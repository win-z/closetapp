//
//  DiaryViewModel.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class DiaryViewModel: ObservableObject {
    @Published private(set) var entries: [RemoteDiaryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let service: DiaryServicing
    private let cache = DiaryCacheStore()
    private let calendar = Calendar.current

    init(service: DiaryServicing) {
        self.service = service
        self.entries = cache.loadEntries()
    }

    convenience init() {
        self.init(service: DiaryService())
    }

    func loadDiaryEntries() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteEntries = try await service.fetchDiaryEntries()
            entries = remoteEntries.sorted { $0.date > $1.date }
            cache.save(entries: entries)
            errorMessage = nil
        } catch {
            if entries.isEmpty {
                entries = cache.loadEntries()
            }
            errorMessage = entries.isEmpty ? error.localizedDescription : "网络请求失败，当前显示最近一次同步的日记数据。"
        }
    }

    func saveEntry(existingID: String?, request: DiaryEntryUpsertRequest) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let entry: RemoteDiaryEntry
            if let existingID {
                entry = try await service.updateDiaryEntry(id: existingID, request: request)
            } else {
                entry = try await service.createDiaryEntry(request)
            }
            replace(entry)
            cache.save(entries: entries)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteEntry(id: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.deleteDiaryEntry(id: id)
            entries.removeAll { $0.id == id }
            cache.save(entries: entries)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func entry(for date: Date) -> RemoteDiaryEntry? {
        entries.first { entry in
            guard let parsedDate = apiDate(entry.date) else { return false }
            return calendar.isDate(parsedDate, inSameDayAs: date)
        }
    }

    func markers(for month: Date) -> [DiaryMarker] {
        entries.compactMap { entry in
            guard let parsedDate = apiDate(entry.date) else { return nil }
            guard calendar.isDate(parsedDate, equalTo: month, toGranularity: .month) else { return nil }
            let hasOutfit = entry.outfitId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || !entry.clothingIds.isEmpty
            return DiaryMarker(
                day: calendar.component(.day, from: parsedDate),
                hasRecord: true,
                hasPhoto: entry.photo?.isEmpty == false,
                hasOutfit: hasOutfit,
                mood: entry.mood
            )
        }
    }

    private func apiDate(_ rawValue: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawValue)
    }

    private func replace(_ entry: RemoteDiaryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        entries.sort { $0.date > $1.date }
    }
}

private struct DiaryCacheStore {
    private let storageKey = "lumina.diary.cache.v1"

    func loadEntries() -> [RemoteDiaryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode([RemoteDiaryEntry].self, from: data)) ?? []
    }

    func save(entries: [RemoteDiaryEntry]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
