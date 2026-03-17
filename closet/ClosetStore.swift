//
//  ClosetStore.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ClosetStore: ObservableObject {
    @Published var closetSpaces: [ClosetSpace] {
        didSet { persist() }
    }
    @Published var selectedClosetID: UUID {
        didSet { persist() }
    }
    @Published var profile: ProfileData {
        didSet { persist() }
    }
    @Published var weather: WeatherSnapshot {
        didSet { persist() }
    }

    private let storageKey = "closet.snapshot.v1"
    private let calendar = Calendar.current
    private let doubaoOutfitImageService: DoubaoOutfitImageService

    init(doubaoOutfitImageService: DoubaoOutfitImageService? = nil) {
        self.doubaoOutfitImageService = doubaoOutfitImageService ?? DoubaoOutfitImageService()
        let loadedPersistedSnapshot: Bool
        if
            let data = UserDefaults.standard.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(ClosetSnapshot.self, from: data)
        {
            loadedPersistedSnapshot = true
            self.closetSpaces = snapshot.closetSpaces
            self.selectedClosetID = snapshot.selectedClosetID
            self.profile = snapshot.profile
            self.weather = snapshot.weather
        } else {
            loadedPersistedSnapshot = false
            let seed = Self.seedSnapshot()
            self.closetSpaces = seed.closetSpaces
            self.selectedClosetID = seed.selectedClosetID
            self.profile = seed.profile
            self.weather = seed.weather
            persist()
        }

        if closetSpaces.isEmpty {
            let seed = Self.seedSnapshot()
            closetSpaces = seed.closetSpaces
            selectedClosetID = seed.selectedClosetID
        }
        if !closetSpaces.contains(where: { $0.id == selectedClosetID }), let firstID = closetSpaces.first?.id {
            selectedClosetID = firstID
        }

        if !loadedPersistedSnapshot {
            migrateLegacySampleDataIfNeeded()
            ensureBundledSeedContent()
        }
    }

    var selectedCloset: ClosetSpace {
        get {
            closetSpaces.first(where: { $0.id == selectedClosetID }) ?? closetSpaces.first ?? ClosetSpace(name: "我的衣橱")
        }
        set {
            guard let index = closetSpaces.firstIndex(where: { $0.id == newValue.id }) else { return }
            objectWillChange.send()
            closetSpaces[index] = newValue
            persist()
        }
    }

    var wardrobeItems: [ClosetItem] {
        get { selectedCloset.wardrobeItems }
        set { updateSelectedCloset { $0.wardrobeItems = newValue } }
    }

    var savedLooks: [OutfitPreview] {
        get { selectedCloset.savedLooks }
        set { updateSelectedCloset { $0.savedLooks = newValue } }
    }

    var diaryEntries: [DiaryEntry] {
        get { selectedCloset.diaryEntries }
        set { updateSelectedCloset { $0.diaryEntries = newValue } }
    }

    var currentClosetName: String {
        selectedCloset.name
    }

    func selectCloset(_ closetID: UUID) {
        guard closetSpaces.contains(where: { $0.id == closetID }) else { return }
        selectedClosetID = closetID
    }

    func createCloset(named name: String? = nil) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let closetName = trimmedName.isEmpty ? nextClosetName() : trimmedName
        let newCloset = ClosetSpace(name: closetName)
        closetSpaces.insert(newCloset, at: 0)
        selectedClosetID = newCloset.id
    }

    func renameCurrentCloset(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        updateSelectedCloset { $0.name = trimmedName }
    }

    func deleteCloset(_ closetID: UUID) {
        guard closetSpaces.count > 1 else { return }
        guard let closet = closetSpaces.first(where: { $0.id == closetID }) else { return }
        cleanupAssets(for: closet)
        closetSpaces.removeAll { $0.id == closetID }
        if selectedClosetID == closetID, let firstID = closetSpaces.first?.id {
            selectedClosetID = firstID
        }
    }

    var totalWardrobeValue: Int {
        wardrobeItems.reduce(0) { $0 + $1.price }
    }

    var averageItemPrice: Int {
        guard !wardrobeItems.isEmpty else { return 0 }
        return totalWardrobeValue / wardrobeItems.count
    }

    var mostExpensiveItemPrice: Int {
        wardrobeItems.map(\.price).max() ?? 0
    }

    var pricedItemCount: Int {
        wardrobeItems.filter { $0.price > 0 }.count
    }

    var stats: [AnalysisStat] {
        [
            AnalysisStat(value: currency(totalWardrobeValue), label: "总价值", tone: "mint"),
            AnalysisStat(value: currency(averageItemPrice), label: "平均单价", tone: "sky"),
            AnalysisStat(value: "\(matchingCoverage)%", label: "识别覆盖率", tone: "rose"),
            AnalysisStat(value: "\(manualAdjustmentRate)%", label: "手动修正率", tone: "yellow")
        ]
    }

    var matchingCoverage: Int {
        let entriesWithPhoto = diaryEntries.filter(\.hasPhoto)
        guard !entriesWithPhoto.isEmpty else { return 0 }
        let matchedCount = entriesWithPhoto.filter { !$0.itemIDs.isEmpty || $0.outfitID != nil }.count
        return Int((Double(matchedCount) / Double(entriesWithPhoto.count) * 100).rounded())
    }

    var manualAdjustmentRate: Int {
        let matchedEntries = diaryEntries.filter { !$0.itemIDs.isEmpty || $0.outfitID != nil }
        guard !matchedEntries.isEmpty else { return 0 }
        let adjustedCount = matchedEntries.filter { $0.matchSource == .manuallyAdjusted }.count
        return Int((Double(adjustedCount) / Double(matchedEntries.count) * 100).rounded())
    }

    var priceBands: [PriceBand] {
        let counts = [
            wardrobeItems.filter { $0.price < 100 }.count,
            wardrobeItems.filter { $0.price >= 100 && $0.price < 300 }.count,
            wardrobeItems.filter { $0.price >= 300 && $0.price < 500 }.count,
            wardrobeItems.filter { $0.price >= 500 && $0.price < 1000 }.count,
            wardrobeItems.filter { $0.price >= 1000 }.count
        ]
        let total = max(wardrobeItems.count, 1)
        return [
            PriceBand(range: "0-100", count: counts[0], ratio: Double(counts[0]) / Double(total)),
            PriceBand(range: "100-300", count: counts[1], ratio: Double(counts[1]) / Double(total)),
            PriceBand(range: "300-500", count: counts[2], ratio: Double(counts[2]) / Double(total)),
            PriceBand(range: "500-1000", count: counts[3], ratio: Double(counts[3]) / Double(total)),
            PriceBand(range: "1000+", count: counts[4], ratio: Double(counts[4]) / Double(total))
        ]
    }

    func filteredWardrobeItems(filter: WardrobeFilter, query: String) -> [ClosetItem] {
        wardrobeItems.filter { item in
            let matchesFilter = filter == .all || item.section.filter == filter
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery: Bool
            if normalizedQuery.isEmpty {
                matchesQuery = true
            } else {
                let source = [item.name, item.color, item.brand].joined(separator: " ").lowercased()
                matchesQuery = source.contains(normalizedQuery.lowercased())
            }
            return matchesFilter && matchesQuery
        }
    }

    var activeWardrobeItems: [ClosetItem] {
        wardrobeItems.filter { !$0.isArchived }
    }

    var archivedWardrobeItems: [ClosetItem] {
        wardrobeItems.filter(\.isArchived)
    }

    var activeSavedLooks: [OutfitPreview] {
        let archivedIDs = Set(archivedWardrobeItems.map(\.id))
        return savedLooks.filter { look in
            look.itemIDs.allSatisfy { !archivedIDs.contains($0) }
        }
    }

    var allReferencedImageFileNames: Set<String> {
        let wardrobeImageNames = closetSpaces.flatMap(\.wardrobeItems).compactMap(\.imageFileName)
        let outfitCoverImageNames = closetSpaces.flatMap(\.savedLooks).compactMap(\.photoFileName)
        let outfitTryOnImageNames = closetSpaces.flatMap(\.savedLooks).compactMap(\.tryOnImageFileName)
        let outfitRealPhotoNames = closetSpaces.flatMap(\.savedLooks).compactMap(\.realPhotoFileName)
        let diaryImageNames = closetSpaces.flatMap(\.diaryEntries).compactMap(\.photoFileName)
        let bodyPhotoNames = profile.bodyPhotos.compactMap(\.imageFileName)

        return Set(
            wardrobeImageNames +
            outfitCoverImageNames +
            outfitTryOnImageNames +
            outfitRealPhotoNames +
            diaryImageNames +
            bodyPhotoNames
        )
    }

    func itemCount(for section: WardrobeSection) -> Int {
        wardrobeItems.filter { $0.section == section }.count
    }

    @discardableResult
    func addItem(from draft: AddItemDraft) -> ClosetItem? {
        addItem(from: draft, photoData: nil)
    }

    @discardableResult
    func addItem(from draft: AddItemDraft, photoData: Data?) -> ClosetItem? {
        guard photoData != nil || draft.imageFileName != nil else { return nil }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = draft.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageFileName = storedImageFileName(
            newData: photoData,
            oldFileName: draft.imageFileName,
            prefix: "item"
        )

        let item = ClosetItem(
            name: trimmedName.isEmpty ? defaultItemName(for: draft.section) : trimmedName,
            section: draft.section,
            color: trimmedColor.isEmpty ? "未填写颜色" : trimmedColor,
            brand: trimmedBrand.isEmpty ? "未填写品牌" : trimmedBrand,
            price: Int(draft.price) ?? 0,
            wearCount: 0,
            gradientName: draft.gradientName.rawValue,
            imageFileName: imageFileName,
            aiAnalysis: draft.aiAnalysis
        )
        wardrobeItems.insert(item, at: 0)
        LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: item)
        return item
    }

    @discardableResult
    func addBatchImportedPlaceholderItem(photoData: Data) -> ClosetItem? {
        guard let imageFileName = LocalImageStore.shared.saveImageData(photoData, prefix: "item") else { return nil }

        let item = ClosetItem(
            name: "",
            section: .uncategorized,
            color: "",
            brand: "",
            price: 0,
            wearCount: 0,
            gradientName: WardrobeSection.uncategorized.defaultGradientName,
            imageFileName: imageFileName,
            aiAnalysis: .empty
        )
        wardrobeItems.insert(item, at: 0)
        LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: item)
        return item
    }

    func applyBackgroundAutoTag(
        to itemID: UUID,
        section: WardrobeSection,
        name: String?,
        color: String?,
        brand: String?,
        aiAnalysis: ClothingAIAnalysis = .empty
    ) {
        guard let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }

        if wardrobeItems[index].section == .uncategorized {
            wardrobeItems[index].section = section
            wardrobeItems[index].symbol = section.symbol
            wardrobeItems[index].gradientName = section.defaultGradientName
        }

        if wardrobeItems[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wardrobeItems[index].name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if wardrobeItems[index].color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wardrobeItems[index].color = color?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if wardrobeItems[index].brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wardrobeItems[index].brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if aiAnalysis.hasContent {
            wardrobeItems[index].aiAnalysis = aiAnalysis
        }
    }

    func addItems(from draft: AddItemDraft, photoDatas: [Data]) {
        guard !photoDatas.isEmpty else { return }
        for data in photoDatas.reversed() {
            addItem(from: draft, photoData: data)
        }
    }

    func updateItem(_ itemID: UUID, from draft: AddItemDraft, photoData: Data?) {
        guard let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = draft.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard photoData != nil || draft.imageFileName != nil || wardrobeItems[index].imageFileName != nil else { return }

        wardrobeItems[index].name = trimmedName.isEmpty ? defaultItemName(for: draft.section) : trimmedName
        wardrobeItems[index].section = draft.section
        wardrobeItems[index].color = trimmedColor.isEmpty ? "未填写颜色" : trimmedColor
        wardrobeItems[index].brand = trimmedBrand.isEmpty ? "未填写品牌" : trimmedBrand
        wardrobeItems[index].price = Int(draft.price) ?? 0
        wardrobeItems[index].symbol = draft.section.symbol
        wardrobeItems[index].gradientName = draft.gradientName.rawValue
        wardrobeItems[index].imageFileName = storedImageFileName(
            newData: photoData,
            oldFileName: wardrobeItems[index].imageFileName,
            requestedFileName: draft.imageFileName,
            prefix: "item"
        )
        wardrobeItems[index].aiAnalysis = draft.aiAnalysis
        LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: wardrobeItems[index])
    }

    func deleteItem(_ itemID: UUID) {
        guard let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }
        LocalImageStore.shared.removeImage(named: wardrobeItems[index].imageFileName)
        wardrobeItems.remove(at: index)
        savedLooks.removeAll { look in
            look.itemIDs.contains(itemID)
        }
        diaryEntries = diaryEntries.map { entry in
            guard let outfitID = entry.outfitID else { return entry }
            let outfitStillExists = savedLooks.contains(where: { $0.id == outfitID })
            guard !outfitStillExists else { return entry }
            var updatedEntry = entry
            updatedEntry.outfitID = nil
            return updatedEntry
        }
    }

    func setArchived(_ itemID: UUID, isArchived: Bool) {
        guard let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }
        wardrobeItems[index].isArchived = isArchived
    }

    func setArchived(_ itemIDs: Set<UUID>, isArchived: Bool) {
        guard !itemIDs.isEmpty else { return }
        for index in wardrobeItems.indices where itemIDs.contains(wardrobeItems[index].id) {
            wardrobeItems[index].isArchived = isArchived
        }
    }

    func toggleArchived(_ itemID: UUID) {
        guard let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }
        wardrobeItems[index].isArchived.toggle()
    }

    func incrementWearCount(for itemID: UUID, amount: Int = 1) {
        guard amount > 0, let index = wardrobeItems.firstIndex(where: { $0.id == itemID }) else { return }
        wardrobeItems[index].wearCount += amount
    }

    func logItemAsWornToday(_ itemID: UUID, mood: String = "普通") {
        logItemAsWorn(itemID, on: .now, mood: mood)
    }

    func logItemAsWorn(_ itemID: UUID, on date: Date, mood: String = "普通") {
        guard activeWardrobeItems.contains(where: { $0.id == itemID }) else { return }

        let normalizedDate = calendar.startOfDay(for: date)
        var draft = draftForDiary(on: normalizedDate)
        if !draft.itemIDs.contains(itemID) {
            draft.itemIDs.append(itemID)
        }
        draft.outfitID = nil
        draft.matchSource = .manuallyAdjusted
        if draft.mood.isEmpty {
            draft.mood = mood
        }

        upsertDiaryEntry(for: normalizedDate, draft: draft)
    }

    func makeAIOutfit(prompt: String) async throws -> OutfitPreview? {
        guard let selectedItems = selectItemsForAIPrompt(prompt) else {
            return nil
        }
        if let existingLook = existingSavedLook(matching: selectedItems) {
            return existingLook
        }
        let outfitMetadata = analyzeOutfit(items: selectedItems, customPrompt: prompt)

        let imageData = try await doubaoOutfitImageService.generateOutfitImage(
            prompt: prompt,
            profile: profile,
            weather: weather,
            items: selectedItems
        )
        let generatedTryOnFileName = LocalImageStore.shared.saveImageData(imageData, prefix: "outfit-ai")

        let title = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "今日 AI 推荐" : "AI: \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
        let subtitle = selectedItems.map(\.name).joined(separator: " + ")
        let outfit = OutfitPreview(
            title: title,
            subtitle: subtitle,
            symbol: "sparkles",
            accent: selectedItems.first?.gradientName ?? "cloud",
            itemIDs: selectedItems.map(\.id),
            outfitCategory: outfitMetadata.category,
            tags: outfitMetadata.tags,
            aiSummary: outfitMetadata.summary,
            sourceMode: .ai,
            photoFileName: generatedTryOnFileName,
            tryOnImageFileName: generatedTryOnFileName,
            coverImageSource: .tryOn
        )
        savedLooks.insert(outfit, at: 0)
        return outfit
    }

    func saveManualOutfit(itemIDs: [UUID], itemLayouts: [OutfitItemLayout]? = nil) -> OutfitPreview? {
        let items = activeWardrobeItems.filter { itemIDs.contains($0.id) }
        guard !items.isEmpty else { return nil }
        let outfitMetadata = analyzeOutfit(items: items, customPrompt: nil)
        let title = "手动选择 \(savedLooks.count + 1)"
        let subtitle = items.map(\.name).joined(separator: " + ")
        let layouts = normalizedLayouts(for: itemIDs, proposed: itemLayouts)
        let outfit = OutfitPreview(
            title: title,
            subtitle: subtitle,
            symbol: "hand.raised",
            accent: items.first?.gradientName ?? "cloud",
            itemIDs: itemIDs,
            itemLayouts: layouts,
            outfitCategory: outfitMetadata.category,
            tags: outfitMetadata.tags,
            aiSummary: outfitMetadata.summary,
            sourceMode: .manual,
            coverImageSource: .canvas
        )
        savedLooks.insert(outfit, at: 0)
        return outfit
    }

    func saveManualOutfitWithGeneratedCover(
        itemIDs: [UUID],
        itemLayouts: [OutfitItemLayout]? = nil,
        prompt: String? = nil
    ) async throws -> OutfitPreview? {
        let items = activeWardrobeItems.filter { itemIDs.contains($0.id) }
        guard !items.isEmpty else { return nil }
        let outfitMetadata = analyzeOutfit(items: items, customPrompt: prompt)

        let generatedPhotoFileName: String?
        do {
            let imageData = try await doubaoOutfitImageService.generateOutfitImage(
                prompt: manualOutfitCoverPrompt(customPrompt: prompt, items: items),
                profile: profile,
                weather: weather,
                items: items
            )
            generatedPhotoFileName = LocalImageStore.shared.saveImageData(imageData, prefix: "outfit-manual")
        } catch let error as DoubaoOutfitImageError where shouldFallbackToCoverlessSave(for: error) {
            generatedPhotoFileName = nil
        }

        let title = "手动选择 \(savedLooks.count + 1)"
        let subtitle = items.map(\.name).joined(separator: " + ")
        let layouts = normalizedLayouts(for: itemIDs, proposed: itemLayouts)
        let outfit = OutfitPreview(
            title: title,
            subtitle: subtitle,
            symbol: "hand.raised",
            accent: items.first?.gradientName ?? "cloud",
            itemIDs: itemIDs,
            itemLayouts: layouts,
            outfitCategory: outfitMetadata.category,
            tags: outfitMetadata.tags,
            aiSummary: outfitMetadata.summary,
            sourceMode: .manual,
            photoFileName: generatedPhotoFileName,
            tryOnImageFileName: generatedPhotoFileName,
            coverImageSource: generatedPhotoFileName == nil ? .canvas : .tryOn
        )
        savedLooks.insert(outfit, at: 0)
        return outfit
    }

    func updateOutfit(_ outfitID: UUID, from draft: OutfitDraft, photoData: Data?) {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        let orderedIDs = Array(draft.itemIDs)
        let items = wardrobeItems.filter { draft.itemIDs.contains($0.id) }
        let outfitMetadata = analyzeOutfit(items: items, customPrompt: nil)
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLooks[index].title = trimmedTitle.isEmpty ? savedLooks[index].title : trimmedTitle
        savedLooks[index].subtitle = items.map(\.name).joined(separator: " + ")
        savedLooks[index].itemIDs = orderedIDs
        savedLooks[index].itemLayouts = normalizedLayouts(for: orderedIDs, proposed: draft.itemLayouts)
        savedLooks[index].outfitCategory = outfitMetadata.category
        savedLooks[index].tags = outfitMetadata.tags
        savedLooks[index].aiSummary = outfitMetadata.summary
        savedLooks[index].tryOnImageFileName = draft.tryOnImageFileName
        savedLooks[index].realPhotoFileName = storedImageFileName(
            newData: photoData,
            oldFileName: savedLooks[index].realPhotoFileName,
            requestedFileName: draft.realPhotoFileName,
            prefix: "outfit-real"
        )
        savedLooks[index].coverImageSource = availableCoverSources(for: savedLooks[index]).contains(draft.coverImageSource) ? draft.coverImageSource : defaultCoverSource(for: savedLooks[index])
        savedLooks[index].photoFileName = resolvedCoverFileName(for: savedLooks[index])
    }

    func updateOutfitWithGeneratedCover(
        _ outfitID: UUID,
        from draft: OutfitDraft,
        prompt: String? = nil
    ) async throws {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        let orderedIDs = Array(draft.itemIDs)
        let items = activeWardrobeItems.filter { orderedIDs.contains($0.id) }
        guard !items.isEmpty else { return }

        let existingOutfit = savedLooks[index]
        let shouldRegenerateCover =
            existingOutfit.photoFileName == nil ||
            existingOutfit.itemIDs != orderedIDs

        var generatedPhotoFileName = draft.photoFileName
        var generatedTryOnImageFileName = draft.tryOnImageFileName
        if shouldRegenerateCover {
            do {
                let imageData = try await doubaoOutfitImageService.generateOutfitImage(
                    prompt: manualOutfitCoverPrompt(customPrompt: prompt, items: items),
                    profile: profile,
                    weather: weather,
                    items: items
                )
                generatedTryOnImageFileName = LocalImageStore.shared.saveImageData(imageData, prefix: "outfit-manual")
                if draft.coverImageSource == .tryOn || draft.photoFileName == nil {
                    generatedPhotoFileName = generatedTryOnImageFileName
                }
            } catch let error as DoubaoOutfitImageError where shouldFallbackToCoverlessSave(for: error) {
                generatedPhotoFileName = draft.photoFileName
            }
        }

        let nextDraft = OutfitDraft(
            title: draft.title,
            itemIDs: Set(orderedIDs),
            itemLayouts: draft.itemLayouts,
            photoFileName: generatedPhotoFileName,
            tryOnImageFileName: generatedTryOnImageFileName,
            realPhotoFileName: draft.realPhotoFileName,
            coverImageSource: draft.coverImageSource
        )
        updateOutfit(outfitID, from: nextDraft, photoData: nil)
    }

    func setOutfitCoverSource(_ outfitID: UUID, source: OutfitCoverSource) {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        let availableSources = availableCoverSources(for: savedLooks[index])
        let nextSource = availableSources.contains(source) ? source : defaultCoverSource(for: savedLooks[index])
        savedLooks[index].coverImageSource = nextSource
        savedLooks[index].photoFileName = resolvedCoverFileName(for: savedLooks[index])
    }

    func deleteOutfit(_ outfitID: UUID) {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        LocalImageStore.shared.removeImage(named: savedLooks[index].photoFileName)
        if savedLooks[index].tryOnImageFileName != savedLooks[index].photoFileName {
            LocalImageStore.shared.removeImage(named: savedLooks[index].tryOnImageFileName)
        }
        if savedLooks[index].realPhotoFileName != savedLooks[index].photoFileName,
           savedLooks[index].realPhotoFileName != savedLooks[index].tryOnImageFileName {
            LocalImageStore.shared.removeImage(named: savedLooks[index].realPhotoFileName)
        }
        savedLooks.remove(at: index)
        diaryEntries = diaryEntries.map { entry in
            guard entry.outfitID == outfitID else { return entry }
            var e = entry; e.outfitID = nil; return e
        }
        recomputeWearCounts()
    }

    func deleteItems(_ itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        for itemID in itemIDs {
            deleteItem(itemID)
        }
    }

    func diaryEntry(for date: Date) -> DiaryEntry? {
        diaryEntries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func upsertDiaryEntry(for date: Date, draft: DiaryDraft, photoData: Data? = nil) {
        let normalized = calendar.startOfDay(for: date)
        if let index = diaryEntries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: normalized) }) {
            let photoFileName = storedImageFileName(
                newData: photoData,
                oldFileName: diaryEntries[index].photoFileName ?? draft.photoFileName,
                requestedFileName: draft.photoFileName,
                prefix: "diary"
            ) ?? draft.photoFileName
            diaryEntries[index].mood = draft.mood
            diaryEntries[index].note = draft.note
            diaryEntries[index].hasPhoto = draft.hasPhoto || photoFileName != nil
            diaryEntries[index].photoFileName = photoFileName
            diaryEntries[index].outfitID = draft.outfitID
            diaryEntries[index].itemIDs = draft.itemIDs
            diaryEntries[index].matchSource = draft.matchSource
        } else {
            let photoFileName = storedImageFileName(
                newData: photoData,
                oldFileName: draft.photoFileName,
                requestedFileName: draft.photoFileName,
                prefix: "diary"
            ) ?? draft.photoFileName
            diaryEntries.append(
                DiaryEntry(
                    date: normalized,
                    mood: draft.mood,
                    note: draft.note,
                    hasPhoto: draft.hasPhoto || photoFileName != nil,
                    photoFileName: photoFileName,
                    outfitID: draft.outfitID,
                    itemIDs: draft.itemIDs,
                    matchSource: draft.matchSource
                )
            )
        }
        recomputeWearCounts()
    }

    func recordOutfit(_ outfitID: UUID, on date: Date) {
        guard let outfit = savedLooks.first(where: { $0.id == outfitID }) else { return }
        let normalized = calendar.startOfDay(for: date)
        var draft = draftForDiary(on: normalized)
        draft.outfitID = outfitID
        draft.itemIDs = outfit.itemIDs
        draft.matchSource = .manuallyAdjusted
        if draft.mood.isEmpty {
            draft.mood = "普通"
        }
        upsertDiaryEntry(for: normalized, draft: draft)
    }

    func markers(for month: Date) -> [DiaryMarker] {
        let entriesForMonth = diaryEntries.filter { entry in
            calendar.isDate(entry.date, equalTo: month, toGranularity: .month)
        }

        let uniqueEntries = entriesForMonth.reduce(into: [Int: DiaryEntry]()) { result, entry in
            let day = calendar.component(.day, from: entry.date)
            if result[day] == nil {
                result[day] = entry
            }
        }

        return uniqueEntries.values.compactMap { entry in
            let hasDisplayablePhoto = hasDisplayableDiaryPhoto(for: entry)
            let hasDisplayableOutfit = hasDisplayableDiaryOutfit(for: entry)
            guard hasDisplayablePhoto || hasDisplayableOutfit else { return nil }
            return DiaryMarker(
                day: calendar.component(.day, from: entry.date),
                hasRecord: true,
                hasPhoto: hasDisplayablePhoto,
                hasOutfit: hasDisplayableOutfit,
                mood: entry.mood
            )
        }
    }

    func updateProfile(from draft: ProfileDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingFileNames = Set(profile.bodyPhotos.compactMap(\.imageFileName))
        let nextFileNames = Set(draft.bodyPhotos.compactMap(\.imageFileName))
        let removedFileNames = existingFileNames.subtracting(nextFileNames)

        profile.name = trimmedName.isEmpty ? profile.name : trimmedName
        profile.heightCm = Int(draft.heightCm) ?? profile.heightCm
        profile.weightKg = Int(draft.weightKg) ?? profile.weightKg
        profile.bodyPhotos = draft.bodyPhotos

        removedFileNames.forEach { LocalImageStore.shared.removeImage(named: $0) }
    }

    func draftForProfile() -> ProfileDraft {
        ProfileDraft(
            name: profile.name,
            heightCm: "\(profile.heightCm)",
            weightKg: "\(profile.weightKg)",
            bodyPhotos: profile.bodyPhotos
        )
    }

    func draftForDiary(on date: Date) -> DiaryDraft {
        guard let entry = diaryEntry(for: date) else { return DiaryDraft() }
        return DiaryDraft(
            mood: entry.mood,
            note: entry.note,
            hasPhoto: entry.hasPhoto,
            photoFileName: entry.photoFileName,
            outfitID: entry.outfitID,
            itemIDs: entry.itemIDs,
            matchSource: entry.matchSource
        )
    }

    func updateBodyPhoto(_ photoID: UUID, imageData: Data, in draft: inout ProfileDraft) {
        guard let index = draft.bodyPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        draft.bodyPhotos[index].imageFileName = storedImageFileName(
            newData: imageData,
            oldFileName: draft.bodyPhotos[index].imageFileName,
            prefix: "profile"
        )
    }

    func removeBodyPhoto(_ photoID: UUID, in draft: inout ProfileDraft) {
        guard let index = draft.bodyPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        draft.bodyPhotos[index].imageFileName = nil
    }

    func removeDiaryPhoto(in draft: inout DiaryDraft) {
        draft.photoFileName = nil
        draft.hasPhoto = false
    }

    func makeBackupDocument() -> LocalClosetBackupDocument {
        let images = allReferencedImageFileNames.reduce(into: [String: Data]()) { partial, fileName in
            if let data = LocalImageStore.shared.loadImageData(named: fileName) {
                partial[fileName] = data
            }
        }
        return LocalClosetBackupDocument(
            payload: LocalClosetBackupPayload(
                snapshot: ClosetSnapshot(
                    closetSpaces: closetSpaces,
                    selectedClosetID: selectedClosetID,
                    profile: profile,
                    weather: weather
                ),
                images: images,
                exportedAt: .now
            )
        )
    }

    func importBackup(_ document: LocalClosetBackupDocument) {
        let snapshot = document.payload.snapshot
        closetSpaces = snapshot.closetSpaces
        selectedClosetID = snapshot.selectedClosetID
        profile = snapshot.profile
        weather = snapshot.weather

        for (fileName, data) in document.payload.images {
            LocalImageStore.shared.restoreImageData(data, named: fileName)
        }

        cleanupUnusedAssets()
        for item in closetSpaces.flatMap(\.wardrobeItems) {
            LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: item)
        }
    }

    @discardableResult
    func cleanupUnusedAssets() -> Int {
        let removedImages = LocalImageStore.shared.removeAllImages(except: allReferencedImageFileNames)
        LocalWardrobeFeatureStore.shared.removeSignatures(except: Set(closetSpaces.flatMap(\.wardrobeItems).compactMap(\.imageFileName)))
        return removedImages
    }

    func duplicateCandidates(for imageData: Data) -> [DuplicateCandidate] {
        LocalDuplicateDetector.detectDuplicates(for: imageData, in: activeWardrobeItems)
    }

    func lastWornDate(for itemID: UUID) -> Date? {
        diaryEntries
            .filter { entry in
                if entry.itemIDs.contains(itemID) {
                    return true
                }
                guard let outfitID = entry.outfitID,
                      let outfit = savedLooks.first(where: { $0.id == outfitID }) else {
                    return false
                }
                return outfit.itemIDs.contains(itemID)
            }
            .map(\.date)
            .max()
    }

    func idleItems(forMoreThan days: Int) -> [ClosetItem] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .distantPast
        return activeWardrobeItems
            .filter { item in
                guard let lastWornDate = lastWornDate(for: item.id) else { return true }
                return lastWornDate < cutoff
            }
            .sorted { lhs, rhs in
                let lhsDate = lastWornDate(for: lhs.id) ?? .distantPast
                let rhsDate = lastWornDate(for: rhs.id) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    func newestItemsCount(since days: Int = 7) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return wardrobeItems.filter { $0.createdAt >= cutoff }.count
    }

    func highestWearCount() -> Int {
        wardrobeItems.map(\.wearCount).max() ?? 0
    }

    func bestValueItem() -> ClosetItem? {
        wardrobeItems
            .filter { $0.wearCount > 0 }
            .min { lhs, rhs in
                Double(lhs.price) / Double(lhs.wearCount) < Double(rhs.price) / Double(rhs.wearCount)
            }
    }

    private func recomputeWearCounts() {
        for index in wardrobeItems.indices {
            wardrobeItems[index].wearCount = 0
        }

        for entry in diaryEntries {
            let countedIDs: [UUID]
            if !entry.itemIDs.isEmpty {
                countedIDs = entry.itemIDs
            } else if let outfitID = entry.outfitID,
                      let outfit = savedLooks.first(where: { $0.id == outfitID }) {
                countedIDs = outfit.itemIDs
            } else {
                countedIDs = []
            }

            for id in countedIDs {
                guard let index = wardrobeItems.firstIndex(where: { $0.id == id }) else { continue }
                wardrobeItems[index].wearCount += 1
            }
        }
    }

    private func hasDisplayableDiaryPhoto(for entry: DiaryEntry) -> Bool {
        if let outfitID = entry.outfitID,
           let outfit = savedLooks.first(where: { $0.id == outfitID }),
           LocalImageStore.shared.loadImage(named: outfit.photoFileName) != nil {
            return true
        }

        guard let fileName = entry.photoFileName else { return false }
        return LocalImageStore.shared.loadImage(named: fileName) != nil
    }

    private func hasDisplayableDiaryOutfit(for entry: DiaryEntry) -> Bool {
        let existingWardrobeIDs = Set(wardrobeItems.map(\.id))

        if !entry.itemIDs.isEmpty {
            return entry.itemIDs.contains { existingWardrobeIDs.contains($0) }
        }

        guard let outfitID = entry.outfitID,
              let outfit = savedLooks.first(where: { $0.id == outfitID }) else {
            return false
        }

        return outfit.itemIDs.contains { existingWardrobeIDs.contains($0) }
    }

    private func persist() {
        let snapshot = ClosetSnapshot(
            closetSpaces: closetSpaces,
            selectedClosetID: selectedClosetID,
            profile: profile,
            weather: weather
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func currency(_ value: Int) -> String {
        "¥\(value.formatted(.number.grouping(.automatic)))"
    }

    private func defaultItemName(for section: WardrobeSection) -> String {
        switch section {
        case .uncategorized: "未命名单品"
        case .top: "未命名上装"
        case .bottom: "未命名下装"
        case .dress: "未命名连衣裙"
        case .shoes: "未命名鞋履"
        }
    }

    private func storedImageFileName(newData: Data?, oldFileName: String?, requestedFileName: String? = nil, prefix: String) -> String? {
        if let newData {
            let newFileName = LocalImageStore.shared.saveImageData(newData, prefix: prefix)
            if oldFileName != newFileName {
                LocalImageStore.shared.removeImage(named: oldFileName)
            }
            return newFileName
        }

        if requestedFileName == nil, oldFileName != nil {
            LocalImageStore.shared.removeImage(named: oldFileName)
            return nil
        }

        return requestedFileName ?? oldFileName
    }

    private func manualOutfitCoverPrompt(customPrompt: String?, items: [ClosetItem]) -> String {
        let userPrompt = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !userPrompt.isEmpty {
            return userPrompt
        }

        let summary = items.map { "\($0.color)\($0.name)" }.joined(separator: "、")
        return "为已保存搭配生成一张真实自然的试穿封面图，人物使用档案里的同一用户三视图，服装严格参考单品图片：\(summary)。"
    }

    private func shouldFallbackToCoverlessSave(for error: DoubaoOutfitImageError) -> Bool {
        switch error {
        case .missingAPIKey, .missingReferenceImages:
            return true
        case .transport, .invalidResponse, .server, .emptyResult:
            return false
        }
    }

    private func updateSelectedCloset(_ mutate: (inout ClosetSpace) -> Void) {
        guard let index = closetSpaces.firstIndex(where: { $0.id == selectedClosetID }) else { return }
        objectWillChange.send()
        var closet = closetSpaces[index]
        mutate(&closet)
        closetSpaces[index] = closet
        persist()
    }

    private func nextClosetName() -> String {
        let existingNames = Set(closetSpaces.map(\.name))
        var index = max(closetSpaces.count + 1, 2)
        var candidate = "衣橱 \(index)"
        while existingNames.contains(candidate) {
            index += 1
            candidate = "衣橱 \(index)"
        }
        return candidate
    }

    private func cleanupAssets(for closet: ClosetSpace) {
        let fileNames = Set(
            closet.wardrobeItems.compactMap(\.imageFileName) +
            closet.savedLooks.compactMap(\.photoFileName) +
            closet.savedLooks.compactMap(\.tryOnImageFileName) +
            closet.savedLooks.compactMap(\.realPhotoFileName) +
            closet.diaryEntries.compactMap(\.photoFileName)
        )
        for fileName in fileNames {
            LocalImageStore.shared.removeImage(named: fileName)
        }
        LocalWardrobeFeatureStore.shared.removeSignatures(except: Set(closetSpaces.filter { $0.id != closet.id }.flatMap(\.wardrobeItems).compactMap(\.imageFileName)))
    }

    private func normalizedLayouts(for itemIDs: [UUID], proposed: [OutfitItemLayout]?) -> [OutfitItemLayout] {
        let validIDs = Set(itemIDs)
        let filtered = (proposed ?? []).filter { validIDs.contains($0.itemID) }
        let existingMap = Dictionary(uniqueKeysWithValues: filtered.map { ($0.itemID, $0) })
        let defaults = defaultLayouts(for: itemIDs)
        return itemIDs.compactMap { itemID in
            existingMap[itemID] ?? defaults.first(where: { $0.itemID == itemID })
        }
    }

    private func defaultLayouts(for itemIDs: [UUID]) -> [OutfitItemLayout] {
        let presets: [(Double, Double)] = [
            (0.5, 0.2),
            (0.5, 0.5),
            (0.5, 0.8),
            (0.28, 0.48),
            (0.72, 0.48),
            (0.28, 0.8),
            (0.72, 0.8)
        ]
        return itemIDs.enumerated().map { index, itemID in
            let preset = presets[min(index, presets.count - 1)]
            let scale = index == 0 ? 1.08 : 0.96
            return OutfitItemLayout(itemID: itemID, x: preset.0, y: preset.1, scale: scale, rotation: 0)
        }
    }

    private func availableCoverSources(for outfit: OutfitPreview) -> [OutfitCoverSource] {
        var sources: [OutfitCoverSource] = [.canvas]
        if outfit.tryOnImageFileName != nil {
            sources.append(.tryOn)
        }
        if outfit.realPhotoFileName != nil {
            sources.append(.realPhoto)
        }
        return sources
    }

    private func defaultCoverSource(for outfit: OutfitPreview) -> OutfitCoverSource {
        if outfit.realPhotoFileName != nil { return .realPhoto }
        if outfit.tryOnImageFileName != nil { return .tryOn }
        return .canvas
    }

    private func resolvedCoverFileName(for outfit: OutfitPreview) -> String? {
        switch outfit.coverImageSource {
        case .canvas:
            return nil
        case .tryOn:
            return outfit.tryOnImageFileName
        case .realPhoto:
            return outfit.realPhotoFileName
        }
    }

    private func selectItemsForAIPrompt(_ prompt: String) -> [ClosetItem]? {
        let tops = activeWardrobeItems.filter { $0.section == .top }
        let bottoms = activeWardrobeItems.filter { $0.section == .bottom }
        let dresses = activeWardrobeItems.filter { $0.section == .dress }
        let shoes = activeWardrobeItems.filter { $0.section == .shoes }

        let scoredShoes = rankedItems(shoes, prompt: prompt)
        guard let bestShoes = scoredShoes.first else { return nil }

        let bestTop = rankedItems(tops, prompt: prompt).first
        let bestBottom = rankedItems(bottoms, prompt: prompt).first
        let bestDress = rankedItems(dresses, prompt: prompt).first

        let separatesScore = (bestTop.map { score(for: $0, prompt: prompt) } ?? -Double.greatestFiniteMagnitude)
            + (bestBottom.map { score(for: $0, prompt: prompt) } ?? -Double.greatestFiniteMagnitude)
            + score(for: bestShoes, prompt: prompt)

        let dressScore = (bestDress.map { score(for: $0, prompt: prompt) } ?? -Double.greatestFiniteMagnitude)
            + score(for: bestShoes, prompt: prompt)

        if let bestDress, dressScore >= separatesScore {
            return [bestDress, bestShoes]
        }

        if let bestTop, let bestBottom {
            return [bestTop, bestBottom, bestShoes]
        }

        if let bestDress {
            return [bestDress, bestShoes]
        }

        return nil
    }

    private func existingSavedLook(matching items: [ClosetItem]) -> OutfitPreview? {
        let itemIDs = Set(items.map(\.id))
        guard !itemIDs.isEmpty else { return nil }

        return activeSavedLooks.first { look in
            Set(look.itemIDs) == itemIDs
        }
    }

    private func analyzeOutfit(items: [ClosetItem], customPrompt: String?) -> OutfitMetadata {
        let styles = mergedTopValues(from: items.flatMap(\.aiAnalysis.style))
        let occasions = mergedTopValues(from: items.flatMap(\.aiAnalysis.occasions))
        let seasons = mergedTopValues(from: items.flatMap(\.aiAnalysis.seasons))
        let promptKeywords = promptKeywords(from: customPrompt ?? "")
        let dominantOccasion = occasions.first
        let dominantStyle = styles.first
        let warmth = dominantWarmth(in: items)
        let formality = dominantFormality(in: items)

        let category = inferredOutfitCategory(
            occasion: dominantOccasion,
            style: dominantStyle,
            promptKeywords: promptKeywords,
            warmth: warmth
        )

        let tags = makeOutfitTags(
            category: category,
            occasion: dominantOccasion,
            style: dominantStyle,
            seasons: seasons,
            warmth: warmth,
            formality: formality,
            promptKeywords: promptKeywords,
            items: items
        )

        let names = items.map(\.name).joined(separator: "、")
        let occasionText = dominantOccasion ?? "日常"
        let styleText = dominantStyle ?? "协调"
        let seasonText = seasons.first.map { "\($0)季" } ?? "当下天气"
        let summary = "这套搭配以\(styleText)风格为主，适合\(occasionText)场景，重点单品是\(names)，更贴合\(seasonText)与\(weather.condition)天气。"

        return OutfitMetadata(
            category: category,
            tags: tags,
            summary: summary
        )
    }

    private func rankedItems(_ items: [ClosetItem], prompt: String) -> [ClosetItem] {
        items.sorted { lhs, rhs in
            let lhsScore = score(for: lhs, prompt: prompt)
            let rhsScore = score(for: rhs, prompt: prompt)
            if lhsScore == rhsScore {
                return lhs.wearCount < rhs.wearCount
            }
            return lhsScore > rhsScore
        }
    }

    private func score(for item: ClosetItem, prompt: String) -> Double {
        let keywords = promptKeywords(from: prompt)
        let haystack = searchableText(for: item)
        let exactKeywordMatches = keywords.filter { haystack.contains($0) }.count
        let semanticMatches = semanticMatchScore(for: item, keywords: keywords)
        let weatherScore = weatherCompatibilityScore(for: item)
        let recencyPenalty = min(Double(item.wearCount) * 0.12, 1.2)

        var score = Double(exactKeywordMatches) * 2.2
        score += semanticMatches
        score += weatherScore
        score -= recencyPenalty

        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += defaultSectionScore(for: item.section)
        }

        return score
    }

    private func promptKeywords(from prompt: String) -> [String] {
        prompt
            .lowercased()
            .replacingOccurrences(of: "，", with: " ")
            .replacingOccurrences(of: "。", with: " ")
            .replacingOccurrences(of: "、", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private func searchableText(for item: ClosetItem) -> String {
        [
            item.name,
            item.color,
            item.brand,
            item.section.rawValue,
            item.aiAnalysis.style.joined(separator: " "),
            item.aiAnalysis.seasons.joined(separator: " "),
            item.aiAnalysis.materials.joined(separator: " "),
            item.aiAnalysis.silhouette ?? "",
            item.aiAnalysis.pattern ?? "",
            item.aiAnalysis.occasions.joined(separator: " "),
            item.aiAnalysis.formality ?? "",
            item.aiAnalysis.warmth ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func semanticMatchScore(for item: ClosetItem, keywords: [String]) -> Double {
        guard !keywords.isEmpty else { return baselineSemanticScore(for: item) }

        var score = 0.0
        for keyword in keywords {
            switch keyword {
            case _ where matches(keyword, values: item.aiAnalysis.style):
                score += 1.8
            case _ where matches(keyword, values: item.aiAnalysis.occasions):
                score += 1.8
            case _ where matches(keyword, values: item.aiAnalysis.seasons):
                score += 1.5
            case _ where matches(keyword, values: item.aiAnalysis.materials):
                score += 1.0
            case _ where contains(keyword, value: item.aiAnalysis.silhouette):
                score += 1.2
            case _ where contains(keyword, value: item.aiAnalysis.pattern):
                score += 1.2
            case _ where contains(keyword, value: item.aiAnalysis.formality):
                score += 1.6
            case _ where contains(keyword, value: item.aiAnalysis.warmth):
                score += 1.6
            case _ where contains(keyword, value: item.color):
                score += 1.4
            case _ where contains(keyword, value: item.name):
                score += 1.4
            default:
                score += semanticHintScore(for: keyword, item: item)
            }
        }
        return score
    }

    private func baselineSemanticScore(for item: ClosetItem) -> Double {
        var score = 0.0
        if item.aiAnalysis.hasContent { score += 1.2 }
        if !item.color.isEmpty { score += 0.4 }
        if !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 0.4 }
        return score
    }

    private func semanticHintScore(for keyword: String, item: ClosetItem) -> Double {
        switch keyword {
        case "通勤", "上班", "办公室", "职场":
            return containsAny(item.aiAnalysis.occasions, ["通勤"]) || contains("轻通勤", value: item.aiAnalysis.formality) || contains("正式", value: item.aiAnalysis.formality) ? 1.6 : 0
        case "日常", "休闲", "出门":
            return containsAny(item.aiAnalysis.occasions, ["日常"]) || contains("休闲", value: item.aiAnalysis.formality) ? 1.5 : 0
        case "约会", "聚会":
            return containsAny(item.aiAnalysis.occasions, ["约会", "聚会"]) || containsAny(item.aiAnalysis.style, ["温柔", "精致"]) ? 1.5 : 0
        case "旅行", "出游":
            return containsAny(item.aiAnalysis.occasions, ["旅行"]) || containsAny(item.aiAnalysis.style, ["休闲", "街头"]) ? 1.4 : 0
        case "简约", "极简":
            return containsAny(item.aiAnalysis.style, ["简约", "极简"]) ? 1.5 : 0
        case "复古":
            return containsAny(item.aiAnalysis.style, ["复古"]) ? 1.5 : 0
        case "街头":
            return containsAny(item.aiAnalysis.style, ["街头"]) ? 1.5 : 0
        case "正式":
            return contains("正式", value: item.aiAnalysis.formality) ? 1.6 : 0
        case "保暖", "御寒":
            return containsAny([item.aiAnalysis.warmth].compactMap { $0 }, ["保暖"]) ? 1.7 : 0
        case "轻薄", "清爽":
            return containsAny([item.aiAnalysis.warmth].compactMap { $0 }, ["轻薄"]) ? 1.7 : 0
        case "春", "夏", "秋", "冬":
            return containsAny(item.aiAnalysis.seasons, [keyword]) ? 1.3 : 0
        default:
            return 0
        }
    }

    private func weatherCompatibilityScore(for item: ClosetItem) -> Double {
        var score = 0.0
        let temperature = weather.feelsLike
        let warmth = item.aiAnalysis.warmth ?? ""
        let seasons = item.aiAnalysis.seasons
        let condition = weather.condition.lowercased()

        if temperature <= 8 {
            if warmth.contains("保暖") { score += 2.0 }
            if seasons.contains(where: { ["秋", "冬"].contains($0) }) { score += 1.0 }
        } else if temperature >= 25 {
            if warmth.contains("轻薄") { score += 2.0 }
            if seasons.contains(where: { ["春", "夏"].contains($0) }) { score += 1.0 }
        } else {
            if warmth.contains("适中") { score += 1.6 }
            if seasons.contains(where: { ["春", "秋"].contains($0) }) { score += 0.8 }
        }

        if (condition.contains("雨") || condition.contains("阴")) && item.section == .shoes {
            if containsAny(item.aiAnalysis.materials, ["皮革", "合成革"]) {
                score += 0.8
            }
        }

        return score
    }

    private func defaultSectionScore(for section: WardrobeSection) -> Double {
        switch section {
        case .top, .bottom, .dress, .shoes:
            return 0.8
        case .uncategorized:
            return -0.5
        }
    }

    private func matches(_ keyword: String, values: [String]) -> Bool {
        values.contains { $0.lowercased().contains(keyword) }
    }

    private func contains(_ keyword: String, value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.lowercased().contains(keyword)
    }

    private func containsAny(_ values: [String], _ targets: [String]) -> Bool {
        let normalizedValues = values.map { $0.lowercased() }
        return targets.contains { target in
            normalizedValues.contains { $0.contains(target.lowercased()) }
        }
    }

    private func mergedTopValues(from values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        var firstSeenOrder: [String] = []

        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if counts[value] == nil {
                firstSeenOrder.append(value)
            }
            counts[value, default: 0] += 1
        }

        return firstSeenOrder.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount == rhsCount {
                return firstSeenOrder.firstIndex(of: lhs) ?? 0 < firstSeenOrder.firstIndex(of: rhs) ?? 0
            }
            return lhsCount > rhsCount
        }
    }

    private func inferredOutfitCategory(
        occasion: String?,
        style: String?,
        promptKeywords: [String],
        warmth: String?
    ) -> String {
        if let occasion {
            if occasion.contains("通勤") { return "通勤搭配" }
            if occasion.contains("约会") || occasion.contains("聚会") { return "约会搭配" }
            if occasion.contains("旅行") { return "出游搭配" }
            if occasion.contains("运动") { return "运动搭配" }
        }

        if promptKeywords.contains(where: { ["通勤", "上班", "办公室"].contains($0) }) {
            return "通勤搭配"
        }
        if promptKeywords.contains(where: { ["约会", "聚会"].contains($0) }) {
            return "约会搭配"
        }
        if promptKeywords.contains(where: { ["旅行", "出游"].contains($0) }) {
            return "出游搭配"
        }
        if warmth?.contains("保暖") == true || weather.feelsLike <= 8 {
            return "保暖搭配"
        }
        if let style {
            if style.contains("简约") || style.contains("极简") { return "简约搭配" }
            if style.contains("复古") { return "复古搭配" }
            if style.contains("街头") { return "街头搭配" }
            if style.contains("温柔") { return "温柔搭配" }
        }

        return "日常搭配"
    }

    private func dominantWarmth(in items: [ClosetItem]) -> String? {
        mergedTopValues(from: items.compactMap(\.aiAnalysis.warmth)).first
    }

    private func dominantFormality(in items: [ClosetItem]) -> String? {
        mergedTopValues(from: items.compactMap(\.aiAnalysis.formality)).first
    }

    private func makeOutfitTags(
        category: String,
        occasion: String?,
        style: String?,
        seasons: [String],
        warmth: String?,
        formality: String?,
        promptKeywords: [String],
        items: [ClosetItem]
    ) -> [String] {
        var tags: [String] = [category]

        if let occasionTag = normalizedOccasionTag(from: occasion, promptKeywords: promptKeywords) {
            tags.append(occasionTag)
        }

        if let styleTag = normalizedStyleTag(from: style, promptKeywords: promptKeywords) {
            tags.append(styleTag)
        }

        if let seasonTag = normalizedSeasonTag(from: seasons, promptKeywords: promptKeywords) {
            tags.append(seasonTag)
        }

        if let weatherTag = weatherDrivenOutfitTag(warmth: warmth) {
            tags.append(weatherTag)
        }

        if let formalityTag = normalizedFormalityTag(from: formality, occasion: occasion) {
            tags.append(formalityTag)
        }

        tags.append(structureTag(for: items))

        return deduplicated(tags)
    }

    private func normalizedOccasionTag(from occasion: String?, promptKeywords: [String]) -> String? {
        if let occasion {
            if occasion.contains("通勤") { return "通勤" }
            if occasion.contains("约会") { return "约会" }
            if occasion.contains("聚会") { return "聚会" }
            if occasion.contains("旅行") { return "出游" }
            if occasion.contains("日常") { return "日常" }
            if occasion.contains("运动") { return "运动" }
        }

        if promptKeywords.contains(where: { ["通勤", "上班", "办公室", "职场"].contains($0) }) { return "通勤" }
        if promptKeywords.contains(where: { ["约会"].contains($0) }) { return "约会" }
        if promptKeywords.contains(where: { ["聚会", "派对"].contains($0) }) { return "聚会" }
        if promptKeywords.contains(where: { ["旅行", "出游"].contains($0) }) { return "出游" }
        if promptKeywords.contains(where: { ["运动", "健身"].contains($0) }) { return "运动" }
        return "日常"
    }

    private func normalizedStyleTag(from style: String?, promptKeywords: [String]) -> String? {
        if let style {
            if style.contains("简约") || style.contains("极简") { return "简约" }
            if style.contains("复古") { return "复古" }
            if style.contains("街头") { return "街头" }
            if style.contains("温柔") { return "温柔" }
            if style.contains("通勤") { return "干练" }
        }

        if promptKeywords.contains(where: { ["简约", "极简"].contains($0) }) { return "简约" }
        if promptKeywords.contains(where: { ["复古"].contains($0) }) { return "复古" }
        if promptKeywords.contains(where: { ["街头"].contains($0) }) { return "街头" }
        if promptKeywords.contains(where: { ["温柔"].contains($0) }) { return "温柔" }
        return nil
    }

    private func normalizedSeasonTag(from seasons: [String], promptKeywords: [String]) -> String? {
        if seasons.contains("冬") || promptKeywords.contains("冬") { return "冬季" }
        if seasons.contains("秋") || promptKeywords.contains("秋") { return "秋季" }
        if seasons.contains("夏") || promptKeywords.contains("夏") { return "夏季" }
        if seasons.contains("春") || promptKeywords.contains("春") { return "春季" }
        return nil
    }

    private func weatherDrivenOutfitTag(warmth: String?) -> String? {
        if warmth?.contains("保暖") == true || weather.feelsLike <= 8 { return "保暖" }
        if warmth?.contains("轻薄") == true || weather.feelsLike >= 25 { return "清爽" }
        if weather.condition.contains("雨") { return "雨天" }
        if weather.condition.contains("阴") { return "阴天" }
        return nil
    }

    private func normalizedFormalityTag(from formality: String?, occasion: String?) -> String? {
        if let formality {
            if formality.contains("正式") { return "正式感" }
            if formality.contains("轻通勤") { return "轻通勤" }
            if formality.contains("休闲") { return "休闲" }
        }

        if occasion?.contains("通勤") == true { return "轻通勤" }
        return nil
    }

    private func structureTag(for items: [ClosetItem]) -> String {
        if items.contains(where: { $0.section == .dress }) {
            return "裙装搭配"
        }
        return "上下装搭配"
    }

    private func deduplicated(_ tags: [String]) -> [String] {
        tags.reduce(into: [String]()) { result, tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
    }

    private struct OutfitMetadata {
        let category: String
        let tags: [String]
        let summary: String
    }

    private static func seedSnapshot() -> ClosetSnapshot {
        var snapshot = MockClosetDashboard.sampleSnapshot
        guard var firstCloset = snapshot.closetSpaces.first else { return snapshot }
        let items = firstCloset.wardrobeItems
        let look1 = OutfitPreview(
            title: "日常简洁风",
            subtitle: "白色短上衣 + 浅蓝牛仔裤 + 小白鞋",
            symbol: "sparkles",
            accent: "cloud",
            itemIDs: [items[0].id, items[5].id, items[8].id],
            createdAt: .now.addingTimeInterval(-86_400 * 3),
            sourceMode: .ai
        )
        let look2 = OutfitPreview(
            title: "轻熟一体感",
            subtitle: "黑色连衣裙 + 小白鞋",
            symbol: "sun.max",
            accent: "mist",
            itemIDs: [items[7].id, items[8].id],
            createdAt: .now.addingTimeInterval(-86_400),
            sourceMode: .manual
        )
        firstCloset.savedLooks = [look1, look2]
        firstCloset.diaryEntries = [
            DiaryEntry(date: .now.addingTimeInterval(-86_400 * 2), mood: "开心", note: "白上衣配浅牛仔，出门省心。", hasPhoto: false, photoFileName: nil, outfitID: look1.id, itemIDs: look1.itemIDs),
            DiaryEntry(date: .now, mood: "利落", note: "试了连衣裙搭小白鞋，整体更利落。", hasPhoto: false, outfitID: look2.id, itemIDs: look2.itemIDs)
        ]
        snapshot.closetSpaces[0] = firstCloset
        snapshot.selectedClosetID = firstCloset.id
        return snapshot
    }

    private func ensureBundledSeedContent() {
        let seedItemResources: [String: String] = [
            "白色短上衣": "上衣1",
            "黑色短上衣": "上衣2",
            "灰色短上衣": "上衣3",
            "米色针织上衣": "上衣4",
            "蓝色衬衣背面": "衬衣背面",
            "浅蓝牛仔裤": "裤子1",
            "深蓝牛仔裤": "裤子2",
            "黑色连衣裙": "连衣裙1",
            "小白鞋": "鞋子1"
        ]
        let seedBodyResources: [String: String] = [
            "正面": "女生正面",
            "侧面": "女生侧面",
            "背面": "女生背面"
        ]

        var didChange = false

        for closetIndex in closetSpaces.indices {
            for itemIndex in closetSpaces[closetIndex].wardrobeItems.indices {
                guard let resourceName = seedItemResources[closetSpaces[closetIndex].wardrobeItems[itemIndex].name] else { continue }
                let fileName = LocalImageStore.shared.saveBundledImageIfNeeded(
                    named: resourceName,
                    prefix: "item",
                    existingFileName: closetSpaces[closetIndex].wardrobeItems[itemIndex].imageFileName
                )
                if closetSpaces[closetIndex].wardrobeItems[itemIndex].imageFileName != fileName {
                    closetSpaces[closetIndex].wardrobeItems[itemIndex].imageFileName = fileName
                    didChange = true
                }
                LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: closetSpaces[closetIndex].wardrobeItems[itemIndex])
            }
        }

        for index in profile.bodyPhotos.indices {
            guard let resourceName = seedBodyResources[profile.bodyPhotos[index].title] else { continue }
            let fileName = LocalImageStore.shared.saveBundledImageIfNeeded(
                named: resourceName,
                prefix: "profile",
                existingFileName: profile.bodyPhotos[index].imageFileName
            )
            if profile.bodyPhotos[index].imageFileName != fileName {
                profile.bodyPhotos[index].imageFileName = fileName
                didChange = true
            }
        }

        if didChange {
            persist()
        }
    }

    private func migrateLegacySampleDataIfNeeded() {
        let legacyNames = Set(["雾蓝衬衫", "浅水洗牛仔裤", "复古德训鞋"])
        let currentNames = Set(wardrobeItems.map(\.name))
        guard currentNames == legacyNames else { return }

        let seed = Self.seedSnapshot()
        closetSpaces = seed.closetSpaces
        selectedClosetID = seed.selectedClosetID
        profile = seed.profile
        weather = seed.weather
        persist()
    }
}
