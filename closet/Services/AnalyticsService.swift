//
//  AnalyticsService.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

protocol AnalyticsServicing {
    func fetchSummary() async throws -> [String: JSONValue]
    func analyzeWardrobe() async throws -> JSONValue
}

struct AnalyticsService: AnalyticsServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    init() {
        self.init(apiClient: .shared)
    }

    func fetchSummary() async throws -> [String: JSONValue] {
        try await apiClient.get(APIEndpoints.Analytics.summary)
    }

    func analyzeWardrobe() async throws -> JSONValue {
        try await apiClient.post(APIEndpoints.AI.analyze, body: EmptyBody())
    }
}

private struct EmptyBody: Encodable {}
