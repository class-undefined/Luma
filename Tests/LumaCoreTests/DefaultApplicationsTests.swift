import XCTest
import UniformTypeIdentifiers
@testable import LumaCore

@MainActor
private final class FakeApplicationAccess: DefaultApplicationAccess {
    let applicationURL = URL(fileURLWithPath: "/Applications/Luma.app")
    var handlers: [String: URL] = [:]
    var requests: [String] = []
    var rejected: Set<String> = []
    var ignored: Set<String> = []
    func defaultApplication(for type: UTType) -> URL? { handlers[type.identifier] }
    func setDefaultApplication(for type: UTType) async throws {
        requests.append(type.identifier)
        if rejected.contains(type.identifier) { throw CocoaError(.userCancelled) }
        if !ignored.contains(type.identifier) { handlers[type.identifier] = applicationURL }
    }
}

final class DefaultApplicationsTests: XCTestCase {
    @MainActor func testOnlySelectedTypesAreChangedAndExistingChoicesAreSkipped() async {
        let access = FakeApplicationAccess()
        access.handlers[UTType.jpeg.identifier] = access.applicationURL
        let service = DefaultApplicationSettings(access: access)
        let jpeg = ImageAssociation(type: .jpeg, title: "JPEG")
        let png = ImageAssociation(type: .png, title: "PNG")
        let result = await service.apply(to: [jpeg, png, png])
        XCTAssertEqual(access.requests, [UTType.png.identifier])
        XCTAssertEqual(result.changed, [UTType.png.identifier])
        XCTAssertEqual(result.unchanged, [UTType.jpeg.identifier])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(service.isDefault(for: png))
        XCTAssertFalse(service.isApplying)
    }
    @MainActor func testCancellationAndUnchangedSystemStateAreReportedAsFailures() async {
        let access = FakeApplicationAccess()
        access.rejected.insert(UTType.jpeg.identifier)
        access.ignored.insert(UTType.png.identifier)
        let service = DefaultApplicationSettings(access: access)
        let result = await service.apply(to: [.init(type: .jpeg, title: "JPEG"), .init(type: .png, title: "PNG")])
        XCTAssertTrue(result.changed.isEmpty)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertFalse(service.isDefault(for: .init(type: .png, title: "PNG")))
    }
    func testFormatListIsUniqueAndIncludesConcreteImageAndRAWTypes() {
        let types = ImageAssociation.supported
        XCTAssertEqual(Set(types.map(\.id)).count, types.count)
        XCTAssertTrue(types.contains { $0.type == .jpeg })
        XCTAssertTrue(types.contains { $0.type == .rawImage })
        XCTAssertTrue(types.contains { $0.isRAW && $0.type.preferredFilenameExtension == "dng" })
    }
}
