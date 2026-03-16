//
//  APIEndpoints.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum APIEndpoints {
    enum Auth {
        static let login = "/api/auth/login"
        static let register = "/api/auth/register"
        static let profile = "/api/users/profile"
    }

    enum Wardrobe {
        static let list = "/api/wardrobe"

        static func item(_ id: String) -> String { "/api/wardrobe/\(id)" }
        static func wear(_ id: String) -> String { "/api/wardrobe/\(id)/wear" }
        static func archive(_ id: String) -> String { "/api/wardrobe/\(id)/archive" }
    }

    enum AI {
        static let autoTag = "/api/ai/auto-tag"
        static let outfit = "/api/ai/outfit"
        static let tryOn = "/api/ai/try-on"
        static let analyze = "/api/ai/analyze"
        static let capsule = "/api/ai/capsule"
    }

    enum Diary {
        static let list = "/api/diary"

        static func item(_ id: String) -> String { "/api/diary/\(id)" }
    }

    enum Outfits {
        static let list = "/api/outfits"

        static func item(_ id: String) -> String { "/api/outfits/\(id)" }
    }

    enum Analytics {
        static let summary = "/api/analytics/wardrobe"
    }

    enum Weather {
        static let current = "/api/weather"
    }
}
