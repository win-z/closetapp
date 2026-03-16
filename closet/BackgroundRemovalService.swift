//
//  BackgroundRemovalService.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import simd
import UIKit
@preconcurrency import Vision

struct BackgroundRemovalResult {
    enum FailureReason: String {
        case visionNoInstance = "前景识别没有返回主体实例"
        case visionRejected = "前景识别结果不可用，已回退到原图"
        case simulatorUnsupported = "模拟器上的系统前景抠图不稳定，已回退到原图"
        case solidBackgroundRejected = "纯色背景分离未形成稳定主体"
        case personSegmentationRejected = "人像分割未识别到有效主体"
        case imageDecodeFailed = "图片解析失败"
        case allStrategiesFailed = "所有本地抠图策略都未得到可用结果"
    }

    enum Strategy: String {
        case foregroundMask = "前景主体识别"
        case personSegmentation = "人像分割"
        case solidBackground = "纯色背景分离"
        case originalPreserved = "保留原图"
    }

    let imageData: Data
    let strategy: Strategy
    let didRemoveBackground: Bool
    let failureReason: FailureReason?

    var localizedStatusMessage: String {
        switch strategy {
        case .foregroundMask:
            return "已使用系统前景抠图完成处理"
        case .personSegmentation:
            return didRemoveBackground ? "已使用本地人像分割完成抠图" : "未识别到明确主体，已保留原图"
        case .solidBackground:
            return didRemoveBackground ? "已使用本地纯色背景分离完成抠图" : "未识别到明确主体，已保留原图"
        case .originalPreserved:
            if let failureReason {
                return "未识别到明确主体，已保留原图"
            }
            return "未识别到明确主体，已保留原图"
        }
    }

    var localizedFailureDetail: String? {
        failureReason?.rawValue
    }
}

final class BackgroundRemovalService {
    static let shared = BackgroundRemovalService()

    private init() {}

    func prepareWardrobeImage(from imageData: Data) async -> BackgroundRemovalResult {
        guard let image = UIImage(data: imageData)?.normalizedForVision else {
            return BackgroundRemovalResult(
                imageData: imageData,
                strategy: .originalPreserved,
                didRemoveBackground: false,
                failureReason: .imageDecodeFailed
            )
        }

#if targetEnvironment(simulator)
        return BackgroundRemovalResult(
            imageData: image.optimizedWardrobeUploadData() ?? imageData,
            strategy: .originalPreserved,
            didRemoveBackground: false,
            failureReason: .simulatorUnsupported
        )
#else

        var lastFailureReason: BackgroundRemovalResult.FailureReason?

        if #available(iOS 17.0, *) {
            if let image = await ForegroundMaskRemover().removeBackground(from: image),
               let optimizedData = image.optimizedWardrobeUploadData() {
                return BackgroundRemovalResult(
                    imageData: optimizedData,
                    strategy: .foregroundMask,
                    didRemoveBackground: true,
                    failureReason: nil
                )
            }
            lastFailureReason = .visionRejected
        }

        if let image = SolidBackgroundRemover().removeBackground(from: image),
           let optimizedData = image.optimizedWardrobeUploadData() {
            return BackgroundRemovalResult(
                imageData: optimizedData,
                strategy: .solidBackground,
                didRemoveBackground: true,
                failureReason: nil
            )
        }
        if lastFailureReason == nil {
            lastFailureReason = .solidBackgroundRejected
        }

        if let image = await PersonSegmentationRemover().removeBackground(from: image),
           let optimizedData = image.optimizedWardrobeUploadData() {
            return BackgroundRemovalResult(
                imageData: optimizedData,
                strategy: .personSegmentation,
                didRemoveBackground: true,
                failureReason: nil
            )
        }

        return BackgroundRemovalResult(
            imageData: image.optimizedWardrobeUploadData() ?? imageData,
            strategy: .originalPreserved,
            didRemoveBackground: false,
            failureReason: lastFailureReason ?? .allStrategiesFailed
        )
#endif
    }

    func removeBackgroundIfPossible(from imageData: Data) async -> Data? {
        await prepareWardrobeImage(from: imageData).imageData
    }
}

extension Data {
    func optimizedWardrobeUploadData(maxDimension: CGFloat = 1920, maxBytes: Int = 2_000_000) -> Data? {
        guard let image = UIImage(data: self) else { return self }
        return image.optimizedWardrobeUploadData(maxDimension: maxDimension, maxBytes: maxBytes)
    }
}

@available(iOS 17.0, *)
private final class ForegroundMaskRemover {
    private let ciContext = CIContext()

    func removeBackground(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { [ciContext] in
            guard let cgImage = image.cgImage else { return nil }
            return Self.removeBackground(
                from: image,
                cgImage: cgImage,
                ciContext: ciContext
            )
        }.value
    }

    nonisolated private static func removeBackground(
        from image: UIImage,
        cgImage: CGImage,
        ciContext: CIContext
    ) -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])

            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty
            else {
                return nil
            }

            let mask = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )

            guard let masked = blend(
                original: image,
                maskBuffer: mask,
                ciContext: ciContext
            ) else {
                return nil
            }

            return masked.trimmedToVisibleBounds(paddingRatio: 0.08, minimumInset: 24)
        } catch {
            return nil
        }
    }

    nonisolated private static func blend(original: UIImage, maskBuffer: CVPixelBuffer, ciContext: CIContext) -> UIImage? {
        guard let cgImage = original.cgImage else { return nil }

        let originalCI = CIImage(cgImage: cgImage)
        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
        let scaleX = originalCI.extent.width / maskCI.extent.width
        let scaleY = originalCI.extent.height / maskCI.extent.height
        let scaledMask = maskCI
            .transformed(by: .init(scaleX: scaleX, y: scaleY))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .cropped(to: originalCI.extent)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.maskImage = scaledMask
        filter.backgroundImage = CIImage.empty()

        guard let output = filter.outputImage,
              let cgOutput = ciContext.createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgOutput, scale: original.scale, orientation: .up)
    }
}

private final class PersonSegmentationRemover {
    private let ciContext = CIContext()

    func removeBackground(from image: UIImage) async -> UIImage? {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: nil)
                return
            }

            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8

            DispatchQueue.global(qos: .userInitiated).async { [ciContext] in
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    guard let maskBuffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(
                        returning: Self.blend(
                            original: image,
                            maskBuffer: maskBuffer,
                            ciContext: ciContext
                        )
                    )
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    nonisolated private static func blend(original: UIImage, maskBuffer: CVPixelBuffer, ciContext: CIContext) -> UIImage? {
        guard let cgImage = original.cgImage else { return nil }

        let originalCI = CIImage(cgImage: cgImage)
        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
        let scaleX = originalCI.extent.width / maskCI.extent.width
        let scaleY = originalCI.extent.height / maskCI.extent.height
        let scaledMask = maskCI
            .transformed(by: .init(scaleX: scaleX, y: scaleY))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.4])
            .cropped(to: originalCI.extent)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.maskImage = scaledMask
        filter.backgroundImage = CIImage.empty()

        guard let output = filter.outputImage,
              let cgOutput = ciContext.createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgOutput, scale: original.scale, orientation: .up)
    }
}

private final class SolidBackgroundRemover {
    func removeBackground(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 24, height > 24 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let background = sampleBackgroundColor(from: pixels, width: width, height: height)
        let visitedCount = clearEdgeConnectedBackground(
            in: &pixels,
            width: width,
            height: height,
            background: background
        )

        isolatePrimaryGarment(in: &pixels, width: width, height: height)

        let totalPixels = width * height
        let clearedRatio = Double(visitedCount) / Double(totalPixels)
        guard clearedRatio > 0.04 && clearedRatio < 0.985 else { return nil }

        softenEdges(in: &pixels, width: width, height: height)

        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    private func sampleBackgroundColor(from pixels: [UInt8], width: Int, height: Int) -> SIMD3<Double> {
        let sampleInset = max(min(width, height) / 12, 6)
        let samplePoints = [
            (x: sampleInset, y: sampleInset),
            (x: width - sampleInset - 1, y: sampleInset),
            (x: sampleInset, y: height - sampleInset - 1),
            (x: width - sampleInset - 1, y: height - sampleInset - 1),
            (x: width / 2, y: sampleInset),
            (x: width / 2, y: height - sampleInset - 1)
        ]

        var red = 0.0
        var green = 0.0
        var blue = 0.0

        for point in samplePoints {
            let index = (point.y * width + point.x) * 4
            red += Double(pixels[index])
            green += Double(pixels[index + 1])
            blue += Double(pixels[index + 2])
        }

        let count = Double(samplePoints.count)
        return SIMD3(red / count, green / count, blue / count)
    }

    private func clearEdgeConnectedBackground(
        in pixels: inout [UInt8],
        width: Int,
        height: Int,
        background: SIMD3<Double>
    ) -> Int {
        var queue: [(x: Int, y: Int)] = []
        var visited = [Bool](repeating: false, count: width * height)

        func enqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = y * width + x
            guard !visited[offset] else { return }
            visited[offset] = true
            queue.append((x, y))
        }

        for x in 0..<width {
            enqueue(x, 0)
            enqueue(x, height - 1)
        }
        for y in 0..<height {
            enqueue(0, y)
            enqueue(width - 1, y)
        }

        var cleared = 0
        var index = 0

        while index < queue.count {
            let point = queue[index]
            index += 1

            let pixelIndex = (point.y * width + point.x) * 4
            let alpha = pixels[pixelIndex + 3]
            if alpha == 0 { continue }

            let color = SIMD3(
                Double(pixels[pixelIndex]),
                Double(pixels[pixelIndex + 1]),
                Double(pixels[pixelIndex + 2])
            )

            let distance = simd_distance(color, background)
            let backgroundLuminance = (background.x + background.y + background.z) / 3.0
            let luminance = (color.x + color.y + color.z) / 3.0
            let luminanceDelta = abs(luminance - backgroundLuminance)
            let backgroundIsNearWhite = backgroundLuminance > 235
            let isBackground =
                distance < 54 ||
                (distance < 72 && luminanceDelta < 24) ||
                (backgroundIsNearWhite && distance < 96 && luminance > 214)
            guard isBackground else { continue }

            pixels[pixelIndex + 3] = 0
            cleared += 1

            enqueue(point.x + 1, point.y)
            enqueue(point.x - 1, point.y)
            enqueue(point.x, point.y + 1)
            enqueue(point.x, point.y - 1)
        }

        return cleared
    }

    private func isolatePrimaryGarment(in pixels: inout [UInt8], width: Int, height: Int) {
        var visited = [Bool](repeating: false, count: width * height)
        var bestComponent: [Int] = []
        let center = SIMD2<Double>(Double(width) / 2.0, Double(height) / 2.0)

        func alpha(at index: Int) -> UInt8 {
            pixels[index * 4 + 3]
        }

        func componentScore(indices: [Int]) -> Double {
            guard !indices.isEmpty else { return 0 }
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var sumX = 0.0
            var sumY = 0.0

            for index in indices {
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                sumX += Double(x)
                sumY += Double(y)
            }

            let count = Double(indices.count)
            let centroid = SIMD2(sumX / count, sumY / count)
            let distanceToCenter = simd_distance(centroid, center)
            let normalizedCenterBias = 1.0 - min(distanceToCenter / (Double(max(width, height)) * 0.6), 1.0)
            let boundingArea = Double((maxX - minX + 1) * (maxY - minY + 1))
            return count * 1.0 + boundingArea * 0.08 + normalizedCenterBias * count * 0.35
        }

        for start in 0..<(width * height) {
            guard !visited[start], alpha(at: start) > 0 else { continue }

            var queue = [start]
            var component: [Int] = []
            visited[start] = true
            var pointer = 0

            while pointer < queue.count {
                let current = queue[pointer]
                pointer += 1
                component.append(current)

                let x = current % width
                let y = current / width
                let neighbors = [
                    (x + 1, y), (x - 1, y),
                    (x, y + 1), (x, y - 1)
                ]

                for (nx, ny) in neighbors where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let next = ny * width + nx
                    guard !visited[next], alpha(at: next) > 0 else { continue }
                    visited[next] = true
                    queue.append(next)
                }
            }

            if componentScore(indices: component) > componentScore(indices: bestComponent) {
                bestComponent = component
            }
        }

        guard !bestComponent.isEmpty else { return }
        let keep = Set(bestComponent)
        for index in 0..<(width * height) where !keep.contains(index) {
            pixels[index * 4 + 3] = 0
        }
    }

    private func softenEdges(in pixels: inout [UInt8], width: Int, height: Int) {
        guard width > 2, height > 2 else { return }
        var softened = pixels

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = (y * width + x) * 4
                let alpha = pixels[index + 3]
                guard alpha > 0 else { continue }

                var transparentNeighbors = 0
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let neighborIndex = ((y + dy) * width + (x + dx)) * 4
                        if pixels[neighborIndex + 3] == 0 {
                            transparentNeighbors += 1
                        }
                    }
                }

                if transparentNeighbors >= 3 {
                    softened[index + 3] = UInt8(max(96, Int(alpha) - transparentNeighbors * 18))
                }
            }
        }

        pixels = softened
    }
}

extension UIImage {
    var normalizedForVision: UIImage? {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func optimizedWardrobeUploadData(maxDimension: CGFloat = 1920, maxBytes: Int = 2_000_000) -> Data? {
        let resizedImage = resizedForUpload(maxDimension: maxDimension)

        if resizedImage.hasTransparentAlpha {
            if let transparentData = resizedImage.bestEffortTransparentData(maxBytes: maxBytes) {
                return transparentData
            }
            return resizedImage.pngData()
        }

        var compression: CGFloat = 0.82
        while compression >= 0.4 {
            if let data = resizedImage.jpegData(compressionQuality: compression), data.count <= maxBytes {
                return data
            }
            compression -= 0.08
        }

        return resizedImage.jpegData(compressionQuality: 0.32)
    }

    private func bestEffortTransparentData(maxBytes: Int) -> Data? {
        if let pngData = pngData(), pngData.count <= maxBytes {
            return pngData
        }

        var candidate = self
        for _ in 0..<6 {
            let nextSize = CGSize(
                width: max(candidate.size.width * 0.85, 320),
                height: max(candidate.size.height * 0.85, 320)
            )
            candidate = candidate.resized(to: nextSize)
            if let pngData = candidate.pngData(), pngData.count <= maxBytes {
                return pngData
            }
        }

        return candidate.pngData()
    }

    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let currentMaxDimension = max(size.width, size.height)
        guard currentMaxDimension > maxDimension else { return self }

        let scaleRatio = maxDimension / currentMaxDimension
        let targetSize = CGSize(width: size.width * scaleRatio, height: size.height * scaleRatio)
        return resized(to: targetSize)
    }

    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    var hasTransparentAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    func trimmedToVisibleBounds(paddingRatio: CGFloat = 0.08, minimumInset: CGFloat = 24) -> UIImage? {
        guard let cgImage = cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return self }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                let alpha = Int(pixels[index + 3])
                guard alpha > 28 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY else { return self }

        let padding = max(minimumInset, CGFloat(max(width, height)) * paddingRatio)
        let cropRect = CGRect(
            x: max(0, CGFloat(minX) - padding),
            y: max(0, CGFloat(minY) - padding),
            width: min(CGFloat(width), CGFloat(maxX - minX + 1) + padding * 2),
            height: min(CGFloat(height), CGFloat(maxY - minY + 1) + padding * 2)
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}
