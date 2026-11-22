import Foundation

public enum PhotoFileOperations {
    public static func copy(_ source: URL, into directory: URL, duplicate: Bool = false) throws -> URL {
        let destination = availableDestination(source, in: directory, duplicate: duplicate)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    public static func rename(_ source: URL, to name: String) throws -> URL {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.contains("/"), !name.contains(":"), name != ".", name != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if source.standardizedFileURL == destination.standardizedFileURL { return source }
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    private static func availableDestination(_ source: URL, in directory: URL, duplicate: Bool) -> URL {
        let original = directory.appendingPathComponent(source.lastPathComponent)
        if !duplicate && !FileManager.default.fileExists(atPath: original.path) { return original }
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
        var number = 1
        while true {
            let suffix = number == 1 ? " 副本" : " 副本 \(number)"
            let candidate = directory.appendingPathComponent(stem + suffix + ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
