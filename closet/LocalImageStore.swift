//
//  LocalImageStore.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import Foundation
import UIKit

final class LocalImageStore {
    static let shared = LocalImageStore()

    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, UIImage>()
    private let folderName = "ClosetImages"
    private let maxPixelSize: CGFloat = 2_048
    private let maxBytes = 900_000

    private init() {
        imageCache.countLimit = 160
    }

    func saveImageData(_ data: Data, prefix: String) -> String? {
        do {
            try createDirectoryIfNeeded()
            let normalizedData = normalizedImageData(from: data) ?? NormalizedImageData(data: data, fileExtension: "jpg")
            let fileName = "\(prefix)-\(UUID().uuidString).\(normalizedData.fileExtension)"
            let url = imagesDirectory().appendingPathComponent(fileName)
            try normalizedData.data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    func loadImage(named fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        let cacheKey = fileName as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        let url = imagesDirectory().appendingPathComponent(fileName)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    func loadImageData(named fileName: String?) -> Data? {
        guard let fileName else { return nil }
        let url = imagesDirectory().appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    func removeImage(named fileName: String?) {
        guard let fileName else { return }
        imageCache.removeObject(forKey: fileName as NSString)
        let url = imagesDirectory().appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    func restoreImageData(_ data: Data, named fileName: String) {
        do {
            try createDirectoryIfNeeded()
            let url = imagesDirectory().appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            imageCache.removeObject(forKey: fileName as NSString)
        } catch {
        }
    }

    func storedImageFileNames() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: imagesDirectory().path)) ?? []
    }

    func removeAllImages(except fileNames: Set<String>) -> Int {
        let stored = storedImageFileNames()
        var removedCount = 0
        for fileName in stored where !fileNames.contains(fileName) {
            removeImage(named: fileName)
            removedCount += 1
        }
        return removedCount
    }

    func saveBundledImageIfNeeded(named resourceName: String, prefix: String, existingFileName: String?) -> String? {
        if let existingFileName, loadImage(named: existingFileName) != nil {
            return existingFileName
        }

        guard let bundledData = bundledImageData(named: resourceName) else {
            return existingFileName
        }

        return saveImageData(bundledData, prefix: prefix) ?? existingFileName
    }

    private func imagesDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private func createDirectoryIfNeeded() throws {
        let url = imagesDirectory()
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func bundledImageData(named resourceName: String) -> Data? {
        let candidates = [
            Bundle.main.url(forResource: resourceName, withExtension: "png", subdirectory: "SeedImages"),
            Bundle.main.url(forResource: resourceName, withExtension: "jpg", subdirectory: "SeedImages"),
            Bundle.main.url(forResource: resourceName, withExtension: "jpeg", subdirectory: "SeedImages")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }

    private func normalizedImageData(from data: Data) -> NormalizedImageData? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resizedImageIfNeeded(image)

        if resized.hasAlphaChannel, let pngData = resized.pngData() {
            return NormalizedImageData(data: pngData, fileExtension: "png")
        }

        var compressionQuality: CGFloat = 0.82
        var bestData = resized.jpegData(compressionQuality: compressionQuality)

        while let currentData = bestData, currentData.count > maxBytes, compressionQuality > 0.45 {
            compressionQuality -= 0.1
            bestData = resized.jpegData(compressionQuality: compressionQuality)
        }

        guard let bestData else { return nil }
        return NormalizedImageData(data: bestData, fileExtension: "jpg")
    }

    private func resizedImageIfNeeded(_ image: UIImage) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxPixelSize else { return image }

        let scaleRatio = maxPixelSize / longestSide
        let targetSize = CGSize(
            width: image.size.width * scaleRatio,
            height: image.size.height * scaleRatio
        )

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct NormalizedImageData {
    let data: Data
    let fileExtension: String
}

private extension UIImage {
    var hasAlphaChannel: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}
