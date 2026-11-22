import Foundation
import UniformTypeIdentifiers

public enum ImageLibrary {
    public struct Scan: Sendable {
        public let photos: [Photo]
        public let skipped: Int
    }

    public static func supports(_ url: URL) -> Bool {
        if ImageDecoder.isRAW(url) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Opens the immediate images in a folder. Hidden files and nested folders are excluded.
    public static func scan(urls: [URL]) throws -> Scan {
        var candidates: [URL] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let children = try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                candidates += children.filter { supports($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            } else if supports(url) {
                candidates.append(url)
            }
        }
        var seen = Set<String>()
        var photos: [Photo] = []
        var skipped = 0
        for url in candidates where seen.insert(url.standardizedFileURL.path).inserted {
            if let metadata = ImageMetadata.read(from: url) {
                photos.append(Photo(url: url, metadata: metadata))
            } else {
                skipped += 1
            }
        }
        return Scan(photos: PhotoSort.name.sorted(photos), skipped: skipped)
    }
}
