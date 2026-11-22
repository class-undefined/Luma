import AppKit
import ImageIO
import LumaCore

@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: Task<CGImage?, Never>] = [:]

    private init() { cache.totalCostLimit = 256 * 1024 * 1024 }

    func image(for photo: Photo, maxPixels: Int) async -> NSImage? {
        let key = "\(photo.id)-\(photo.metadata.modifiedAt?.timeIntervalSince1970 ?? 0)-\(maxPixels)"
        if let image = cache.object(forKey: key as NSString) { return image }
        let task: Task<CGImage?, Never>
        if let existing = pending[key] { task = existing } else {
            let url = photo.url
            task = Task.detached(priority: maxPixels > 1024 ? .userInitiated : .utility) {
                autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary)
                }
            }
            pending[key] = task
        }
        let cgImage = await task.value
        pending[key] = nil
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
