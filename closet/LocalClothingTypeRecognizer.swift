//
//  LocalClothingTypeRecognizer.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import UIKit
@preconcurrency import Vision

struct LocalClothingTypeRecognition {
    let category: ClothingCategory?
    let section: WardrobeSection?
    let typeName: String?
    let confidence: Float

    var isConfident: Bool {
        guard section != nil else { return false }
        return confidence >= 0.55
    }
}

struct LocalClothingAutoTagResult {
    let section: WardrobeSection
    let category: ClothingCategory
    let typeName: String
    let color: String
    let suggestedName: String
    let tags: [String]
    let confidence: Float
}

final class LocalClothingTypeRecognizer {
    static let shared = LocalClothingTypeRecognizer()

    private init() {}

    func recognizeSection(from image: UIImage?) async -> LocalClothingTypeRecognition {
        guard let image, let cgImage = image.cgImage else {
            return LocalClothingTypeRecognition(category: nil, section: nil, typeName: nil, confidence: 0)
        }

        let heuristic = heuristicSection(for: image)
        let visionRecognition = await classifyWithVision(cgImage: cgImage)

        if let visionRecognition, visionRecognition.confidence >= 0.55 {
            return visionRecognition
        }

        return heuristic
    }

    func recognizeAttributes(from image: UIImage?) async -> LocalClothingAutoTagResult {
        let recognition = await recognizeSection(from: image)
        let category = recognition.isConfident ? (recognition.category ?? .top) : .top
        let section = recognition.isConfident ? (recognition.section ?? .uncategorized) : .uncategorized
        let color = WardrobeSection.heuristicColorName(for: image)
        let typeName = resolvedTypeName(
            for: section,
            category: category,
            recognizedTypeName: recognition.typeName
        )
        let tags = tags(for: category, typeName: typeName)

        return LocalClothingAutoTagResult(
            section: section,
            category: category,
            typeName: typeName,
            color: color,
            suggestedName: suggestedName(for: color, typeName: typeName),
            tags: tags,
            confidence: recognition.confidence
        )
    }

    private func classifyWithVision(cgImage: CGImage) async -> LocalClothingTypeRecognition? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    let observations = request.results ?? []

                    for observation in observations.prefix(12) {
                        if let mapping = Self.mapIdentifier(observation.identifier) {
                            continuation.resume(returning: LocalClothingTypeRecognition(
                                category: mapping.category,
                                section: mapping.section,
                                typeName: mapping.typeName,
                                confidence: observation.confidence
                            ))
                            return
                        }
                    }

                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func heuristicSection(for image: UIImage) -> LocalClothingTypeRecognition {
        let silhouette = image.foregroundSilhouetteMetrics
        let landscapeRatio = silhouette.widthToHeightRatio
        let portraitRatio = silhouette.heightToWidthRatio

        if landscapeRatio > 1.28 {
            return LocalClothingTypeRecognition(category: .shoes, section: .shoes, typeName: "鞋履", confidence: 0.62)
        }
        if portraitRatio > 1.85 && silhouette.bottomHalfFillRatio < 0.58 {
            return LocalClothingTypeRecognition(category: .bottom, section: .bottom, typeName: "长裤", confidence: 0.58)
        }
        if portraitRatio > 1.35 &&
            silhouette.bottomHalfFillRatio > 0.6 &&
            silhouette.bottomWidthRatio > silhouette.topWidthRatio * 1.12 {
            return LocalClothingTypeRecognition(category: .dress, section: .dress, typeName: "连衣裙", confidence: 0.6)
        }
        if portraitRatio > 0.9 {
            return LocalClothingTypeRecognition(category: .top, section: .top, typeName: "上装", confidence: 0.6)
        }

        return LocalClothingTypeRecognition(category: nil, section: nil, typeName: nil, confidence: 0.2)
    }

    private func resolvedTypeName(
        for section: WardrobeSection,
        category: ClothingCategory,
        recognizedTypeName: String?
    ) -> String {
        if let recognizedTypeName, !recognizedTypeName.isEmpty {
            return recognizedTypeName
        }

        switch category {
        case .outerwear:
            return "外套"
        case .accessory:
            return "配饰"
        case .top, .bottom, .dress, .shoes:
            break
        }

        switch section {
        case .uncategorized:
            return "单品"
        case .top:
            return "上装"
        case .bottom:
            return "下装"
        case .dress:
            return "连衣裙"
        case .shoes:
            return "鞋履"
        }
    }

    private func suggestedName(for color: String, typeName: String) -> String {
        let prefixlessTypes: Set<String> = ["小白鞋"]
        if prefixlessTypes.contains(typeName) {
            return typeName
        }

        return "\(color)\(typeName)"
    }

    private func tags(for category: ClothingCategory, typeName: String) -> [String] {
        let primaryTag = category.rawValue
        if typeName == primaryTag {
            return [primaryTag]
        }
        return [primaryTag, typeName]
    }

    private static func mapIdentifier(_ identifier: String) -> (category: ClothingCategory, section: WardrobeSection?, typeName: String)? {
        let value = identifier.lowercased()

        let mapping: [(ClothingCategory, WardrobeSection?, String, [String])] = [
            (.accessory, nil, "托特包", ["tote", "shopper"]),
            (.accessory, nil, "单肩包", ["shoulder bag"]),
            (.accessory, nil, "斜挎包", ["crossbody", "messenger bag"]),
            (.accessory, nil, "手提包", ["handbag", "purse"]),
            (.accessory, nil, "双肩包", ["backpack", "rucksack"]),
            (.accessory, nil, "帽子", ["hat", "cap", "beanie", "beret"]),
            (.accessory, nil, "项链", ["necklace", "pendant"]),
            (.accessory, nil, "耳饰", ["earring", "earrings"]),
            (.accessory, nil, "手链", ["bracelet", "bangle"]),
            (.accessory, nil, "戒指", ["ring"]),
            (.accessory, nil, "围巾", ["scarf"]),
            (.accessory, nil, "腰带", ["belt"]),
            (.accessory, nil, "太阳镜", ["sunglasses", "glasses", "eyewear"]),
            (.accessory, nil, "包", ["bag"]),
            (.dress, .dress, "连衣裙", ["dress", "gown", "robe"]),
            (.shoes, .shoes, "小白鞋", ["white sneaker"]),
            (.shoes, .shoes, "运动鞋", ["sneaker", "trainer"]),
            (.shoes, .shoes, "靴子", ["boot"]),
            (.shoes, .shoes, "凉鞋", ["sandal", "slipper"]),
            (.shoes, .shoes, "高跟鞋", ["heel", "pump"]),
            (.shoes, .shoes, "乐福鞋", ["loafer"]),
            (.shoes, .shoes, "鞋履", ["shoe", "footwear"]),
            (.bottom, .bottom, "牛仔裤", ["jean", "denim"]),
            (.bottom, .bottom, "短裤", ["shorts"]),
            (.bottom, .bottom, "半身裙", ["skirt"]),
            (.bottom, .bottom, "打底裤", ["leggings"]),
            (.bottom, .bottom, "长裤", ["pants", "trousers"]),
            (.top, .top, "T恤", ["t-shirt", "tee"]),
            (.top, .top, "衬衫", ["shirt", "blouse"]),
            (.top, .top, "针织衫", ["sweater", "knitwear"]),
            (.top, .top, "卫衣", ["hoodie", "sweatshirt"]),
            (.outerwear, .top, "西装外套", ["blazer"]),
            (.outerwear, .top, "大衣", ["coat"]),
            (.outerwear, .top, "夹克", ["jacket"]),
            (.outerwear, .top, "开衫", ["cardigan"]),
            (.outerwear, .top, "外套", ["outerwear"]),
            (.top, .top, "上装", ["top"])
        ]

        for (category, section, typeName, keywords) in mapping {
            if keywords.contains(where: { value.contains($0) }) {
                return (category, section, typeName)
            }
        }

        return nil
    }
}
