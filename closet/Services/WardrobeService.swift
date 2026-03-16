//
//  WardrobeService.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

protocol WardrobeServicing {
    func fetchWardrobe() async throws -> [ClothingItem]
    func createWardrobeItem(_ request: WardrobeItemUpsertRequest) async throws -> ClothingItem
    func updateWardrobeItem(id: String, request: WardrobeItemUpsertRequest) async throws -> ClothingItem
    func deleteWardrobeItem(id: String) async throws
    func markItemWorn(id: String) async throws -> ClothingItem
    func setArchived(id: String, isArchived: Bool) async throws -> ClothingItem
    func autoTag(imageBase64: String) async throws -> AutoTagResponse
}

struct WardrobeService: WardrobeServicing {
    private let apiClient: APIClient
    private let autoTagService: SiliconFlowAutoTagService

    init(
        apiClient: APIClient,
        autoTagService: SiliconFlowAutoTagService = SiliconFlowAutoTagService()
    ) {
        self.apiClient = apiClient
        self.autoTagService = autoTagService
    }

    init() {
        self.init(apiClient: .shared)
    }

    func fetchWardrobe() async throws -> [ClothingItem] {
        try await apiClient.get(APIEndpoints.Wardrobe.list)
    }

    func createWardrobeItem(_ request: WardrobeItemUpsertRequest) async throws -> ClothingItem {
        try await apiClient.post(APIEndpoints.Wardrobe.list, body: request)
    }

    func updateWardrobeItem(id: String, request: WardrobeItemUpsertRequest) async throws -> ClothingItem {
        try await apiClient.put(APIEndpoints.Wardrobe.item(id), body: request)
    }

    func deleteWardrobeItem(id: String) async throws {
        let _: EmptyResponse = try await apiClient.delete(APIEndpoints.Wardrobe.item(id))
    }

    func markItemWorn(id: String) async throws -> ClothingItem {
        try await apiClient.post(APIEndpoints.Wardrobe.wear(id), body: EmptyBody())
    }

    func setArchived(id: String, isArchived: Bool) async throws -> ClothingItem {
        try await apiClient.patch(
            APIEndpoints.Wardrobe.archive(id),
            body: ArchiveClothingItemRequest(isArchived: isArchived)
        )
    }

    func autoTag(imageBase64: String) async throws -> AutoTagResponse {
        try await autoTagService.autoTag(imageBase64: imageBase64)
    }
}

private struct EmptyBody: Encodable {}
