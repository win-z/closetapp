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
        Set(
            closetSpaces.flatMap(\.wardrobeItems).compactMap(\.imageFileName) +
            closetSpaces.flatMap(\.savedLooks).compactMap(\.photoFileName) +
            closetSpaces.flatMap(\.diaryEntries).compactMap(\.photoFileName) +
            profile.bodyPhotos.compactMap(\.imageFileName)
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
            imageFileName: imageFileName
        )
        wardrobeItems.insert(item, at: 0)
        LocalWardrobeFeatureStore.shared.precomputeFeatureIfNeeded(for: item)
        return item
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
        guard
            let top = activeWardrobeItems.first(where: { $0.section == .top }),
            let bottom = activeWardrobeItems.first(where: { $0.section == .bottom }),
            let shoes = activeWardrobeItems.first(where: { $0.section == .shoes })
        else {
            return nil
        }

        let imageData = try await doubaoOutfitImageService.generateOutfitImage(
            prompt: prompt,
            profile: profile,
            weather: weather,
            items: [top, bottom, shoes]
        )

        let title = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "今日 AI 推荐" : "AI: \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
        let subtitle = "\(top.name) + \(bottom.name) + \(shoes.name)"
        let outfit = OutfitPreview(
            title: title,
            subtitle: subtitle,
            symbol: "sparkles",
            accent: top.gradientName,
            itemIDs: [top.id, bottom.id, shoes.id],
            sourceMode: .ai,
            photoFileName: LocalImageStore.shared.saveImageData(imageData, prefix: "outfit-ai")
        )
        savedLooks.insert(outfit, at: 0)
        return outfit
    }

    func saveManualOutfit(itemIDs: [UUID], itemLayouts: [OutfitItemLayout]? = nil) -> OutfitPreview? {
        let items = activeWardrobeItems.filter { itemIDs.contains($0.id) }
        guard !items.isEmpty else { return nil }
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
            sourceMode: .manual
        )
        savedLooks.insert(outfit, at: 0)
        return outfit
    }

    func updateOutfit(_ outfitID: UUID, from draft: OutfitDraft, photoData: Data?) {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        let orderedIDs = Array(draft.itemIDs)
        let items = wardrobeItems.filter { draft.itemIDs.contains($0.id) }
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLooks[index].title = trimmedTitle.isEmpty ? savedLooks[index].title : trimmedTitle
        savedLooks[index].subtitle = items.map(\.name).joined(separator: " + ")
        savedLooks[index].itemIDs = orderedIDs
        savedLooks[index].itemLayouts = normalizedLayouts(for: orderedIDs, proposed: draft.itemLayouts)
        savedLooks[index].photoFileName = storedImageFileName(
            newData: photoData,
            oldFileName: savedLooks[index].photoFileName,
            requestedFileName: draft.photoFileName,
            prefix: "outfit"
        )
    }

    func deleteOutfit(_ outfitID: UUID) {
        guard let index = savedLooks.firstIndex(where: { $0.id == outfitID }) else { return }
        LocalImageStore.shared.removeImage(named: savedLooks[index].photoFileName)
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

    func markers(for month: Date) -> [DiaryMarker] {
        diaryEntries.compactMap { entry in
            guard calendar.isDate(entry.date, equalTo: month, toGranularity: .month) else { return nil }
            return DiaryMarker(
                day: calendar.component(.day, from: entry.date),
                hasRecord: true,
                hasPhoto: entry.hasPhoto,
                hasOutfit: entry.outfitID != nil,
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
