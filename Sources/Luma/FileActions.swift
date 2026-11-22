import AppKit
import LumaCore

extension WindowController {
    var canModifyPhoto: Bool {
        guard let url = state.selectedPhoto?.url else { return false }
        return writableDirectory(url.deletingLastPathComponent())
    }
    private func writableDirectory(_ directory: URL) -> Bool {
        let path = directory.standardizedFileURL.path
        guard !path.hasPrefix(Bundle.module.bundleURL.path), !path.hasPrefix(Bundle.main.bundleURL.path + "/") else { return false }
        return FileManager.default.isWritableFile(atPath: path)
    }
    var pasteDestination: URL? {
        state.currentDirectory.flatMap { writableDirectory($0) ? $0 : nil }
    }
    var copiedFileURLs: [URL] {
        (clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { ImageLibrary.supports($0) }
    }
    @objc func copyFileName(_ sender: Any?) {
        guard let photo = state.selectedPhoto else { return }
        clipboard.clearContents()
        clipboard.setString(photo.url.lastPathComponent, forType: .string)
    }
    @objc func copyFilePath(_ sender: Any?) {
        guard let photo = state.selectedPhoto else { return }
        clipboard.clearContents()
        clipboard.setString(photo.url.path, forType: .string)
    }
    @objc func copyFile(_ sender: Any?) {
        guard let photo = state.selectedPhoto else { return }
        clipboard.clearContents()
        clipboard.writeObjects([photo.url as NSURL])
    }
    @objc func openContainingFolder(_ sender: Any?) {
        if let url = state.selectedPhoto?.url { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
    }
    @objc func pasteFiles(_ sender: Any?) {
        guard let destination = pasteDestination, !copiedFileURLs.isEmpty else { return }
        do {
            var copied: URL?
            for source in copiedFileURLs { copied = try PhotoFileOperations.copy(source, into: destination) }
            state.refresh(selecting: copied)
        } catch { showError(error.localizedDescription) }
    }
    @objc func duplicateFile(_ sender: Any?) {
        guard canModifyPhoto, let source = state.selectedPhoto?.url else { return }
        do {
            let copied = try PhotoFileOperations.copy(source, into: source.deletingLastPathComponent(), duplicate: true)
            state.refresh(selecting: copied)
        } catch { showError(error.localizedDescription) }
    }
    @objc func renameFile(_ sender: Any?) {
        guard canModifyPhoto, let source = state.selectedPhoto?.url, let window else { return }
        let alert = NSAlert()
        alert.messageText = "重命名照片"
        alert.informativeText = "输入新的文件名。"
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(string: source.lastPathComponent)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 26)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                let renamed = try PhotoFileOperations.rename(source, to: input.stringValue)
                self.state.renamedFile(from: source, to: renamed)
            } catch { self.showError(error.localizedDescription) }
        }
    }
    @objc func moveToTrash(_ sender: Any?) {
        guard canModifyPhoto, let source = state.selectedPhoto?.url else { return }
        do {
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
            state.removedFile(source)
        } catch { showError(error.localizedDescription) }
    }
}
