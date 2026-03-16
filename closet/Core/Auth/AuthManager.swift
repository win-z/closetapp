//
//  AuthManager.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var authState: AuthState = .launching

    private let apiClient: APIClient
    private let keychain: KeychainHelper

    init(apiClient: APIClient, keychain: KeychainHelper) {
        self.apiClient = apiClient
        self.keychain = keychain
    }

    convenience init() {
        self.init(apiClient: .shared, keychain: .shared)
    }

    var isAuthenticated: Bool {
        currentUser != nil && keychain.readToken() != nil
    }

    func bootstrap() async {
        guard keychain.readToken() != nil else {
            authState = .signedOut
            return
        }

        do {
            let user: User = try await apiClient.get(APIEndpoints.Auth.profile)
            currentUser = user
            authState = .signedIn
        } catch {
            keychain.clearToken()
            currentUser = nil
            authState = .signedOut
        }
    }

    func login(email: String, password: String) async throws {
        authState = .authenticating
        let response: AuthResponse = try await apiClient.post(
            APIEndpoints.Auth.login,
            body: LoginRequest(email: email, password: password)
        )
        keychain.saveToken(response.token)
        currentUser = response.user
        authState = .signedIn
    }

    func register(username: String, email: String, password: String) async throws {
        authState = .authenticating
        let response: AuthResponse = try await apiClient.post(
            APIEndpoints.Auth.register,
            body: RegisterRequest(nickname: username, email: email, password: password)
        )
        keychain.saveToken(response.token)
        currentUser = response.user
        authState = .signedIn
    }

    func logout() {
        keychain.clearToken()
        currentUser = nil
        authState = .signedOut
    }

    func continueAsGuest() {
        keychain.clearToken()
        currentUser = nil
        authState = .guest
    }
}

enum AuthState: Equatable {
    case launching
    case signedOut
    case authenticating
    case guest
    case signedIn
}
