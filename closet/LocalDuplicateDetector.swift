//
//  LocalDuplicateDetector.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import Foundation
import UIKit

struct DuplicateCandidate: Identifiable {
    let id: UUID
    let name: String
    let brand: String
    let section: WardrobeSection
    let score: Double
}

enum LocalDuplicateDetector {
    static func detectDuplicates(for imageData: Data, in items: [ClosetItem]) -> [DuplicateCandidate] {
        guard let image = UIImage(data: imageData)?.normalizedForVision else { return [] }

        let targetSignature = ClothingVisualSignature(image: image)
        return items.compactMap { item in
            guard let fileName = item.imageFileName,
                  let referenceImage = LocalImageStore.shared.loadImage(named: fileName)?.normalizedForVision
            else {
                return nil
            }

            let referenceSignature = ClothingVisualSignature(image: referenceImage)
            let score =
                targetSignature.colorSimilarity(to: referenceSignature) * 0.4 +
                targetSignature.histogramSimilarity(to: referenceSignature) * 0.35 +
                targetSignature.ratioSimilarity(to: referenceSignature) * 0.15 +
                targetSignature.edgeSimilarity(to: referenceSignature) * 0.1

            guard score >= 0.82 else { return nil }
            return DuplicateCandidate(
                id: item.id,
                name: item.name,
                brand: item.brand,
                section: item.section,
                score: score
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(3)
        .map { $0 }
    }
}
