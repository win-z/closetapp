//
//  RemoteModels.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum ClothingCategory: String, Codable, CaseIterable, Identifiable {
    case top = "上装"
    case bottom = "下装"
    case dress = "连衣裙"
    case outerwear = "外套"
    case shoes = "鞋履"
    case accessory = "配饰"

    var id: String { rawValue }
}

struct ClothingItem: Codable, Identifiable, Equatable {
    let id: String
    var imageFront: String?
    var category: ClothingCategory
    var name: String
    var color: String
    var brand: String?
    var price: Double?
    var purchaseDate: String?
    var tags: [String]
    var aiAnalysis: ClothingAIAnalysis?
    var lastWorn: String?
    var isArchived: Bool
    var wearCount: Int
}

struct WardrobeItemUpsertRequest: Encodable {
    var imageFront: String?
    var category: ClothingCategory
    var name: String
    var color: String
    var brand: String?
    var price: Double?
    var purchaseDate: String?
    var tags: [String]
}

struct ArchiveClothingItemRequest: Encodable {
    var isArchived: Bool
}

struct AutoTagRequest: Encodable {
    var imageBase64: String
}

struct AutoTagResponse: Decodable, Equatable {
    var category: ClothingCategory?
    var name: String?
    var color: String?
    var brand: String?
    var tags: [String]?
    var aiAnalysis: ClothingAIAnalysis?
}

struct BodyProfile: Codable, Equatable {
    var name: String
    var heightCm: Double
    var weightKg: Double
    var photoFront: String?
    var photoSide: String?
    var photoBack: String?
    var description: String?

    init(
        name: String,
        heightCm: Double,
        weightKg: Double,
        photoFront: String? = nil,
        photoSide: String? = nil,
        photoBack: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.photoFront = photoFront
        self.photoSide = photoSide
        self.photoBack = photoBack
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .nickname)
            ?? ""
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
            ?? Double(try container.decodeIfPresent(Int.self, forKey: .heightCm) ?? 0)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
            ?? Double(try container.decodeIfPresent(Int.self, forKey: .weightKg) ?? 0)
        photoFront = try container.decodeIfPresent(String.self, forKey: .photoFront)
        photoSide = try container.decodeIfPresent(String.self, forKey: .photoSide)
        photoBack = try container.decodeIfPresent(String.self, forKey: .photoBack)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .nickname)
        try container.encode(heightCm, forKey: .heightCm)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encodeIfPresent(photoFront, forKey: .photoFront)
        try container.encodeIfPresent(photoSide, forKey: .photoSide)
        try container.encodeIfPresent(photoBack, forKey: .photoBack)
        try container.encodeIfPresent(description, forKey: .description)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case nickname
        case heightCm
        case weightKg
        case photoFront
        case photoSide
        case photoBack
        case description
    }
}

struct RemoteDiaryEntry: Codable, Identifiable, Equatable {
    let id: String
    var date: String
    var weather: String
    var mood: String
    var notes: String
    var clothingIds: [String]
    var photo: String?
    var outfitId: String?
    var createdAt: String
}

struct DiaryEntryUpsertRequest: Encodable {
    var date: String
    var weather: String
    var mood: String
    var notes: String
    var clothingIds: [String]
    var photo: String?
    var outfitId: String?
}

struct SavedOutfit: Codable, Identifiable, Equatable {
    let id: String
    var name: String?
    var tags: [String]?
    var weather: String?
    var occasion: String?
    var dressId: String?
    var topId: String?
    var bottomId: String?
    var shoesId: String?
    var reasoning: String?
    var tryonImage: String?
    var createdAt: String
}
