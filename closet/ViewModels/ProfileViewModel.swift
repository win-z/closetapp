//
//  ProfileViewModel.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: BodyProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let service: UserServicing
    private let cache = ProfileCacheStore()

    init(service: UserServicing) {
        self.service = service
        self.profile = cache.loadProfile()
    }

    convenience init() {
        self.init(service: UserService())
    }

    func loadProfile() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteProfile = try await service.fetchProfile()
            profile = remoteProfile
            cache.save(profile: remoteProfile)
            errorMessage = nil
        } catch {
            if profile == nil {
                profile = cache.loadProfile()
            }
            errorMessage = profile == nil ? error.localizedDescription : "网络请求失败，当前显示最近一次同步的身体档案。"
        }
    }

    func updateProfile(_ profile: BodyProfile) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await service.updateProfile(profile)
            self.profile = updated
            cache.save(profile: updated)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct ProfileCacheStore {
    private let storageKey = "lumina.profile.cache.v1"

    func loadProfile() -> BodyProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(BodyProfile.self, from: data)
    }

    func save(profile: BodyProfile) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
