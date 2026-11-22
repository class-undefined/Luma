import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumaCore

final class ImageLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func image(_ name: String, orientation: Int = 1, properties: [String: Any] = [:]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        var properties = properties
        properties[kCGImagePropertyOrientation as String] = orientation
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testFolderFiltersCorruptionHiddenFilesAndSubfolders() throws {
        _ = try image("image10.tiff")
        _ = try image("image2.tiff")
        _ = try image(".hidden.tiff")
        try Data("broken".utf8).write(to: directory.appendingPathComponent("broken.jpg"))
        try Data("text".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let scan = try ImageLibrary.scan(urls: [directory, directory.appendingPathComponent("image2.tiff")])
        XCTAssertEqual(scan.photos.map(\.name), ["image2.tiff", "image10.tiff"])
        XCTAssertEqual(scan.skipped, 1)
        XCTAssertEqual(scan.photos[0].metadata.pixelWidth, 40)
        XCTAssertGreaterThan(scan.photos[0].metadata.byteCount, 0)
    }

    func testOrientationAffectsReportedDimensions() throws {
        let url = try image("portrait.tiff", orientation: 6)
        let metadata = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(metadata.pixelWidth, 20)
        XCTAssertEqual(metadata.pixelHeight, 40)
    }

    func testMissingDirectoryReportsAnError() {
        XCTAssertThrowsError(try ImageLibrary.scan(urls: [directory.appendingPathComponent("missing")]))
    }

    func testCameraMetadataAndCaptureTimeAreReadFromEXIF() throws {
        let properties: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "FUJIFILM",
                kCGImagePropertyTIFFModel as String: "FUJIFILM X-T5"
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "XF 23mm F2 R WR",
                kCGImagePropertyExifDateTimeOriginal as String: "2025:01:02 03:04:05",
                kCGImagePropertyExifOffsetTimeOriginal as String: "+08:00",
                kCGImagePropertyExifExposureTime as String: 1.0 / 125,
                kCGImagePropertyExifFNumber as String: 2.0,
                kCGImagePropertyExifISOSpeedRatings as String: [640],
                kCGImagePropertyExifFocalLength as String: 23.0,
                kCGImagePropertyExifExposureBiasValue as String: -0.3
            ]
        ]
        let url = try image("exif.tiff", properties: properties)
        let metadata = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(metadata.camera, "FUJIFILM X-T5")
        XCTAssertEqual(metadata.lens, "XF 23mm F2 R WR")
        XCTAssertEqual(metadata.exposureDescription, "1/125 s")
        XCTAssertEqual(metadata.iso, 640)
        XCTAssertEqual(metadata.bitDepth, 8)
        XCTAssertEqual(metadata.capturedAt, ISO8601DateFormatter().date(from: "2025-01-02T03:04:05+08:00"))
    }
}
