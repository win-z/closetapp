//
//  LocalClosetBackup.swift
//  closet
//
//  Created by Codex on 2026/3/12.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LocalClosetBackupPayload: Codable {
    var snapshot: ClosetSnapshot
    var images: [String: Data]
    var exportedAt: Date
}

struct LocalClosetBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var payload: LocalClosetBackupPayload

    init(payload: LocalClosetBackupPayload) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        payload = try decoder.decode(LocalClosetBackupPayload.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return .init(regularFileWithContents: try encoder.encode(payload))
    }
}
