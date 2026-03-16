//
//  DiaryService.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

protocol DiaryServicing {
    func fetchDiaryEntries() async throws -> [RemoteDiaryEntry]
    func createDiaryEntry(_ request: DiaryEntryUpsertRequest) async throws -> RemoteDiaryEntry
    func updateDiaryEntry(id: String, request: DiaryEntryUpsertRequest) async throws -> RemoteDiaryEntry
    func deleteDiaryEntry(id: String) async throws
}

struct DiaryService: DiaryServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    init() {
        self.init(apiClient: .shared)
    }

    func fetchDiaryEntries() async throws -> [RemoteDiaryEntry] {
        try await apiClient.get(APIEndpoints.Diary.list)
    }

    func createDiaryEntry(_ request: DiaryEntryUpsertRequest) async throws -> RemoteDiaryEntry {
        try await apiClient.post(APIEndpoints.Diary.list, body: request)
    }

    func updateDiaryEntry(id: String, request: DiaryEntryUpsertRequest) async throws -> RemoteDiaryEntry {
        try await apiClient.put(APIEndpoints.Diary.item(id), body: request)
    }

    func deleteDiaryEntry(id: String) async throws {
        let _: EmptyResponse = try await apiClient.delete(APIEndpoints.Diary.item(id))
    }
}
