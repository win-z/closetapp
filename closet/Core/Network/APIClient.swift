//
//  APIClient.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let authTokenProvider: () -> String?
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = AppEnvironment.shared.apiBaseURL,
        authTokenProvider: @escaping () -> String? = { KeychainHelper.shared.readToken() }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.authTokenProvider = authTokenProvider

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(path, method: "GET", queryItems: queryItems)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path, method: "PUT", body: body)
    }

    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path, method: "PATCH", body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "DELETE")
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        try await request(
            path,
            method: method,
            queryItems: queryItems,
            body: Optional<EmptyRequestBody>.none
        )
    }

    func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        components.path = normalizedPath(path)
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.transportError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            if T.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! T
            }
            guard !data.isEmpty else {
                throw NetworkError.emptyResponse
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingFailed
            }
        case 401:
            throw NetworkError.unauthorized
        default:
            let errorPayload = try? decoder.decode(APIErrorResponse.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: errorPayload?.message)
        }
    }

    private func normalizedPath(_ path: String) -> String {
        let basePath = baseURL.path == "/" ? "" : baseURL.path
        let requestPath = path.hasPrefix("/") ? path : "/" + path
        return basePath + requestPath
    }
}

struct EmptyResponse: Codable {}

private struct APIErrorResponse: Decodable {
    let message: String?
}

private struct EmptyRequestBody: Encodable {}
