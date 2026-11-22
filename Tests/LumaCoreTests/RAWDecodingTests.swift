import XCTest
import CoreImage
@testable import LumaCore

final class RAWDecodingTests: XCTestCase {
    private var fixture: URL { Bundle.module.url(forResource: "synthetic", withExtension: "dng", subdirectory: "Fixtures")! }

    func testGenuineBayerDNGHasRAWMetadataAndDecodes() throws {
        let raw = try XCTUnwrap(CIRAWFilter(imageURL: fixture))
        XCTAssertEqual(raw.nativeSize.width, 512)
        let scan = try ImageLibrary.scan(urls: [fixture])
        let metadata = try XCTUnwrap(scan.photos.first?.metadata)
        XCTAssertTrue(metadata.isRAW)
        XCTAssertEqual(metadata.format, "DNG")
        XCTAssertEqual(metadata.pixelWidth, 512)
        XCTAssertEqual(metadata.pixelHeight, 512)
        let original = try XCTUnwrap(ImageDecoder.decode(fixture, maxPixels: 512, original: true))
        XCTAssertEqual(original.width, 512)
        XCTAssertEqual(original.height, 512)
        let thumbnail = try XCTUnwrap(ImageDecoder.decode(fixture, maxPixels: 128))
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 128)
    }

    func testCameraRAWExtensionsReachTheDecoder() {
        for ext in ["ARW", "nef", "CR2", "cr3", "RAF", "rw2", "orf", "dng", "nrw"] {
            XCTAssertTrue(ImageLibrary.supports(URL(fileURLWithPath: "sample.\(ext)")))
        }
        XCTAssertFalse(ImageLibrary.supports(URL(fileURLWithPath: "sample.txt")))
    }

    func testCorruptedRAWIsSkippedWithoutCrashing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).arw")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a RAW file".utf8).write(to: url)
        XCTAssertNil(ImageDecoder.decode(url, maxPixels: 128, original: true))
        let scan = try ImageLibrary.scan(urls: [url])
        XCTAssertTrue(scan.photos.isEmpty)
        XCTAssertEqual(scan.skipped, 1)
    }
}
