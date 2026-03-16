//
//  AppEnvironment.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum AppEnvironment {
    static let shared = Configuration()

    struct Configuration {
        let apiBaseURL: URL
        let doubaoAPIURL: URL
        let doubaoAPIKey: String
        let doubaoModel: String
        let siliconFlowAPIURL: URL
        let siliconFlowAPIKey: String
        let siliconFlowVisionModel: String
        let appName: String

        init() {
            let configuredBaseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            apiBaseURL = URL(string: configuredBaseURL?.nilIfBlank ?? Self.defaultAPIBaseURL)!

            let configuredDoubaoURL = Bundle.main.object(forInfoDictionaryKey: "DOUBAO_API_URL") as? String
            doubaoAPIURL = URL(string: configuredDoubaoURL?.nilIfBlank ?? "https://ark.cn-beijing.volces.com/api/v3")!

            let configuredDoubaoAPIKey = Bundle.main.object(forInfoDictionaryKey: "DOUBAO_API_KEY") as? String
            doubaoAPIKey = configuredDoubaoAPIKey?.nilIfBlank ?? ""

            let configuredDoubaoModel = Bundle.main.object(forInfoDictionaryKey: "DOUBAO_MODEL") as? String
            doubaoModel = configuredDoubaoModel?.nilIfBlank ?? "doubao-seedream-4-5-251128"

            let configuredSiliconFlowURL = Bundle.main.object(forInfoDictionaryKey: "SILICONFLOW_API_URL") as? String
            siliconFlowAPIURL = URL(string: configuredSiliconFlowURL?.nilIfBlank ?? "https://api.siliconflow.cn/v1")!

            let configuredSiliconFlowAPIKey = Bundle.main.object(forInfoDictionaryKey: "SILICONFLOW_API_KEY") as? String
            siliconFlowAPIKey = configuredSiliconFlowAPIKey?.nilIfBlank ?? ""

            let configuredSiliconFlowVisionModel = Bundle.main.object(forInfoDictionaryKey: "SILICONFLOW_VISION_MODEL") as? String
            siliconFlowVisionModel = configuredSiliconFlowVisionModel?.nilIfBlank ?? "Qwen/Qwen2.5-VL-32B-Instruct"

            appName = "Lumina Closet AI"
        }

        private static var defaultAPIBaseURL: String {
            #if DEBUG
                return "http://127.0.0.1:3000"
            #else
                return "https://101.37.159.90:3000"
            #endif
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
