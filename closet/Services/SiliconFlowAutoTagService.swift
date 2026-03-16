//
//  SiliconFlowAutoTagService.swift
//  closet
//
//  Created by Codex on 2026/3/13.
//

import Foundation

struct SiliconFlowAutoTagService {
    private let session: URLSession
    private let environment: AppEnvironment.Configuration

    init(
        session: URLSession = .shared,
        environment: AppEnvironment.Configuration = AppEnvironment.shared
    ) {
        self.session = session
        self.environment = environment
    }

    func autoTag(imageBase64: String) async throws -> AutoTagResponse {
        guard !environment.siliconFlowAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SiliconFlowAutoTagError.missingAPIKey
        }

        let normalizedImage = imageBase64.hasPrefix("data:image")
            ? imageBase64
            : "data:image/jpeg;base64,\(imageBase64)"

        let prompt = """
        分析这张服装图片，识别以下信息并返回 JSON：
        {
          "name": "简短中文名称",
          "color": "主色调",
          "category": "上装/下装/连衣裙/外套/鞋履/配饰",
          "brand": "品牌名称或 null",
          "tags": ["风格1", "季节1", "材质1", "场合1"]
        }

        要求：
        - 如果品牌无法识别，返回 null
        - category 必须从固定枚举中选
        - 只返回 JSON
        """

        let body = SiliconFlowChatRequest(
            model: environment.siliconFlowVisionModel,
            messages: [
                SiliconFlowMessage(
                    role: "user",
                    content: [
                        .imageURL(url: normalizedImage),
                        .text(prompt)
                    ]
                )
            ],
            maxTokens: 500,
            temperature: 0.2
        )

        let endpoint = environment.siliconFlowAPIURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(environment.siliconFlowAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw SiliconFlowAutoTagError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SiliconFlowAutoTagError.invalidResponse
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let serverMessage = parseServerMessage(from: responseData)
            throw SiliconFlowAutoTagError.server(statusCode: httpResponse.statusCode, message: serverMessage)
        }

        let payload = try JSONDecoder().decode(SiliconFlowChatResponse.self, from: responseData)
        guard let content = payload.choices.first?.message.content?.nilIfBlank else {
            throw SiliconFlowAutoTagError.emptyResult
        }

        guard let jsonString = extractJSONObject(from: content),
              let jsonData = jsonString.data(using: .utf8)
        else {
            throw SiliconFlowAutoTagError.invalidJSON
        }

        let decoded = try JSONDecoder().decode(SiliconFlowAutoTagPayload.self, from: jsonData)
        return decoded.normalized
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}")
        else {
            return nil
        }
        return String(text[start ... end])
    }

    private func parseServerMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(SiliconFlowErrorResponse.self, from: data) {
            return payload.error?.message ?? payload.message
        }
        return String(data: data, encoding: .utf8)
    }
}

enum SiliconFlowAutoTagError: LocalizedError {
    case missingAPIKey
    case transport(String)
    case invalidResponse
    case server(statusCode: Int, message: String?)
    case emptyResult
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 SiliconFlow API Key，请先填写 SILICONFLOW_API_KEY。"
        case let .transport(message):
            return "请求硅基流动失败：\(message)"
        case .invalidResponse:
            return "硅基流动返回了无法识别的响应。"
        case let .server(statusCode, message):
            return "硅基流动识别失败（\(statusCode)）：\(message ?? "请稍后重试")"
        case .emptyResult:
            return "识别结果为空，请换一张更清晰的服装图片再试。"
        case .invalidJSON:
            return "识别结果解析失败，请重试。"
        }
    }
}

private struct SiliconFlowChatRequest: Encodable {
    let model: String
    let messages: [SiliconFlowMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct SiliconFlowMessage: Encodable {
    let role: String
    let content: [SiliconFlowContent]
}

private struct SiliconFlowContent: Encodable {
    let type: String
    let text: String?
    let imageURL: ImageURLPayload?

    static func text(_ value: String) -> SiliconFlowContent {
        SiliconFlowContent(type: "text", text: value, imageURL: nil)
    }

    static func imageURL(url: String) -> SiliconFlowContent {
        SiliconFlowContent(type: "image_url", text: nil, imageURL: ImageURLPayload(url: url))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ImageURLPayload: Encodable {
    let url: String
}

private struct SiliconFlowChatResponse: Decodable {
    let choices: [SiliconFlowChoice]
}

private struct SiliconFlowChoice: Decodable {
    let message: SiliconFlowResponseMessage
}

private struct SiliconFlowResponseMessage: Decodable {
    let content: String?
}

private struct SiliconFlowErrorResponse: Decodable {
    let message: String?
    let error: SiliconFlowErrorDetail?
}

private struct SiliconFlowErrorDetail: Decodable {
    let message: String?
}

private struct SiliconFlowAutoTagPayload: Decodable {
    let name: String?
    let color: String?
    let category: String?
    let brand: String?
    let tags: [String]?

    var normalized: AutoTagResponse {
        AutoTagResponse(
            category: normalizedCategory,
            name: name?.nilIfBlank,
            color: color?.nilIfBlank,
            brand: brandValue,
            tags: tags?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    private var normalizedCategory: ClothingCategory? {
        guard let category = category?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return ClothingCategory(rawValue: category)
    }

    private var brandValue: String? {
        guard let brand = brand?.nilIfBlank else { return nil }
        return brand.lowercased() == "null" ? nil : brand
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
