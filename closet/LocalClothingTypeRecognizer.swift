//
//  LocalClothingTypeRecognizer.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import UIKit
@preconcurrency import Vision

struct LocalClothingTypeRecognition {
    let section: WardrobeSection?
    let confidence: Float

    var isConfident: Bool {
        guard section != nil else { return false }
        return confidence >= 0.55
    }
}

final class LocalClothingTypeRecognizer {
    static let shared = LocalClothingTypeRecognizer()

    private init() {}

    func recognizeSection(from image: UIImage?) async -> LocalClothingTypeRecognition {
        guard let image, let cgImage = image.cgImage else {
            return LocalClothingTypeRecognition(section: nil, confidence: 0)
        }

        let heuristic = heuristicSection(for: image)
        let visionRecognition = await classifyWithVision(cgImage: cgImage)

        if let visionRecognition, visionRecognition.confidence >= 0.55 {
            return visionRecognition
        }

        return heuristic
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
                        if let section = Self.mapIdentifierToSection(observation.identifier) {
                            continuation.resume(returning: LocalClothingTypeRecognition(section: section, confidence: observation.confidence))
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
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let landscapeRatio = width / height
        let portraitRatio = height / width

        if landscapeRatio > 1.28 {
            return LocalClothingTypeRecognition(section: .shoes, confidence: 0.62)
        }
        if portraitRatio > 1.9 {
            return LocalClothingTypeRecognition(section: .bottom, confidence: 0.58)
        }
        if portraitRatio > 1.18 {
            return LocalClothingTypeRecognition(section: .top, confidence: 0.6)
        }
        if portraitRatio > 0.92 {
            return LocalClothingTypeRecognition(section: .dress, confidence: 0.52)
        }

        return LocalClothingTypeRecognition(section: nil, confidence: 0.2)
    }

    private static func mapIdentifierToSection(_ identifier: String) -> WardrobeSection? {
        let value = identifier.lowercased()

        let mapping: [(WardrobeSection, [String])] = [
            (.dress, ["dress", "gown", "robe"]),
            (.shoes, ["shoe", "sneaker", "boot", "sandal", "slipper", "loafer", "heel", "footwear"]),
            (.bottom, ["jean", "pants", "trousers", "shorts", "skirt", "leggings"]),
            (.top, ["shirt", "t-shirt", "tee", "top", "blouse", "sweater", "hoodie", "jacket", "coat", "outerwear", "cardigan"])
        ]

        for (section, keywords) in mapping {
            if keywords.contains(where: { value.contains($0) }) {
                return section
            }
        }

        return nil
    }
}
