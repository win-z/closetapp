//
//  DoubaoOutfitImageService.swift
//  closet
//
//  Created by Codex on 2026/3/13.
//

import Foundation
import OSLog

struct DoubaoOutfitImageService {
    private let session: URLSession
    private let environment: AppEnvironment.Configuration
    private let logger = Logger(subsystem: "winz.closet", category: "DoubaoOutfitImage")

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
        let finalPrompt = makePrompt(prompt: prompt, profile: profile, weather: weather, items: items)
        let requestBody = DoubaoGenerationRequest(
            model: environment.doubaoModel,
            prompt: finalPrompt,
            size: "2K",
            responseFormat: "url",
            image: referenceImages,
            stream: false,
            watermark: false,
            sequentialImageGeneration: "disabled"
        )

        logger.info("Doubao request start model=\(self.environment.doubaoModel, privacy: .public) images=\(referenceImages.count) bodyPhotos=\(self.availableBodyPhotoCount(profile: profile)) items=\(items.count)")
        logger.debug("Doubao prompt: \(finalPrompt, privacy: .public)")

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
            logger.error("Doubao request transport error: \(error.localizedDescription, privacy: .public)")
            throw DoubaoOutfitImageError.transport(networkErrorDescription(from: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Doubao invalid response object")
            throw DoubaoOutfitImageError.invalidResponse
        }

        logger.info("Doubao response status=\(httpResponse.statusCode)")

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let message = parseErrorMessage(from: responseData)
            logger.error("Doubao server error status=\(httpResponse.statusCode) message=\(message ?? "nil", privacy: .public)")
            throw DoubaoOutfitImageError.server(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(DoubaoGenerationResponse.self, from: responseData)
        logger.info("Doubao response decoded images=\(payload.data.count)")

        if let first = payload.data.first {
            if let imageURLString = first.url, let imageURL = URL(string: imageURLString) {
                logger.info("Doubao image url received")
                do {
                    let (imageData, _) = try await session.data(from: imageURL)
                    logger.info("Doubao image download success bytes=\(imageData.count)")
                    return imageData
                } catch {
                    logger.error("Doubao image download error: \(error.localizedDescription, privacy: .public)")
                    throw DoubaoOutfitImageError.transport(networkErrorDescription(from: error))
                }
            }

            if let base64 = first.b64Json, let imageData = Data(base64Encoded: base64) {
                logger.info("Doubao base64 image received bytes=\(imageData.count)")
                return imageData
            }
        }

        logger.error("Doubao empty result")
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
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let customRequirement = userPrompt.isEmpty ? "自然、真实、适合日常穿搭展示" : userPrompt
        let bodyPhotos = profile.bodyPhotos.filter { $0.imageFileName != nil }
        let bodyPhotoLines = bodyPhotos.enumerated().map { index, photo in
            "图\(index + 1)是用户的\(photo.title)全身参考图。"
        }.joined(separator: "\n")
        let clothingStartIndex = bodyPhotos.count + 1
        let clothingLines = items.enumerated().map { index, item in
            "图\(clothingStartIndex + index)是要穿在人物身上的\(item.section.rawValue)，名称\(item.name)，颜色\(item.color)，品牌\(item.brand)。"
        }.joined(separator: "\n")
        let clothingAnalysisLines = items.enumerated().map { index, item in
            "图\(clothingStartIndex + index)的AI分析：\(aiAnalysisSummary(for: item.aiAnalysis))"
        }.joined(separator: "\n")
        let outfitInstruction = items.enumerated().map { index, item in
            "将图\(clothingStartIndex + index)中的\(item.name)穿在同一个人物身上。"
        }.joined(separator: "\n")

        return """
        虚拟试穿照片生成任务。

        【人物一致性要求 - 必须严格遵守】
        \(bodyPhotoLines)
        以上参考图都是同一个用户的三视图或多视角照片。
        生成结果必须保持这个人的面部特征、五官细节、发型发色、身材比例、身高体型、肤色完全一致，不能替换成其他人。

        【服装参考图】
        \(clothingLines)
        \(clothingAnalysisLines)

        【试穿要求】
        \(outfitInstruction)
        最终人物必须穿的是当前搭配里的这些衣服，不允许替换成其他款式，不允许改变服装主颜色、版型、材质和关键细节。

        【用户与场景补充】
        用户昵称：\(profile.name)
        身高：\(profile.heightCm)cm
        体重：\(profile.weightKg)kg
        天气：\(weather.location)，\(weather.condition)，\(weather.temperature)°C，体感\(weather.feelsLike)°C
        用户要求：\(customRequirement)

        【输出要求】
        生成 9:16 竖图，适合作为已保存搭配的试穿封面。
        人物站在画面正中间，全身完整显示，正面朝向镜头。
        背景简洁干净，自然光照，服装纹理清晰，整体效果真实自然。
        """
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? JSONDecoder().decode(DoubaoErrorResponse.self, from: data) {
            return errorResponse.error?.message ?? errorResponse.message
        }

        return String(data: data, encoding: .utf8)
    }

    private func networkErrorDescription(from error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return "当前网络无法解析或连接豆包域名，请检查设备网络、DNS、代理或地区访问限制。"
        case .notConnectedToInternet:
            return "当前设备未连接互联网，请检查网络后重试。"
        case .timedOut:
            return "请求豆包超时，请稍后重试。"
        default:
            return urlError.localizedDescription
        }
    }

    private func availableBodyPhotoCount(profile: ProfileData) -> Int {
        profile.bodyPhotos.filter { $0.imageFileName != nil }.count
    }

    private func aiAnalysisSummary(for analysis: ClothingAIAnalysis) -> String {
        guard analysis.hasContent else { return "暂无额外分析信息。" }

        var parts: [String] = []
        if !analysis.style.isEmpty { parts.append("风格：\(analysis.style.joined(separator: "、"))") }
        if !analysis.seasons.isEmpty { parts.append("季节：\(analysis.seasons.joined(separator: "、"))") }
        if !analysis.materials.isEmpty { parts.append("材质：\(analysis.materials.joined(separator: "、"))") }
        if let silhouette = analysis.silhouette, !silhouette.isEmpty { parts.append("版型：\(silhouette)") }
        if let pattern = analysis.pattern, !pattern.isEmpty { parts.append("图案：\(pattern)") }
        if !analysis.occasions.isEmpty { parts.append("场合：\(analysis.occasions.joined(separator: "、"))") }
        if let formality = analysis.formality, !formality.isEmpty { parts.append("正式度：\(formality)") }
        if let warmth = analysis.warmth, !warmth.isEmpty { parts.append("保暖度：\(warmth)") }
        return parts.joined(separator: "；")
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
    let stream: Bool
    let watermark: Bool
    let sequentialImageGeneration: String

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case size
        case responseFormat = "response_format"
        case image
        case stream
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
