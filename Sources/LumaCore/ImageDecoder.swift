import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum ImageDecoder {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    public static let rawExtensions: Set<String> = [
        "dng", "nef", "nrw", "cr2", "cr3", "crw", "arw", "srf", "sr2", "raf", "rw2", "rwl",
        "orf", "ori", "pef", "ptx", "srw", "3fr", "fff", "iiq", "mos", "mrw", "erf", "kdc",
        "dcr", "mef", "x3f", "raw", "bay", "cap"
    ]

    public static func isRAW(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased()) ||
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true
    }

    /// RAW originals are demosaiced by Core Image; thumbnails prefer embedded camera previews.
    /// ImageIO remains a fallback for cameras with a readable preview but no system RAW decoder.
    public static func decode(_ url: URL, maxPixels: Int, original: Bool = false) -> CGImage? {
        guard maxPixels > 0 else { return nil }
        return autoreleasepool {
            let raw = isRAW(url)
            if raw && original, let image = renderRAW(url, maxPixels: maxPixels) { return image }
            if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: !raw,
                   kCGImageSourceCreateThumbnailFromImageIfAbsent: raw,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                   kCGImageSourceShouldCacheImmediately: true
               ] as CFDictionary) { return image }
            return raw ? renderRAW(url, maxPixels: maxPixels) : nil
        }
    }

    private static func renderRAW(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url), filter.nativeSize.width > 0, filter.nativeSize.height > 0 else { return nil }
        filter.scaleFactor = Float(min(1, CGFloat(maxPixels) / max(filter.nativeSize.width, filter.nativeSize.height)))
        filter.isDraftModeEnabled = maxPixels <= 1024
        guard let image = filter.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else { return nil }
        return context.createCGImage(image, from: image.extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}
