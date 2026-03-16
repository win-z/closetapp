//
//  LocalOutfitMatcher.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import UIKit
@preconcurrency import Vision

struct LocalOutfitMatchResult {
    struct MatchedItem: Identifiable, Codable {
        let id: UUID
        let section: WardrobeSection
        let confidence: Double
    }

    let outfitID: UUID?
    let itemIDs: [UUID]
    let summary: String
    let matchedItems: [MatchedItem]
    let qualityWarning: String?

    var hasMatch: Bool {
        outfitID != nil || !itemIDs.isEmpty
    }
}

final class LocalOutfitMatcher {
    static let shared = LocalOutfitMatcher()

    private let featureCache = LocalImageFeatureCache()
    private let resultCache = LocalDiaryMatchCache()

    private init() {}

    func matchDiaryPhoto(
        _ imageData: Data,
        wardrobeItems: [ClosetItem],
        savedLooks: [OutfitPreview]
    ) async -> LocalOutfitMatchResult {
        let imageHash = imageData.sha256Key
        let wardrobeSignature = wardrobeItems.map(\.id.uuidString).sorted().joined(separator: "|")
        if let cached = await resultCache.result(for: imageHash, wardrobeSignature: wardrobeSignature) {
            return cached
        }

        guard let diaryImage = UIImage(data: imageData)?.normalizedForVision else {
            return LocalOutfitMatchResult(outfitID: nil, itemIDs: [], summary: "未找到可匹配衣物", matchedItems: [], qualityWarning: nil)
        }

        let sceneDiagnosis = await DiarySceneDiagnosisDetector.shared.analyze(image: diaryImage)
        if sceneDiagnosis.hasMultiplePeople {
            return LocalOutfitMatchResult(
                outfitID: nil,
                itemIDs: [],
                summary: "检测到多人同框，请手动选择衣物",
                matchedItems: [],
                qualityWarning: "多人照片容易把别人的衣服一起算进去，已停止自动匹配。"
            )
        }

        let bodyRect = await PersonBodyRectDetector.shared.detect(in: diaryImage)
        guard bodyRect != nil else {
            return LocalOutfitMatchResult(
                outfitID: nil,
                itemIDs: [],
                summary: "未检测到清晰人像，请手动选择衣物",
                matchedItems: [],
                qualityWarning: "当前照片里人物主体不够清晰，自动匹配已跳过。"
            )
        }
        let diaryRegions = DiaryImageRegions(sourceImage: diaryImage, bodyRect: bodyRect)
        var matchedCandidates: [ItemMatchCandidate] = []

        for item in wardrobeItems {
            guard let fileName = item.imageFileName,
                  let referenceImage = LocalImageStore.shared.loadImage(named: fileName)?.normalizedForVision
            else {
                continue
            }

            let persistedSignature = await LocalWardrobeFeatureStore.shared.signature(for: fileName)

            let regionImage = diaryRegions.image(for: item.section) ?? diaryImage
            if let candidate = await match(
                item: item,
                referenceImage: referenceImage,
                persistedSignature: persistedSignature,
                diaryRegionImage: regionImage,
                cacheKey: fileName
            ) {
                matchedCandidates.append(candidate)
            }
        }

        let bestBySection = Dictionary(grouping: matchedCandidates, by: \.section)
            .compactMapValues { candidates in
                candidates.max { $0.score < $1.score }
            }

        let matchedItems = bestBySection.values
            .sorted { $0.score > $1.score }
            .map(\.itemID)
        let matchedDetails = bestBySection.values
            .sorted { $0.score > $1.score }
            .map {
                LocalOutfitMatchResult.MatchedItem(
                    id: $0.itemID,
                    section: $0.section,
                    confidence: $0.score
                )
            }

        let matchedOutfit = savedLooks
            .map { look in
                (outfitID: look.id, overlap: look.itemIDs.filter { matchedItems.contains($0) }.count)
            }
            .filter { $0.overlap > 0 }
            .max { lhs, rhs in lhs.overlap < rhs.overlap }

        let summary: String
        if let matchedOutfit, matchedOutfit.overlap >= 2 {
            summary = "已本地匹配到现有穿搭"
        } else if !matchedItems.isEmpty {
            summary = "已本地识别 \(matchedItems.count) 件衣物"
        } else {
            summary = "未找到可匹配衣物"
        }

        let result = LocalOutfitMatchResult(
            outfitID: (matchedOutfit?.overlap ?? 0) >= 2 ? matchedOutfit?.outfitID : nil,
            itemIDs: matchedItems,
            summary: summary,
            matchedItems: matchedDetails,
            qualityWarning: sceneDiagnosis.isLikelyMirrorSelfie ? "疑似自拍或镜像自拍，请确认鞋区和下装是否识别准确。" : nil
        )
        await resultCache.store(result, for: imageHash, wardrobeSignature: wardrobeSignature)
        return result
    }

    private func match(
        item: ClosetItem,
        referenceImage: UIImage,
        persistedSignature: PersistedWardrobeSignature?,
        diaryRegionImage: UIImage,
        cacheKey: String
    ) async -> ItemMatchCandidate? {
        let referenceSignature = persistedSignature?.runtimeSignature ?? ClothingVisualSignature(image: referenceImage)
        let regionSignature = ClothingVisualSignature(image: diaryRegionImage)
        let colorScore = regionSignature.colorSimilarity(to: referenceSignature)
        let shapeScore = regionSignature.ratioSimilarity(to: referenceSignature)
        let histogramScore = regionSignature.histogramSimilarity(to: referenceSignature)
        let edgeScore = regionSignature.edgeSimilarity(to: referenceSignature)

        let featureDistance = await featureDistance(
            referenceImage: referenceImage,
            regionImage: diaryRegionImage,
            cacheKey: cacheKey
        )
        let featureScore = max(0.0, 1.0 - Double(featureDistance) * 6.0)
        let weightedFeature = featureScore * 0.48
        let weightedColor = colorScore * 0.16
        let weightedShape = shapeScore * 0.1
        let weightedHistogram = histogramScore * 0.18
        let weightedEdge = edgeScore * 0.08
        let combinedScore = weightedFeature + weightedColor + weightedShape + weightedHistogram + weightedEdge
        guard combinedScore >= 0.52 else { return nil }

        return ItemMatchCandidate(itemID: item.id, section: item.section, score: combinedScore)
    }

    private func featureDistance(
        referenceImage: UIImage,
        regionImage: UIImage,
        cacheKey: String
    ) async -> Float {
        guard let regionPrint = await generateFeaturePrint(for: regionImage) else { return 1 }

        let referencePrint: VNFeaturePrintObservation?
        if let cached = await featureCache.featurePrint(for: cacheKey) {
            referencePrint = cached
        } else {
            let generated = await generateFeaturePrint(for: referenceImage)
            if let generated {
                await featureCache.store(generated, for: cacheKey)
            }
            referencePrint = generated
        }

        guard let referencePrint else { return 1 }
        var distance: Float = 1
        try? referencePrint.computeDistance(&distance, to: regionPrint)
        return distance
    }

    private func generateFeaturePrint(for image: UIImage) async -> VNFeaturePrintObservation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private actor LocalImageFeatureCache {
    private var storage: [String: VNFeaturePrintObservation] = [:]

    func featurePrint(for key: String) -> VNFeaturePrintObservation? {
        storage[key]
    }

    func store(_ observation: VNFeaturePrintObservation, for key: String) {
        storage[key] = observation
    }
}

private actor LocalDiaryMatchCache {
    private var storage: [String: LocalOutfitMatchResult] = [:]
    private let storageKey = "closet.local-diary-match-cache.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: PersistedMatchResult].self, from: data) {
            storage = decoded.reduce(into: [:]) { partial, element in
                partial[element.key] = element.value.asRuntimeResult
            }
        }
    }

    func result(for imageHash: String, wardrobeSignature: String) -> LocalOutfitMatchResult? {
        storage["\(imageHash)|\(wardrobeSignature)"]
    }

    func store(_ result: LocalOutfitMatchResult, for imageHash: String, wardrobeSignature: String) {
        storage["\(imageHash)|\(wardrobeSignature)"] = result
        persist()
    }

    func clear() {
        storage = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist() {
        let payload = storage.mapValues { PersistedMatchResult(runtime: $0) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

final class LocalWardrobeFeatureStore {
    static let shared = LocalWardrobeFeatureStore()

    private let storageKey = "closet.local-wardrobe-signatures.v1"
    private var storage: [String: PersistedWardrobeSignature] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: PersistedWardrobeSignature].self, from: data) {
            storage = decoded
        }
    }

    func signature(for fileName: String) async -> PersistedWardrobeSignature? {
        storage[fileName]
    }

    func precomputeFeatureIfNeeded(for item: ClosetItem) {
        guard let fileName = item.imageFileName,
              storage[fileName] == nil,
              let image = LocalImageStore.shared.loadImage(named: fileName)?.normalizedForVision
        else {
            return
        }

        storage[fileName] = PersistedWardrobeSignature(signature: ClothingVisualSignature(image: image))
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func removeSignatures(except fileNames: Set<String>) {
        storage = storage.filter { fileNames.contains($0.key) }
        persist()
    }
}

private struct PersistedMatchResult: Codable {
    let outfitID: UUID?
    let itemIDs: [UUID]
    let summary: String
    let matchedItems: [LocalOutfitMatchResult.MatchedItem]
    let qualityWarning: String?

    nonisolated init(runtime: LocalOutfitMatchResult) {
        outfitID = runtime.outfitID
        itemIDs = runtime.itemIDs
        summary = runtime.summary
        matchedItems = runtime.matchedItems
        qualityWarning = runtime.qualityWarning
    }

    nonisolated var asRuntimeResult: LocalOutfitMatchResult {
        LocalOutfitMatchResult(
            outfitID: outfitID,
            itemIDs: itemIDs,
            summary: summary,
            matchedItems: matchedItems,
            qualityWarning: qualityWarning
        )
    }
}

private struct DiarySceneDiagnosis {
    let hasMultiplePeople: Bool
    let isLikelyMirrorSelfie: Bool
}

private final class DiarySceneDiagnosisDetector {
    static let shared = DiarySceneDiagnosisDetector()

    private init() {}

    func analyze(image: UIImage) async -> DiarySceneDiagnosis {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: DiarySceneDiagnosis(hasMultiplePeople: false, isLikelyMirrorSelfie: false))
                    return
                }

                let faceRequest = VNDetectFaceRectanglesRequest()
                let bodyRequest = VNDetectHumanRectanglesRequest()
                bodyRequest.upperBodyOnly = false

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([faceRequest, bodyRequest])
                    let faceCount = faceRequest.results?.count ?? 0
                    let bodyCount = bodyRequest.results?.count ?? 0
                    let multiplePeople = max(faceCount, bodyCount) > 1

                    let faceBox = faceRequest.results?.first?.boundingBox ?? .zero
                    let likelyMirrorSelfie =
                        faceCount == 1 &&
                        bodyCount <= 1 &&
                        faceBox.height > 0.18 &&
                        faceBox.maxY > 0.72

                    continuation.resume(
                        returning: DiarySceneDiagnosis(
                            hasMultiplePeople: multiplePeople,
                            isLikelyMirrorSelfie: likelyMirrorSelfie
                        )
                    )
                } catch {
                    continuation.resume(returning: DiarySceneDiagnosis(hasMultiplePeople: false, isLikelyMirrorSelfie: false))
                }
            }
        }
    }
}

private struct ItemMatchCandidate {
    let itemID: UUID
    let section: WardrobeSection
    let score: Double
}

struct PersistedWardrobeSignature: Codable {
    let averageRed: CGFloat
    let averageGreen: CGFloat
    let averageBlue: CGFloat
    let aspectRatio: CGFloat
    let histogram: [CGFloat]
    let edgeDensity: CGFloat

    init(signature: ClothingVisualSignature) {
        averageRed = signature.averageColor.red
        averageGreen = signature.averageColor.green
        averageBlue = signature.averageColor.blue
        aspectRatio = signature.aspectRatio
        histogram = signature.histogram
        edgeDensity = signature.edgeDensity
    }

    var runtimeSignature: ClothingVisualSignature {
        ClothingVisualSignature(
            averageColor: (averageRed, averageGreen, averageBlue),
            aspectRatio: aspectRatio,
            histogram: histogram,
            edgeDensity: edgeDensity
        )
    }
}

private struct DiaryImageRegions {
    let top: UIImage?
    let bottom: UIImage?
    let shoes: UIImage?

    init(sourceImage: UIImage, bodyRect: CGRect?) {
        let width = sourceImage.size.width
        let height = sourceImage.size.height
        let targetRect = bodyRect ?? CGRect(x: 0, y: height * 0.06, width: width, height: height * 0.9)

        let expandedX = max(0, targetRect.minX - targetRect.width * 0.08)
        let expandedWidth = min(width - expandedX, targetRect.width * 1.16)
        let expandedRect = CGRect(
            x: expandedX,
            y: max(0, targetRect.minY - targetRect.height * 0.04),
            width: expandedWidth,
            height: min(height, targetRect.height * 1.08)
        )

        top = sourceImage.cropped(
            to: CGRect(
                x: expandedRect.minX,
                y: expandedRect.minY,
                width: expandedRect.width,
                height: expandedRect.height * 0.42
            )
        )
        bottom = sourceImage.cropped(
            to: CGRect(
                x: expandedRect.minX,
                y: expandedRect.minY + expandedRect.height * 0.4,
                width: expandedRect.width,
                height: expandedRect.height * 0.34
            )
        )
        shoes = sourceImage.cropped(
            to: CGRect(
                x: expandedRect.minX,
                y: expandedRect.minY + expandedRect.height * 0.72,
                width: expandedRect.width,
                height: expandedRect.height * 0.24
            )
        )
    }

    func image(for section: WardrobeSection) -> UIImage? {
        switch section {
        case .uncategorized:
            nil
        case .top, .dress:
            top
        case .bottom:
            bottom
        case .shoes:
            shoes
        }
    }
}

private final class PersonBodyRectDetector {
    static let shared = PersonBodyRectDetector()

    private init() {}

    func detect(in image: UIImage) async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    guard let buffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: Self.bodyRect(from: buffer, imageSize: image.size))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func bodyRect(from pixelBuffer: CVPixelBuffer, imageSize: CGSize) -> CGRect? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let threshold: UInt8 = 24

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                if row[x] > threshold {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard found, maxX > minX, maxY > minY else { return nil }

        let scaleX = imageSize.width / CGFloat(width)
        let scaleY = imageSize.height / CGFloat(height)
        return CGRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX) * scaleX,
            height: CGFloat(maxY - minY) * scaleY
        )
    }
}

struct ClothingVisualSignature {
    let averageColor: (red: CGFloat, green: CGFloat, blue: CGFloat)
    let aspectRatio: CGFloat
    let histogram: [CGFloat]
    let edgeDensity: CGFloat

    init(image: UIImage) {
        self.averageColor = image.averageColorComponents
        self.aspectRatio = max(image.size.width, 1) / max(image.size.height, 1)
        self.histogram = image.colorHistogram
        self.edgeDensity = image.edgeDensity
    }

    init(
        averageColor: (CGFloat, CGFloat, CGFloat),
        aspectRatio: CGFloat,
        histogram: [CGFloat],
        edgeDensity: CGFloat
    ) {
        self.averageColor = (averageColor.0, averageColor.1, averageColor.2)
        self.aspectRatio = aspectRatio
        self.histogram = histogram
        self.edgeDensity = edgeDensity
    }

    func colorSimilarity(to other: ClothingVisualSignature) -> Double {
        let colorDistance = sqrt(
            pow(averageColor.red - other.averageColor.red, 2) +
            pow(averageColor.green - other.averageColor.green, 2) +
            pow(averageColor.blue - other.averageColor.blue, 2)
        )
        return max(0, 1 - Double(colorDistance) * 1.35)
    }

    func ratioSimilarity(to other: ClothingVisualSignature) -> Double {
        let ratioDistance = abs(aspectRatio - other.aspectRatio)
        return max(0, 1 - Double(ratioDistance) * 0.8)
    }

    func histogramSimilarity(to other: ClothingVisualSignature) -> Double {
        guard histogram.count == other.histogram.count, !histogram.isEmpty else { return 0 }
        let distance = zip(histogram, other.histogram).reduce(CGFloat.zero) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        return max(0, 1 - Double(distance) * 0.5)
    }

    func edgeSimilarity(to other: ClothingVisualSignature) -> Double {
        let distance = abs(edgeDensity - other.edgeDensity)
        return max(0, 1 - Double(distance) * 3.2)
    }
}

private extension UIImage {
    func cropped(to rect: CGRect) -> UIImage? {
        guard let cgImage else { return nil }

        let scaleRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        ).integral

        guard let cropped = cgImage.cropping(to: scaleRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

private extension Data {
    var sha256Key: String {
        String(hashValue)
    }
}
