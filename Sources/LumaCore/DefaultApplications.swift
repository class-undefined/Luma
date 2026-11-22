import AppKit
import UniformTypeIdentifiers

public struct ImageAssociation: Identifiable, Equatable, Sendable {
    public let type: UTType
    public let title: String
    public let isRAW: Bool
    public var id: String { type.identifier }
    public init(type: UTType, title: String, isRAW: Bool = false) { self.type = type; self.title = title; self.isRAW = isRAW }
    public static var supported: [Self] {
        var values: [Self] = [Self(type: .image, title: "通用图片"), Self(type: .rawImage, title: "RAW（通用）", isRAW: true)]
        for ext in ["jpg", "png", "heic", "heif", "webp", "tiff", "gif", "bmp", "avif", "jp2"] {
            if let type = UTType(filenameExtension: ext), !type.isDynamic {
                values.append(Self(type: type, title: ext == "jpg" ? "JPEG（.jpg / .jpeg）" : ext.uppercased()))
            }
        }
        for ext in ImageDecoder.rawExtensions.sorted() {
            if let type = UTType(filenameExtension: ext), !type.isDynamic { values.append(Self(type: type, title: ext.uppercased(), isRAW: true)) }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
public protocol DefaultApplicationAccess: AnyObject {
    var applicationURL: URL { get }
    func defaultApplication(for type: UTType) -> URL?
    func setDefaultApplication(for type: UTType) async throws
}

@MainActor
public final class SystemDefaultApplicationAccess: DefaultApplicationAccess {
    public let applicationURL: URL
    public init(applicationURL: URL) { self.applicationURL = applicationURL }
    public func defaultApplication(for type: UTType) -> URL? { NSWorkspace.shared.urlForApplication(toOpen: type) }
    public func setDefaultApplication(for type: UTType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpen: type) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}

public struct AssociationResult: Equatable, Sendable {
    public var changed: [String] = []
    public var unchanged: [String] = []
    public var failures: [String: String] = [:]
    public var message: String {
        let count = changed.count + unchanged.count
        if failures.isEmpty { return "\(count) 种文件类型已使用 Luma 打开。" }
        return "\(count) 种已设置，\(failures.count) 种未更改。可重新选择未完成的类型后重试。"
    }
}

@MainActor
public final class DefaultApplicationSettings {
    public let access: any DefaultApplicationAccess
    public let formats: [ImageAssociation]
    public private(set) var handlers: [String: URL] = [:]
    public private(set) var isApplying = false
    public private(set) var progress = ""
    public private(set) var result: AssociationResult?
    public var onChange: (() -> Void)?
    public var canConfigure: Bool { access.applicationURL.pathExtension.lowercased() == "app" }

    public init(access: any DefaultApplicationAccess, formats: [ImageAssociation] = ImageAssociation.supported) {
        self.access = access; self.formats = formats
        refresh()
    }
    public func refresh() {
        handlers = Dictionary(uniqueKeysWithValues: formats.compactMap { format in access.defaultApplication(for: format.type).map { (format.id, $0) } })
        onChange?()
    }
    public func isDefault(for format: ImageAssociation) -> Bool {
        handlers[format.id]?.standardizedFileURL == access.applicationURL.standardizedFileURL
    }
    @discardableResult
    public func apply(to formats: [ImageAssociation]) async -> AssociationResult {
        guard !isApplying else { return result ?? AssociationResult() }
        isApplying = true
        result = nil
        var summary = AssociationResult()
        defer { isApplying = false; progress = ""; result = summary; onChange?() }
        var seen = Set<String>()
        let selected = formats.filter { seen.insert($0.id).inserted }
        for (index, format) in selected.enumerated() {
            progress = "正在设置 \(format.title)（\(index + 1)/\(selected.count)）…"
            onChange?()
            if access.defaultApplication(for: format.type)?.standardizedFileURL == access.applicationURL.standardizedFileURL {
                handlers[format.id] = access.applicationURL
                summary.unchanged.append(format.id)
                continue
            }
            do {
                try await access.setDefaultApplication(for: format.type)
                var actual: URL?
                for attempt in 0..<4 {
                    actual = access.defaultApplication(for: format.type)
                    if actual?.standardizedFileURL == access.applicationURL.standardizedFileURL { break }
                    if attempt < 3 { try await Task.sleep(nanoseconds: 100_000_000) }
                }
                handlers[format.id] = actual
                if actual?.standardizedFileURL == access.applicationURL.standardizedFileURL { summary.changed.append(format.id) }
                else { summary.failures[format.id] = "系统未更改默认应用。" }
            } catch { summary.failures[format.id] = error.localizedDescription }
        }
        return summary
    }
}
