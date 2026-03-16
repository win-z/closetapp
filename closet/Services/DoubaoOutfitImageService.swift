//
//  DoubaoOutfitImageService.swift
//  closet
//
//  Created by Codex on 2026/3/13.
//

import Foundation

struct DoubaoOutfitImageService {
    private let session: URLSession
    private let environment: AppEnvironment.Configuration

    init(
        session: URLSession = .shared,
        environment: AppEnvironment.Configuration = AppEnvironment.shared
    ) {
        self.session = session
        self.environment = environment
    }

    func generateOutfitImage(
        prompt: String,
        profile: ProfileData,
        weather: WeatherSnapshot,
        items: [ClosetItem]
    ) async throws -> Data {
        guard !environment.doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DoubaoOutfitImageError.missingAPIKey
        }

        let referenceImages = try makeReferenceImages(profile: profile, items: items)
        let requestBody = DoubaoGenerationRequest(
            model: environment.doubaoModel,
            prompt: makePrompt(prompt: prompt, profile: profile, weather: weather, items: items),
            size: "2K",
            responseFormat: "url",
            image: referenceImages,
            watermark: false,
            sequentialImageGeneration: "disabled"
        )

        let endpoint = environment.doubaoAPIURL.appending(path: "images/generations")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(environment.doubaoAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw DoubaoOutfitImageError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DoubaoOutfitImageError.invalidResponse
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let message = parseErrorMessage(from: responseData)
            throw DoubaoOutfitImageError.server(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(DoubaoGenerationResponse.self, from: responseData)

        if let first = payload.data.first {
            if let imageURLString = first.url, let imageURL = URL(string: imageURLString) {
                do {
                    let (imageData, _) = try await session.data(from: imageURL)
                    return imageData
                } catch {
                    throw DoubaoOutfitImageError.transport(error.localizedDescription)
                }
            }

            if let base64 = first.b64Json, let imageData = Data(base64Encoded: base64) {
                return imageData
            }
        }

        throw DoubaoOutfitImageError.emptyResult
    }

    private func makeReferenceImages(profile: ProfileData, items: [ClosetItem]) throws -> [String] {
        let bodyImages = profile.bodyPhotos.compactMap { photo in
            dataURL(forLocalFileName: photo.imageFileName)
        }

        let clothingImages = items.compactMap { item in
            dataURL(forLocalFileName: item.imageFileName)
        }

        let references = bodyImages + clothingImages
        guard references.count >= 2 else {
            throw DoubaoOutfitImageError.missingReferenceImages
        }
        return references
    }

    private func dataURL(forLocalFileName fileName: String?) -> String? {
        guard let data = LocalImageStore.shared.loadImageData(named: fileName) else { return nil }
        let mimeType = data.detectedMimeType
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func makePrompt(
        prompt: String,
        profile: ProfileData,
        weather: WeatherSnapshot,
        items: [ClosetItem]
    ) -> String {
        let itemLines = items.map { item in
            "- \(item.section.rawValue)：\(item.name)，颜色\(item.color)，品牌\(item.brand)"
        }.joined(separator: "\n")

        let bodyPhotoTitles = profile.bodyPhotos
            .filter { $0.imageFileName != nil }
            .map(\.title)
            .joined(separator: "、")

        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let customRequirement = userPrompt.isEmpty ? "自然、真实、适合日常穿搭展示" : userPrompt

        return """
        你是一名电商视觉造型师，请根据参考图生成一张真实自然的 AI 穿搭展示图。

        【人物要求】
        保持同一个人的面部特征、发型、肤色和身材比例一致。
        已提供的人体参考角度：\(bodyPhotoTitles.isEmpty ? "正面" : bodyPhotoTitles)。

        【用户档案】
        - 昵称：\(profile.name)
        - 身高：\(profile.heightCm)cm
        - 体重：\(profile.weightKg)kg

        【天气场景】
        - 地点：\(weather.location)
        - 天气：\(weather.condition)
        - 温度：\(weather.temperature)°C
        - 体感：\(weather.feelsLike)°C

        【服装要求】
        严格使用参考服装，保持款式、颜色、材质和轮廓一致：
        \(itemLines)

        【画面要求】
        - 生成 9:16 竖图
        - 全身完整出镜，人物位于画面中间
        - 背景简洁干净，适合穿搭展示
        - 光线自然，服装纹理清晰
        - 整体风格：\(customRequirement)
        """
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? JSONDecoder().decode(DoubaoErrorResponse.self, from: data) {
            return errorResponse.error?.message ?? errorResponse.message
        }

        return String(data: data, encoding: .utf8)
    }
}

enum DoubaoOutfitImageError: LocalizedError {
    case missingAPIKey
    case missingReferenceImages
    case transport(String)
    case invalidResponse
    case server(statusCode: Int, message: String?)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置豆包 API Key，请先在应用配置中填写 DOUBAO_API_KEY。"
        case .missingReferenceImages:
            return "缺少可用的人像或衣物参考图，暂时无法生成穿搭图。"
        case let .transport(message):
            return "请求豆包生图失败：\(message)"
        case .invalidResponse:
            return "豆包返回了无法识别的响应。"
        case let .server(statusCode, message):
            return "豆包生图失败（\(statusCode)）：\(message ?? "请稍后重试")"
        case .emptyResult:
            return "豆包没有返回可下载的图片。"
        }
    }
}

private struct DoubaoGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let size: String
    let responseFormat: String
    let image: [String]
    let watermark: Bool
    let sequentialImageGeneration: String

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case size
        case responseFormat = "response_format"
        case image
        case watermark
        case sequentialImageGeneration = "sequential_image_generation"
    }
}

private struct DoubaoGenerationResponse: Decodable {
    let data: [DoubaoGenerationResult]
}

private struct DoubaoGenerationResult: Decodable {
    let url: String?
    let b64Json: String?

    enum CodingKeys: String, CodingKey {
        case url
        case b64Json = "b64_json"
    }
}

private struct DoubaoErrorResponse: Decodable {
    let message: String?
    let error: DoubaoErrorDetail?
}

private struct DoubaoErrorDetail: Decodable {
    let message: String?
}

private extension Data {
    var detectedMimeType: String {
        let bytes = [UInt8](prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if bytes.count >= 12,
           bytes[0 ... 3] == [0x52, 0x49, 0x46, 0x46],
           bytes[8 ... 11] == [0x57, 0x45, 0x42, 0x50]
        {
            return "image/webp"
        }
        return "image/jpeg"
    }
}
