//
//  AnalyticsService.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation
import OSLog

protocol AnalyticsServicing {
    func fetchSummary() async throws -> [String: JSONValue]
    func analyzeWardrobe(_ input: WardrobeAnalysisInput) async throws -> String
}

struct AnalyticsService: AnalyticsServicing {
    private let requestTimeout: TimeInterval = 180
    private let apiClient: APIClient
    private let session: URLSession
    private let environment: AppEnvironment.Configuration
    private let logger = Logger(subsystem: "winz.closet", category: "AnalyticsService")

    init(
        apiClient: APIClient,
        session: URLSession = .shared,
        environment: AppEnvironment.Configuration = AppEnvironment.shared
    ) {
        self.apiClient = apiClient
        self.session = session
        self.environment = environment
    }

    init() {
        self.init(apiClient: .shared)
    }

    func fetchSummary() async throws -> [String: JSONValue] {
        try await apiClient.get(APIEndpoints.Analytics.summary)
    }

    func analyzeWardrobe(_ input: WardrobeAnalysisInput) async throws -> String {
        guard !environment.siliconFlowAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyticsServiceError.missingAPIKey
        }

        let body = AnalyticsChatRequest(
            model: environment.siliconFlowTextModel,
            messages: [
                AnalyticsMessage(
                    role: "system",
                    content: "你是一名专业衣橱顾问、形象顾问和穿搭整理师。请基于用户提供的完整衣橱数据，输出结构清晰、可执行、直截了当的中文深度分析报告。不要要求用户再提供额外信息。"
                ),
                AnalyticsMessage(role: "user", content: buildPrompt(from: input))
            ],
            maxTokens: 1400,
            temperature: 0.35
        )

        let endpoint = environment.siliconFlowAPIURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(environment.siliconFlowAPIKey)", forHTTPHeaderField: "Authorization")
        let requestData = try JSONEncoder().encode(body)
        request.httpBody = requestData

        let prompt = body.messages.last?.content ?? ""
        logger.info("Wardrobe analysis request start model=\(self.environment.siliconFlowTextModel, privacy: .public) items=\(input.items.count) timeout=\(Int(self.requestTimeout)) promptChars=\(prompt.count) bodyBytes=\(requestData.count)")
        logger.info("Wardrobe analysis prompt preview=\(self.promptPreview(prompt), privacy: .public)")

        let (responseData, response) = try await performRequestWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsServiceError.invalidResponse
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let serverMessage = parseServerMessage(from: responseData)
            logger.error("Wardrobe analysis server error status=\(httpResponse.statusCode) message=\(serverMessage ?? "nil", privacy: .public)")
            throw AnalyticsServiceError.server(statusCode: httpResponse.statusCode, message: serverMessage)
        }

        let payload = try JSONDecoder().decode(AnalyticsChatResponse.self, from: responseData)
        guard let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AnalyticsServiceError.emptyResult
        }

        return content
    }

    private func buildPrompt(from input: WardrobeAnalysisInput) -> String {
        let payload = compactWardrobeSummary(from: input)

        return """
        请根据以下完整衣橱数据，生成一份中文“AI 衣橱深度分析”报告。

        输出要求：
        1. 先给一个总评，概括当前衣橱风格、完整度和最值得优先处理的问题。
        2. 然后按下面 5 个章节输出，每个章节标题都必须包含“建议”二字，方便客户端分段展示：
        - 风格定位建议
        - 衣橱健康建议
        - 购买补强建议
        - 搭配提升建议
        - 闲置优化建议
        3. 每个章节写 2-4 条具体建议，直接结合数据里的品类、颜色、价格、穿着次数、品牌和 AI 分析字段来判断。
        4. 如果发现明显缺口、重复购买、低频闲置、高成本低利用率，请明确指出。
        5. 不要输出 JSON，不要使用 markdown 表格。
        6. 语言自然专业，结论明确，尽量具体到品类、颜色或使用场景。
        7. 如果数据里有“穿着次数很低但价格高”的单品，请优先指出。
        8. 如果颜色、品类或场景明显集中，也请明确指出利弊。

        完整衣橱数据如下：
        \(payload)
        """
    }

    private func compactWardrobeSummary(from input: WardrobeAnalysisInput) -> String {
        let activeItems = input.items.filter { !$0.archived }
        let categoryLines = summarizedCounts(from: activeItems.map(\.category))
        let colorLines = summarizedCounts(from: activeItems.map(\.color))
        let brandLines = summarizedCounts(from: activeItems.map(\.brand).filter { $0 != "未填写品牌" })

        let itemLines = activeItems.map { item in
            let style = item.aiAnalysis.style.joined(separator: "、")
            let seasons = item.aiAnalysis.seasons.joined(separator: "、")
            let occasions = item.aiAnalysis.occasions.joined(separator: "、")
            return """
            - \(item.name) | 品类:\(item.category) | 颜色:\(item.color) | 品牌:\(item.brand) | 价格:\(item.price) | 穿着:\(item.wearCount)次 | 风格:\(style.isEmpty ? "无" : style) | 季节:\(seasons.isEmpty ? "无" : seasons) | 场景:\(occasions.isEmpty ? "无" : occasions)
            """
        }.joined(separator: "\n")

        return """
        生成时间：\(formattedDate(input.generatedAt))
        衣橱：\(input.closetName)
        用户：\(input.profile.name)，身高\(input.profile.heightCm)cm，体重\(input.profile.weightKg)kg
        天气：\(input.weather.location) \(input.weather.temperature)°C，体感\(input.weather.feelsLike)°C，湿度\(input.weather.humidity)% ，\(input.weather.condition)
        总单品数：\(input.itemCount)

        品类分布：
        \(categoryLines)

        颜色分布：
        \(colorLines)

        品牌分布：
        \(brandLines.isEmpty ? "- 暂无明显品牌分布" : brandLines)

        单品明细：
        \(itemLines)
        """
    }

    private func summarizedCounts(from values: [String]) -> String {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            let message = error.localizedDescription
            logger.error("Wardrobe analysis transport error: \(message, privacy: .public)")

            guard let urlError = error as? URLError, urlError.code == .timedOut else {
                throw AnalyticsServiceError.transport(networkErrorDescription(from: error))
            }

            logger.info("Wardrobe analysis timed out, retrying once")
            do {
                return try await session.data(for: request)
            } catch {
                logger.error("Wardrobe analysis retry failed: \(error.localizedDescription, privacy: .public)")
                throw AnalyticsServiceError.transport(networkErrorDescription(from: error))
            }
        }
    }

    private func promptPreview(_ prompt: String) -> String {
        let collapsed = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(collapsed.prefix(600))
    }

    private func parseServerMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(AnalyticsChatErrorResponse.self, from: data) {
            return payload.error?.message ?? payload.message
        }
        return String(data: data, encoding: .utf8)
    }

    private func networkErrorDescription(from error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return "当前网络无法解析或连接硅基流动域名，请检查设备网络、DNS、代理或地区访问限制。"
        case .notConnectedToInternet:
            return "当前设备未连接互联网，请检查网络后重试。"
        case .timedOut:
            return "请求硅基流动超时，请稍后重试。"
        default:
            return urlError.localizedDescription
        }
    }
}

struct WardrobeAnalysisInput: Encodable {
    let generatedAt: Date
    let closetName: String
    let itemCount: Int
    let profile: WardrobeAnalysisProfile
    let weather: WardrobeAnalysisWeather
    let items: [WardrobeAnalysisItem]
}

struct WardrobeAnalysisProfile: Encodable {
    let name: String
    let heightCm: Int
    let weightKg: Int
}

struct WardrobeAnalysisWeather: Encodable {
    let location: String
    let temperature: Int
    let feelsLike: Int
    let humidity: Int
    let condition: String
}

struct WardrobeAnalysisItem: Encodable {
    let name: String
    let category: String
    let color: String
    let brand: String
    let price: Int
    let wearCount: Int
    let archived: Bool
    let createdAt: Date
    let aiAnalysis: WardrobeAnalysisItemAI
}

struct WardrobeAnalysisItemAI: Encodable {
    let style: [String]
    let seasons: [String]
    let materials: [String]
    let silhouette: String?
    let pattern: String?
    let occasions: [String]
    let formality: String?
    let warmth: String?

    init(analysis: ClothingAIAnalysis) {
        style = analysis.style
        seasons = analysis.seasons
        materials = analysis.materials
        silhouette = analysis.silhouette
        pattern = analysis.pattern
        occasions = analysis.occasions
        formality = analysis.formality
        warmth = analysis.warmth
    }
}

enum AnalyticsServiceError: LocalizedError {
    case missingAPIKey
    case transport(String)
    case invalidResponse
    case server(statusCode: Int, message: String?)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 SiliconFlow API Key，请先填写 SILICONFLOW_API_KEY。"
        case let .transport(message):
            return "请求硅基流动失败：\(message)"
        case .invalidResponse:
            return "硅基流动返回了无法识别的响应。"
        case let .server(statusCode, message):
            return "硅基流动分析失败（\(statusCode)）：\(message ?? "请稍后重试")"
        case .emptyResult:
            return "分析结果为空，请稍后重试。"
        }
    }
}

private struct AnalyticsChatRequest: Encodable {
    let model: String
    let messages: [AnalyticsMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct AnalyticsMessage: Encodable {
    let role: String
    let content: String
}

private struct AnalyticsChatResponse: Decodable {
    let choices: [AnalyticsChatChoice]
}

private struct AnalyticsChatChoice: Decodable {
    let message: AnalyticsChatResponseMessage
}

private struct AnalyticsChatResponseMessage: Decodable {
    let content: String?
}

private struct AnalyticsChatErrorResponse: Decodable {
    let message: String?
    let error: AnalyticsChatErrorDetail?
}

private struct AnalyticsChatErrorDetail: Decodable {
    let message: String?
}
