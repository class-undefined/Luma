import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct Photo: Identifiable, Hashable, Sendable {
    public var id: String { url.standardizedFileURL.path }
    public let url: URL
    public let name: String
    public let metadata: ImageMetadata

    public init(url: URL, name: String? = nil, metadata: ImageMetadata) {
        self.url = url.standardizedFileURL
        self.name = name ?? url.lastPathComponent
        self.metadata = metadata
    }
}

public struct ImageMetadata: Hashable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int64
    public let format: String
    public let colorProfile: String
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let camera: String?
    public let lens: String?
    public let focalLength: Double?
    public let aperture: Double?
    public let exposure: Double?
    public let iso: Int?

    public var dimensions: String { "\(pixelWidth) × \(pixelHeight) 像素" }
    public var fileSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    public var aspectRatio: Double { Double(pixelWidth) / Double(max(1, pixelHeight)) }

    public static func read(from url: URL) -> Self? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0 else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let identifier = CGImageSourceGetType(source) as String?
        let format = identifier.flatMap(UTType.init)?.preferredFilenameExtension?.uppercased() ?? url.pathExtension.uppercased()
        let make = tiff[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff[kCGImagePropertyTIFFModel as String] as? String
        let camera = [make, model].compactMap { $0 }.joined(separator: " ")
        return Self(pixelWidth: rotated ? height : width, pixelHeight: rotated ? width : height,
                    byteCount: Int64(values?.fileSize ?? 0), format: format == "JPG" ? "JPEG" : format,
                    colorProfile: properties[kCGImagePropertyProfileName as String] as? String ?? "未指定",
                    createdAt: values?.creationDate, modifiedAt: values?.contentModificationDate,
                    camera: camera.isEmpty ? nil : camera,
                    lens: exif[kCGImagePropertyExifLensModel as String] as? String,
                    focalLength: (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue,
                    aperture: (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue,
                    exposure: (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue,
                    iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first)
    }
}

public enum PhotoSort: String, CaseIterable, Sendable {
    case name, newest, oldest, size, rating
    public var title: String {
        switch self {
        case .name: return "名称"
        case .newest: return "修改时间（最新优先）"
        case .oldest: return "修改时间（最早优先）"
        case .size: return "文件大小"
        case .rating: return "评分（高分优先）"
        }
    }

    public func sorted(_ photos: [Photo], ratings: [String: Int] = [:]) -> [Photo] {
        photos.sorted { a, b in
            switch self {
            case .name: break
            case .newest, .oldest:
                let left = a.metadata.modifiedAt ?? .distantPast
                let right = b.metadata.modifiedAt ?? .distantPast
                if left != right { return self == .newest ? left > right : left < right }
            case .size:
                if a.metadata.byteCount != b.metadata.byteCount { return a.metadata.byteCount > b.metadata.byteCount }
            case .rating:
                let left = ratings[a.id] ?? 0, right = ratings[b.id] ?? 0
                if left != right { return left > right }
            }
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
        }
    }
}
