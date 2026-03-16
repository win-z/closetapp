//
//  UserService.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

protocol UserServicing {
    func fetchProfile() async throws -> BodyProfile
    func updateProfile(_ profile: BodyProfile) async throws -> BodyProfile
}

struct UserService: UserServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    init() {
        self.init(apiClient: .shared)
    }

    func fetchProfile() async throws -> BodyProfile {
        try await apiClient.get(APIEndpoints.Auth.profile)
    }

    func updateProfile(_ profile: BodyProfile) async throws -> BodyProfile {
        try await apiClient.put(APIEndpoints.Auth.profile, body: profile)
    }
}
