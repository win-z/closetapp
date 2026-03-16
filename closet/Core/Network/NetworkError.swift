//
//  NetworkError.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case decodingFailed
    case emptyResponse
    case transportError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效。"
        case .invalidResponse:
            return "服务器响应无效。"
        case .unauthorized:
            return "登录状态已失效，请重新登录。"
        case let .serverError(statusCode, message):
            return message ?? "请求失败（\(statusCode)）。"
        case .decodingFailed:
            return "数据解析失败。"
        case .emptyResponse:
            return "服务器未返回数据。"
        case let .transportError(message):
            return "网络连接失败：\(message)"
        }
    }
}
