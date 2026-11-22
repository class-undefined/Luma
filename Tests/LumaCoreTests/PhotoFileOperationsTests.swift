import XCTest
@testable import LumaCore

final class PhotoFileOperationsTests: XCTestCase {
    private var directory: URL!
    private var source: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("海岸.ARW")
        try Data([1, 2, 3, 4]).write(to: source)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testDuplicatePreservesOriginalAndChoosesUnusedNames() throws {
        let first = try PhotoFileOperations.copy(source, into: directory, duplicate: true)
        let second = try PhotoFileOperations.copy(source, into: directory, duplicate: true)
        XCTAssertEqual(first.lastPathComponent, "海岸 副本.ARW")
        XCTAssertEqual(second.lastPathComponent, "海岸 副本 2.ARW")
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: source))
        XCTAssertEqual(try Data(contentsOf: source), Data([1, 2, 3, 4]))
    }
    func testCopyAndRenameNeverOverwriteExistingFiles() throws {
        let renamed = try PhotoFileOperations.rename(source, to: "旅途.ARW")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let duplicate = try PhotoFileOperations.copy(renamed, into: directory)
        XCTAssertThrowsError(try PhotoFileOperations.rename(renamed, to: duplicate.lastPathComponent))
        XCTAssertThrowsError(try PhotoFileOperations.rename(renamed, to: "../outside.ARW"))
        XCTAssertThrowsError(try PhotoFileOperations.rename(renamed, to: ""))
        XCTAssertEqual(try Data(contentsOf: renamed), Data([1, 2, 3, 4]))
    }
}
