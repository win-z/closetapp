//
//  AppViewModel.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedTab: ClosetTab = .wardrobe
    @Published var stylistMode: StylistMode = .ai
    @Published var selectedWardrobeCategory: WardrobeFilter = .all
    @Published var wardrobeSearchText = ""
    @Published private(set) var authState: AuthState = .launching
    @Published private(set) var currentUser: User?

    let authManager: AuthManager
    let localStore: ClosetStore
    let wardrobeViewModel: WardrobeViewModel
    let profileViewModel: ProfileViewModel
    let diaryViewModel: DiaryViewModel
    let analyticsViewModel: AnalyticsViewModel

    private var pollingTask: Task<Void, Never>?

    init(
        authManager: AuthManager,
        localStore: ClosetStore,
        wardrobeViewModel: WardrobeViewModel,
        profileViewModel: ProfileViewModel,
        diaryViewModel: DiaryViewModel,
        analyticsViewModel: AnalyticsViewModel
    ) {
        self.authManager = authManager
        self.localStore = localStore
        self.wardrobeViewModel = wardrobeViewModel
        self.profileViewModel = profileViewModel
        self.diaryViewModel = diaryViewModel
        self.analyticsViewModel = analyticsViewModel
    }

    convenience init() {
        self.init(
            authManager: AuthManager(),
            localStore: ClosetStore(),
            wardrobeViewModel: WardrobeViewModel(),
            profileViewModel: ProfileViewModel(),
            diaryViewModel: DiaryViewModel(),
            analyticsViewModel: AnalyticsViewModel()
        )
    }

    func bootstrap() async {
        continueAsGuest()
    }

    func login(email: String, password: String) async throws {
        continueAsGuest()
    }

    func register(username: String, email: String, password: String) async throws {
        continueAsGuest()
    }

    func logout() {
        continueAsGuest()
    }

    func continueAsGuest() {
        pollingTask?.cancel()
        pollingTask = nil
        authManager.continueAsGuest()
        syncFromAuthManager()
    }

    func handleSceneBecameActive() async {
        syncFromAuthManager()
    }

    private func refreshSignedInData() async {
        await wardrobeViewModel.loadWardrobe()
        await profileViewModel.loadProfile()
        await diaryViewModel.loadDiaryEntries()
        await analyticsViewModel.loadSummary()
    }

    private func syncFromAuthManager() {
        authState = authManager.authState
        currentUser = authManager.currentUser
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, self.authState == .signedIn else { continue }
                await self.refreshSignedInData()
            }
        }
    }
}
