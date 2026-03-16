//
//  Models.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import Foundation

enum ClosetTab: String, CaseIterable, Identifiable {
    case wardrobe
    case stylist
    case calendar
    case analytics
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wardrobe: "衣橱"
        case .stylist: "搭配"
        case .calendar: "记录"
        case .analytics: "分析"
        case .profile: "我的"
        }
    }

    var icon: String {
        switch self {
        case .wardrobe: "tshirt"
        case .stylist: "sparkles"
        case .calendar: "calendar"
        case .analytics: "chart.bar"
        case .profile: "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .wardrobe: "tshirt.fill"
        case .stylist: "sparkles"
        case .calendar: "calendar"
        case .analytics: "chart.bar.fill"
        case .profile: "person.fill"
        }
    }
}

enum WardrobeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case top = "上装"
    case bottom = "下装"
    case shoes = "鞋履"
    case dress = "连衣裙"
    case outerwear = "外套"
    case accessory = "配饰"
    case uncategorized = "未分类"

    var id: String { rawValue }
}

enum WardrobeSection: String, CaseIterable, Identifiable, Codable {
    case uncategorized = "未分类"
    case top = "上装"
    case bottom = "下装"
    case dress = "连衣裙"
    case shoes = "鞋履"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .uncategorized: "tray"
        case .top: "tshirt"
        case .bottom: "figure.walk"
        case .dress: "figure.dress.line.vertical.figure"
        case .shoes: "shoeprints.fill"
        }
    }

    var filter: WardrobeFilter {
        switch self {
        case .uncategorized: .uncategorized
        case .top: .top
        case .bottom: .bottom
        case .dress: .dress
        case .shoes: .shoes
        }
    }
}

enum StylistMode: String, CaseIterable, Identifiable, Codable {
    case ai
    case manual

    var id: String { rawValue }
}

enum GarmentGradient: String, CaseIterable, Codable {
    case mist
    case denim
    case cloud
    case sage
}

enum DiaryMatchSource: String, Codable {
    case none
    case autoSuggested
    case autoApplied
    case manuallyAdjusted
}

struct ClosetItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var section: WardrobeSection
    var color: String
    var brand: String
    var price: Int
    var wearCount: Int
    var isArchived: Bool
    var symbol: String
    var gradientName: String
    var imageFileName: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        section: WardrobeSection,
        color: String,
        brand: String,
        price: Int,
        wearCount: Int,
        isArchived: Bool = false,
        symbol: String? = nil,
        gradientName: String,
        imageFileName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.section = section
        self.color = color
        self.brand = brand
        self.price = price
        self.wearCount = wearCount
        self.isArchived = isArchived
        self.symbol = symbol ?? section.symbol
        self.gradientName = gradientName
        self.imageFileName = imageFileName
        self.createdAt = createdAt
    }
}

struct OutfitPreview: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String
    var symbol: String
    var accent: String
    var itemIDs: [UUID]
    var itemLayouts: [OutfitItemLayout]
    var createdAt: Date
    var sourceMode: StylistMode
    var photoFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        symbol: String,
        accent: String,
        itemIDs: [UUID],
        itemLayouts: [OutfitItemLayout] = [],
        createdAt: Date = .now,
        sourceMode: StylistMode,
        photoFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
        self.itemIDs = itemIDs
        self.itemLayouts = itemLayouts
        self.createdAt = createdAt
        self.sourceMode = sourceMode
        self.photoFileName = photoFileName
    }
}

struct OutfitItemLayout: Identifiable, Codable, Equatable {
    var id: UUID { itemID }
    let itemID: UUID
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double

    init(itemID: UUID, x: Double, y: Double, scale: Double = 1.0, rotation: Double = 0) {
        self.itemID = itemID
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
    }
}

struct DiaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var mood: String
    var note: String
    var hasPhoto: Bool
    var photoFileName: String?
    var outfitID: UUID?
    var itemIDs: [UUID]
    var matchSource: DiaryMatchSource

    init(
        id: UUID = UUID(),
        date: Date,
        mood: String,
        note: String,
        hasPhoto: Bool,
        photoFileName: String? = nil,
        outfitID: UUID? = nil,
        itemIDs: [UUID] = [],
        matchSource: DiaryMatchSource = .none
    ) {
        self.id = id
        self.date = date
        self.mood = mood
        self.note = note
        self.hasPhoto = hasPhoto
        self.photoFileName = photoFileName
        self.outfitID = outfitID
        self.itemIDs = itemIDs
        self.matchSource = matchSource
    }
}

struct DiaryMarker: Identifiable {
    let id = UUID()
    let day: Int
    let hasRecord: Bool
    let hasPhoto: Bool
    let hasOutfit: Bool
    let mood: String?
}

struct AnalysisStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let tone: String
}

struct PriceBand: Identifiable {
    let id = UUID()
    let range: String
    let count: Int
    let ratio: Double
}

struct BodyPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var symbol: String
    var imageFileName: String?

    init(id: UUID = UUID(), title: String, symbol: String, imageFileName: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.imageFileName = imageFileName
    }
}

struct ProfileData: Codable, Equatable {
    var name: String
    var heightCm: Int
    var weightKg: Int
    var bodyPhotos: [BodyPhoto]
}

struct WeatherSnapshot: Codable, Equatable {
    var temperature: Int
    var condition: String
    var location: String
    var humidity: Int
    var feelsLike: Int
}

struct ClosetSpace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var wardrobeItems: [ClosetItem]
    var savedLooks: [OutfitPreview]
    var diaryEntries: [DiaryEntry]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        wardrobeItems: [ClosetItem] = [],
        savedLooks: [OutfitPreview] = [],
        diaryEntries: [DiaryEntry] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.wardrobeItems = wardrobeItems
        self.savedLooks = savedLooks
        self.diaryEntries = diaryEntries
        self.createdAt = createdAt
    }
}

struct ClosetSnapshot: Codable {
    var closetSpaces: [ClosetSpace]
    var selectedClosetID: UUID
    var profile: ProfileData
    var weather: WeatherSnapshot

    enum CodingKeys: String, CodingKey {
        case closetSpaces
        case selectedClosetID
        case profile
        case weather
        case wardrobeItems
        case savedLooks
        case diaryEntries
    }

    init(
        closetSpaces: [ClosetSpace],
        selectedClosetID: UUID,
        profile: ProfileData,
        weather: WeatherSnapshot
    ) {
        self.closetSpaces = closetSpaces
        self.selectedClosetID = selectedClosetID
        self.profile = profile
        self.weather = weather
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.profile = try container.decode(ProfileData.self, forKey: .profile)
        self.weather = try container.decode(WeatherSnapshot.self, forKey: .weather)

        if let closetSpaces = try container.decodeIfPresent([ClosetSpace].self, forKey: .closetSpaces),
           let selectedClosetID = try container.decodeIfPresent(UUID.self, forKey: .selectedClosetID),
           !closetSpaces.isEmpty
        {
            self.closetSpaces = closetSpaces
            self.selectedClosetID = selectedClosetID
            return
        }

        let wardrobeItems = try container.decodeIfPresent([ClosetItem].self, forKey: .wardrobeItems) ?? []
        let savedLooks = try container.decodeIfPresent([OutfitPreview].self, forKey: .savedLooks) ?? []
        let diaryEntries = try container.decodeIfPresent([DiaryEntry].self, forKey: .diaryEntries) ?? []
        let legacyCloset = ClosetSpace(
            name: "我的衣橱",
            wardrobeItems: wardrobeItems,
            savedLooks: savedLooks,
            diaryEntries: diaryEntries
        )
        self.closetSpaces = [legacyCloset]
        self.selectedClosetID = legacyCloset.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(closetSpaces, forKey: .closetSpaces)
        try container.encode(selectedClosetID, forKey: .selectedClosetID)
        try container.encode(profile, forKey: .profile)
        try container.encode(weather, forKey: .weather)
    }
}

struct OutfitDraft {
    var title: String = ""
    var itemIDs: Set<UUID> = []
    var itemLayouts: [OutfitItemLayout] = []
    var photoFileName: String?

    init() {}

    init(outfit: OutfitPreview) {
        title = outfit.title
        itemIDs = Set(outfit.itemIDs)
        itemLayouts = outfit.itemLayouts
        photoFileName = outfit.photoFileName
    }
}

struct AddItemDraft {
    var id: UUID?
    var name = ""
    var section: WardrobeSection = .top
    var color = ""
    var brand = ""
    var price = ""
    var gradientName: GarmentGradient = .mist
    var imageFileName: String?

    init() {}

    nonisolated init(item: ClosetItem) {
        id = item.id
        name = item.name
        section = item.section
        color = item.color
        brand = item.brand
        price = item.price > 0 ? "\(item.price)" : ""
        gradientName = GarmentGradient(rawValue: item.gradientName) ?? .mist
        imageFileName = item.imageFileName
    }
}

struct DiaryDraft {
    var mood = "普通"
    var note = ""
    var hasPhoto = false
    var photoFileName: String?
    var outfitID: UUID?
    var itemIDs: [UUID] = []
    var matchSource: DiaryMatchSource = .none
}

struct ProfileDraft {
    var name = ""
    var heightCm = ""
    var weightKg = ""
    var bodyPhotos: [BodyPhoto] = []
}

struct MockClosetDashboard {
    let itemCount: Int
    let wardrobeItems: [ClosetItem]
    let savedLooks: [OutfitPreview]
    let calendarMarkers: [DiaryMarker]
    let stats: [AnalysisStat]
    let priceBands: [PriceBand]
    let bodyPhotos: [BodyPhoto]

    static let sampleSnapshot: ClosetSnapshot = {
        let primaryCloset = ClosetSpace(
            name: "我的衣橱",
            wardrobeItems: [
                ClosetItem(name: "白色短上衣", section: .top, color: "白色", brand: "样衣", price: 129, wearCount: 4, gradientName: "cloud"),
                ClosetItem(name: "黑色短上衣", section: .top, color: "黑色", brand: "样衣", price: 139, wearCount: 2, gradientName: "mist"),
                ClosetItem(name: "灰色短上衣", section: .top, color: "灰色", brand: "样衣", price: 149, wearCount: 3, gradientName: "sage"),
                ClosetItem(name: "米色针织上衣", section: .top, color: "米色", brand: "样衣", price: 169, wearCount: 1, gradientName: "cloud"),
                ClosetItem(name: "蓝色衬衣背面", section: .top, color: "蓝色", brand: "样衣", price: 189, wearCount: 1, gradientName: "denim"),
                ClosetItem(name: "浅蓝牛仔裤", section: .bottom, color: "浅蓝", brand: "样衣", price: 199, wearCount: 5, gradientName: "denim"),
                ClosetItem(name: "深蓝牛仔裤", section: .bottom, color: "深蓝", brand: "样衣", price: 219, wearCount: 2, gradientName: "mist"),
                ClosetItem(name: "黑色连衣裙", section: .dress, color: "黑色", brand: "样衣", price: 259, wearCount: 1, gradientName: "mist"),
                ClosetItem(name: "小白鞋", section: .shoes, color: "白色", brand: "样衣", price: 229, wearCount: 6, gradientName: "cloud")
            ]
        )
        return ClosetSnapshot(
            closetSpaces: [primaryCloset],
            selectedClosetID: primaryCloset.id,
            profile: ProfileData(
                name: "Lumina",
                heightCm: 168,
                weightKg: 60,
                bodyPhotos: [
                    BodyPhoto(title: "正面", symbol: "figure.stand"),
                    BodyPhoto(title: "侧面", symbol: "figure.turn.right"),
                    BodyPhoto(title: "背面", symbol: "figure.stand.line.dotted.figure.stand")
                ]
            ),
            weather: WeatherSnapshot(
                temperature: 7,
                condition: "阴天",
                location: "浙江",
                humidity: 66,
                feelsLike: 4
            )
        )
    }()
}
