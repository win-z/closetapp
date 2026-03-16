//
//  WardrobeViewModel.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class WardrobeViewModel: ObservableObject {
    @Published private(set) var items: [ClothingItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let service: WardrobeServicing
    private let cache = WardrobeCacheStore()

    init(service: WardrobeServicing) {
        self.service = service
        self.items = cache.loadItems()
    }

    convenience init() {
        self.init(service: WardrobeService())
    }

    func loadWardrobe() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteItems = try await service.fetchWardrobe()
            items = remoteItems
            cache.save(items: remoteItems)
            errorMessage = nil
        } catch {
            if items.isEmpty {
                items = cache.loadItems()
            }
            errorMessage = items.isEmpty ? error.localizedDescription : "网络请求失败，当前显示最近一次同步的衣橱数据。"
        }
    }

    var activeItems: [ClothingItem] {
        items.filter { !$0.isArchived }
    }

    var archivedItems: [ClothingItem] {
        items.filter(\.isArchived)
    }

    func createItem(_ request: WardrobeItemUpsertRequest) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let item = try await service.createWardrobeItem(request)
            items.insert(item, at: 0)
            cache.save(items: items)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateItem(id: String, request: WardrobeItemUpsertRequest) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let item = try await service.updateWardrobeItem(id: id, request: request)
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = item
            } else {
                items.insert(item, at: 0)
            }
            cache.save(items: items)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteItem(id: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.deleteWardrobeItem(id: id)
            items.removeAll { $0.id == id }
            cache.save(items: items)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markItemWorn(id: String) async {
        do {
            let item = try await service.markItemWorn(id: id)
            replace(item)
            cache.save(items: items)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleArchive(for item: ClothingItem) async {
        do {
            let updated = try await service.setArchived(id: item.id, isArchived: !item.isArchived)
            replace(updated)
            cache.save(items: items)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autoTag(imageBase64: String) async -> AutoTagResponse? {
        do {
            let response = try await service.autoTag(imageBase64: imageBase64)
            errorMessage = nil
            return response
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func replace(_ item: ClothingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }
}

private struct WardrobeCacheStore {
    private let storageKey = "lumina.wardrobe.cache.v1"

    func loadItems() -> [ClothingItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode([ClothingItem].self, from: data)) ?? []
    }

    func save(items: [ClothingItem]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
