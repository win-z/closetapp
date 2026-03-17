//
//  AnalyticsViewModel.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Combine
import Foundation

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published private(set) var summary: [String: JSONValue] = [:]
    @Published private(set) var aiAnalysisText: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var lastUpdatedAt: Date?

    private let service: AnalyticsServicing
    private let cache = AnalyticsCacheStore()

    init(service: AnalyticsServicing) {
        self.service = service
        let snapshot = cache.load()
        self.summary = snapshot.summary
        self.aiAnalysisText = snapshot.aiAnalysisText
        self.lastUpdatedAt = snapshot.lastUpdatedAt
    }

    convenience init() {
        self.init(service: AnalyticsService())
    }

    func loadSummary() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let summary = try await service.fetchSummary()
            self.summary = summary
            self.lastUpdatedAt = .now
            cache.save(summary: summary, aiAnalysisText: aiAnalysisText, lastUpdatedAt: lastUpdatedAt)
            errorMessage = nil
        } catch {
            errorMessage = summary.isEmpty ? error.localizedDescription : "分析接口暂时不可用，当前显示最近一次同步结果。"
        }
    }

    func runAIAnalysis(_ input: WardrobeAnalysisInput) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let response = try await service.analyzeWardrobe(input)
            aiAnalysisText = response
            lastUpdatedAt = .now
            cache.save(summary: summary, aiAnalysisText: aiAnalysisText, lastUpdatedAt: lastUpdatedAt)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AnalyticsCacheSnapshot: Codable {
    var summary: [String: JSONValue]
    var aiAnalysisText: String?
    var lastUpdatedAt: Date?
}

private struct AnalyticsCacheStore {
    private let storageKey = "lumina.analytics.cache.v1"

    func load() -> AnalyticsCacheSnapshot {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(AnalyticsCacheSnapshot.self, from: data) else {
            return AnalyticsCacheSnapshot(summary: [:], aiAnalysisText: nil, lastUpdatedAt: nil)
        }
        return snapshot
    }

    func save(summary: [String: JSONValue], aiAnalysisText: String?, lastUpdatedAt: Date?) {
        let snapshot = AnalyticsCacheSnapshot(summary: summary, aiAnalysisText: aiAnalysisText, lastUpdatedAt: lastUpdatedAt)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
