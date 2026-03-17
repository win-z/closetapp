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
    case outerwear = "外套"
    case dress = "连衣裙"
    case shoes = "鞋子"
    case hat = "帽子"
    case accessory = "饰品"
    case bag = "包"
    case uncategorized = "未分类"

    var id: String { rawValue }

    static var allCases: [WardrobeFilter] {
        [.all, .top, .bottom, .outerwear, .dress, .shoes, .hat, .accessory, .bag, .uncategorized]
    }
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

enum OutfitSceneFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case daily = "日常"
    case commute = "通勤"
    case date = "约会"
    case party = "聚会"
    case outing = "出游"
    case sport = "运动"
    case formal = "正式"
    case vacation = "度假"
    case uncategorized = "未分类"

    var id: String { rawValue }

    static func from(category: String?) -> OutfitSceneFilter {
        guard let category = category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty else {
            return .uncategorized
        }

        if category.contains("通勤") { return .commute }
        if category.contains("约会") { return .date }
        if category.contains("聚会") || category.contains("派对") { return .party }
        if category.contains("出游") || category.contains("旅行") { return .outing }
        if category.contains("运动") || category.contains("健身") { return .sport }
        if category.contains("正式") || category.contains("商务") || category.contains("面试") { return .formal }
        if category.contains("度假") || category.contains("海边") { return .vacation }
        if category.contains("日常") { return .daily }
        return .uncategorized
    }
}

enum StylistMode: String, CaseIterable, Identifiable, Codable {
    case ai
    case manual

    var id: String { rawValue }
}

enum OutfitCoverSource: String, CaseIterable, Codable {
    case canvas
    case tryOn
    case realPhoto
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

struct ClothingAIAnalysis: Codable, Equatable {
    var style: [String]
    var seasons: [String]
    var materials: [String]
    var silhouette: String?
    var pattern: String?
    var occasions: [String]
    var formality: String?
    var warmth: String?

    static let empty = ClothingAIAnalysis(
        style: [],
        seasons: [],
        materials: [],
        silhouette: nil,
        pattern: nil,
        occasions: [],
        formality: nil,
        warmth: nil
    )

    var hasContent: Bool {
        !style.isEmpty ||
        !seasons.isEmpty ||
        !materials.isEmpty ||
        silhouette != nil ||
        pattern != nil ||
        !occasions.isEmpty ||
        formality != nil ||
        warmth != nil
    }
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
    var aiAnalysis: ClothingAIAnalysis
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
        aiAnalysis: ClothingAIAnalysis = .empty,
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
        self.aiAnalysis = aiAnalysis
        self.createdAt = createdAt
    }
}

enum WardrobeAccessoryKind {
    case hat
    case bag
    case accessory
}

extension ClosetItem {
    var accessoryKind: WardrobeAccessoryKind? {
        guard section == .uncategorized else { return nil }
        let source = wardrobeCategoryInferenceText
        if source.contains("帽") || source.contains("cap") || source.contains("hat") || source.contains("beanie") {
            return .hat
        }
        if source.contains("包") || source.contains("bag") || source.contains("tote") || source.contains("backpack") || source.contains("handbag") || source.contains("斜挎") || source.contains("双肩") {
            return .bag
        }
        return .accessory
    }

    var wardrobeFilter: WardrobeFilter {
        switch section {
        case .top:
            return isLikelyOuterwear ? .outerwear : .top
        case .bottom:
            return .bottom
        case .dress:
            return .dress
        case .shoes:
            return .shoes
        case .uncategorized:
            switch accessoryKind {
            case .hat:
                return .hat
            case .bag:
                return .bag
            case .accessory, .none:
                return .accessory
            }
        }
    }

    func matches(filter: WardrobeFilter) -> Bool {
        filter == .all || wardrobeFilter == filter
    }

    var wardrobeSearchText: String {
        [
            name,
            color,
            brand,
            section.rawValue,
            wardrobeFilter.rawValue,
            aiAnalysis.style.joined(separator: " "),
            aiAnalysis.seasons.joined(separator: " "),
            aiAnalysis.materials.joined(separator: " "),
            aiAnalysis.silhouette ?? "",
            aiAnalysis.pattern ?? "",
            aiAnalysis.occasions.joined(separator: " "),
            aiAnalysis.formality ?? "",
            aiAnalysis.warmth ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private var isLikelyOuterwear: Bool {
        let source = wardrobeCategoryInferenceText
        return source.contains("外套")
            || source.contains("大衣")
            || source.contains("夹克")
            || source.contains("风衣")
            || source.contains("开衫")
            || source.contains("西装外套")
            || source.contains("coat")
            || source.contains("jacket")
            || source.contains("blazer")
            || source.contains("cardigan")
            || source.contains("outerwear")
    }

    private var wardrobeCategoryInferenceText: String {
        [
            name,
            color,
            brand,
            aiAnalysis.silhouette ?? "",
            aiAnalysis.pattern ?? "",
            aiAnalysis.style.joined(separator: " "),
            aiAnalysis.materials.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
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
    var outfitCategory: String?
    var tags: [String]
    var aiSummary: String?
    var createdAt: Date
    var sourceMode: StylistMode
    var photoFileName: String?
    var tryOnImageFileName: String?
    var realPhotoFileName: String?
    var coverImageSource: OutfitCoverSource
    var isGeneratingTryOn: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        symbol: String,
        accent: String,
        itemIDs: [UUID],
        itemLayouts: [OutfitItemLayout] = [],
        outfitCategory: String? = nil,
        tags: [String] = [],
        aiSummary: String? = nil,
        createdAt: Date = .now,
        sourceMode: StylistMode,
        photoFileName: String? = nil,
        tryOnImageFileName: String? = nil,
        realPhotoFileName: String? = nil,
        coverImageSource: OutfitCoverSource = .canvas,
        isGeneratingTryOn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
        self.itemIDs = itemIDs
        self.itemLayouts = itemLayouts
        self.outfitCategory = outfitCategory
        self.tags = tags
        self.aiSummary = aiSummary
        self.createdAt = createdAt
        self.sourceMode = sourceMode
        self.tryOnImageFileName = tryOnImageFileName ?? photoFileName
        self.realPhotoFileName = realPhotoFileName
        self.coverImageSource = coverImageSource
        self.isGeneratingTryOn = isGeneratingTryOn
        self.photoFileName = photoFileName ?? {
            switch coverImageSource {
            case .canvas:
                return nil
            case .tryOn:
                return tryOnImageFileName
            case .realPhoto:
                return realPhotoFileName
            }
        }()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case symbol
        case accent
        case itemIDs
        case itemLayouts
        case outfitCategory
        case tags
        case aiSummary
        case createdAt
        case sourceMode
        case photoFileName
        case tryOnImageFileName
        case realPhotoFileName
        case coverImageSource
        case isGeneratingTryOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        symbol = try container.decode(String.self, forKey: .symbol)
        accent = try container.decode(String.self, forKey: .accent)
        itemIDs = try container.decode([UUID].self, forKey: .itemIDs)
        itemLayouts = try container.decodeIfPresent([OutfitItemLayout].self, forKey: .itemLayouts) ?? []
        outfitCategory = try container.decodeIfPresent(String.self, forKey: .outfitCategory)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        aiSummary = try container.decodeIfPresent(String.self, forKey: .aiSummary)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        sourceMode = try container.decode(StylistMode.self, forKey: .sourceMode)
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
        tryOnImageFileName = try container.decodeIfPresent(String.self, forKey: .tryOnImageFileName) ?? photoFileName
        realPhotoFileName = try container.decodeIfPresent(String.self, forKey: .realPhotoFileName)
        if let decodedCoverImageSource = try container.decodeIfPresent(OutfitCoverSource.self, forKey: .coverImageSource) {
            coverImageSource = decodedCoverImageSource
        } else if realPhotoFileName == photoFileName, realPhotoFileName != nil {
            coverImageSource = .realPhoto
        } else if photoFileName != nil {
            coverImageSource = .tryOn
        } else {
            coverImageSource = .canvas
        }
        isGeneratingTryOn = try container.decodeIfPresent(Bool.self, forKey: .isGeneratingTryOn) ?? false
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
    var tryOnImageFileName: String?
    var realPhotoFileName: String?
    var coverImageSource: OutfitCoverSource = .canvas

    init() {}

    init(
        title: String,
        itemIDs: Set<UUID>,
        itemLayouts: [OutfitItemLayout],
        photoFileName: String?,
        tryOnImageFileName: String? = nil,
        realPhotoFileName: String? = nil,
        coverImageSource: OutfitCoverSource = .canvas
    ) {
        self.title = title
        self.itemIDs = itemIDs
        self.itemLayouts = itemLayouts
        self.photoFileName = photoFileName
        self.tryOnImageFileName = tryOnImageFileName
        self.realPhotoFileName = realPhotoFileName
        self.coverImageSource = coverImageSource
    }

    init(outfit: OutfitPreview) {
        title = outfit.title
        itemIDs = Set(outfit.itemIDs)
        itemLayouts = outfit.itemLayouts
        photoFileName = outfit.photoFileName
        tryOnImageFileName = outfit.tryOnImageFileName
        realPhotoFileName = outfit.realPhotoFileName
        coverImageSource = outfit.coverImageSource
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
    var aiAnalysis: ClothingAIAnalysis = .empty

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
        aiAnalysis = item.aiAnalysis
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
