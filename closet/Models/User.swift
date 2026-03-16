//
//  User.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

struct User: Codable, Equatable, Identifiable {
    let id: String
    var nickname: String
    var email: String

    var username: String {
        nickname
    }

    init(id: String, nickname: String, email: String) {
        self.id = id
        self.nickname = nickname
        self.email = email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyString(forKey: .id)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
            ?? container.decodeIfPresent(String.self, forKey: .username)
            ?? ""
        email = try container.decode(String.self, forKey: .email)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(email, forKey: .email)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case username
        case email
    }
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let nickname: String
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let token: String
    let user: User
}

private extension KeyedDecodingContainer where K == User.CodingKeys {
    func decodeLossyString(forKey key: K) throws -> String {
        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing required string value")
        )
    }
}
