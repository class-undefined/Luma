#if DEBUG
import AppKit
import LumaCore

/// Runs against real AppKit views, with an isolated preferences domain.
/// Launch the debug executable with --ui-test to write evidence under build/validation.
@MainActor
enum UIValidation {
    struct Failure: Error { let message: String }
    static func run(_ controller: WindowController, domain: String) {
        Task {
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/validation")
            var passed: [String] = []
            var skipped: [String] = []
            @MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
                guard condition() else { throw Failure(message: message) }
                passed.append(message)
            }
            @MainActor func settle(_ milliseconds: UInt64 = 160) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
            @MainActor func loaded() async throws {
                for _ in 0..<100 {
                    if !controller.state.isLoading { return }
                    await settle(50)
                }
                throw Failure(message: "Image loading timed out")
            }
            @MainActor func snapshot(_ name: String) async throws {
                controller.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                await settle(500)
                guard let window = controller.window else { return }
                let destination = output.appendingPathComponent("\(name).png")
                let appkitDestination = output.appendingPathComponent("\(name).appkit.png")
                for file in [destination, appkitDestination] where FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                for _ in 0..<(hasActiveDisplay ? 3 : 0) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", destination.path]
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 { return }
                    await settle(250)
                }
                guard let view = window.contentView?.superview,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "Window capture failed") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "Window capture failed") }
                try png.write(to: appkitDestination)
                print("Snapshot \(name) used AppKit view rendering; WindowServer capture unavailable.")
            }
            @MainActor func key(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window!.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code)!
                NSApp.postEvent(event, atStart: false)
            }
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try await snapshot("00-empty")
                controller.state.showDemo()
                try await loaded()
                await settle(400)
                try check(controller.state.visiblePhotos.count == 12, "Demo library loads 12 real images")
                try check(controller.state.selectedPhoto?.name == "DSCF_2408.jpg", "Initial selection survives collection reload")
                let landscape = (controller.gallery.collection.item(at: IndexPath(item: 0, section: 0)) as? ThumbnailItem)?.thumbnail
                let portrait = (controller.gallery.collection.item(at: IndexPath(item: 6, section: 0)) as? ThumbnailItem)?.thumbnail
                try check(landscape != nil && portrait != nil && landscape?.preview.frame.size == portrait?.preview.frame.size,
                          "Landscape and portrait thumbnails use identical card frames")
                let selected = controller.state.selectedID
                for size in ThumbnailSize.allCases {
                    controller.state.setSize(size)
                    await settle()
                    try check(controller.state.selectedID == selected, "Selection survives \(size.width) pt layout")
                    try check(controller.status.slider.integerValue == size.rawValue && controller.status.sizeMenu.indexOfSelectedItem == size.rawValue, "All size controls agree at \(size.width) pt")
                    try await snapshot("01-grid-\(Int(size.width))")
                }
                controller.state.stepSize(1)
                try check(controller.state.thumbnailSize == .huge, "Maximum thumbnail size clamps")
                controller.state.setSize(.tiny)
                controller.state.stepSize(-1)
                try check(controller.state.thumbnailSize == .tiny, "Minimum thumbnail size clamps")
                controller.state.setSize(.large)
                await settle()
                let scroll = controller.gallery.gridScroll
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
                scroll.reflectScrolledClipView(scroll.contentView)
                controller.state.select(controller.state.visiblePhotos[5].id)
                let anchor = controller.gallery.captureAnchor()
                controller.state.setSize(.huge)
                await settle()
                let restored = controller.gallery.captureAnchor()
                try check(anchor?.id == restored?.id && abs((anchor?.offset ?? 0) - (restored?.offset ?? 0)) < 2,
                          "Resize preserves selected visual anchor and scroll offset")
                controller.state.setSize(.medium)
                controller.status.slider.integerValue = 1
                _ = controller.status.slider.sendAction(controller.status.slider.action, to: controller.status.slider.target)
                try check(controller.state.thumbnailSize == .small, "Native slider action changes the size preference")
                controller.status.sizeMenu.selectItem(at: 2)
                _ = controller.status.sizeMenu.sendAction(controller.status.sizeMenu.action, to: controller.status.sizeMenu.target)
                try check(controller.state.thumbnailSize == .medium, "Native size menu action changes the shared preference")
                controller.status.larger.performClick(nil)
                try check(controller.state.thumbnailSize == .large, "Size step button advances exactly one level")
                let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)!
                wheel.flags = .maskControl
                controller.gallery.gridScroll.scrollWheel(with: NSEvent(cgEvent: wheel)!)
                try check(controller.state.thumbnailSize == .medium, "Control wheel event reaches native gallery size handling")
                wheel.flags = .maskCommand
                controller.gallery.gridScroll.scrollWheel(with: NSEvent(cgEvent: wheel)!)
                try check(controller.state.thumbnailSize == .small, "Command wheel changes native gallery size")
                controller.state.setSize(.medium)
                controller.state.setListMode(true)
                await settle()
                try check(!controller.gallery.listScroll.isHidden, "Native list view opens")
                try await snapshot("02-list")
                controller.window?.makeFirstResponder(controller.gallery.table)
                key(49, characters: " ")
                await settle()
                try check(controller.state.mode == .viewer, "Space opens the selected image from the native list")
                key(53, characters: "\u{1B}")
                await settle()
                try check(controller.state.mode == .browser && controller.state.listMode, "Escape restores the native list mode")
                controller.state.setListMode(false)
                controller.state.setQuery("2408")
                try check(controller.state.visiblePhotos.count == 1, "Filename search filters the library")
                controller.state.setQuery("no-such-image")
                try check(controller.state.visiblePhotos.isEmpty && !controller.gallery.empty.isHidden, "Search empty state is visible")
                controller.state.setQuery("")
                controller.state.select(selected)
                controller.state.toggleFavorite()
                try check(controller.state.isFavorite, "Favorite is stored for the selected file")
                let persisted = AppState(defaults: controller.state.defaults)
                try check(persisted.thumbnailSize == .medium && persisted.favoritePaths.contains(selected!), "Thumbnail preference and favorite survive state reconstruction")
                controller.openSelected(nil)
                await settle(700)
                try check(controller.state.mode == .viewer && controller.viewer.canvas.image != nil, "Viewer decodes the selected original")
                controller.viewer.inspector.layoutSubtreeIfNeeded()
                try check(controller.viewer.inspector.displayedName == controller.state.selectedPhoto?.name, "Inspector filename matches the selected photo")
                try check(controller.viewer.inspector.rows.allSatisfy { $0.value.frame.width > 0 && $0.value.frame.maxX <= $0.bounds.width + 1 }, "Inspector values stay within their column bounds")
                controller.viewer.inspector.ratingMenu.selectItem(at: 6)
                _ = controller.viewer.inspector.ratingMenu.sendAction(controller.viewer.inspector.ratingMenu.action, to: controller.viewer.inspector.ratingMenu.target)
                try check(controller.state.selectedRating == 6, "Native inspector rating control changes the photo grade")
                key(28, characters: "8", modifiers: .control)
                await settle()
                try check(controller.state.selectedRating == 8 && controller.state.selectedID == selected, "Control 8 grades the current photo without moving selection")
                try check(AppState(defaults: controller.state.defaults).rating(for: selected!) == 8, "Photo rating survives preference reconstruction")
                key(29, characters: "0", modifiers: .control)
                await settle()
                try check(controller.state.selectedRating == 0, "Control 0 clears the photo rating")
                key(28, characters: "8", modifiers: .control)
                await settle()
                let fit = controller.viewer.canvas.scale
                controller.zoomIn(nil)
                try check(controller.viewer.canvas.scale > fit, "Viewer zoom changes rendered scale")
                controller.actualSize(nil)
                try check(controller.viewer.canvas.scale == 1, "Actual size uses 100 percent zoom")
                controller.fitImage(nil)
                controller.rotateImage(nil)
                try check(controller.viewer.canvas.quarterTurns == 1, "Rotation changes the canvas without writing the source")
                controller.rotateImage(nil); controller.rotateImage(nil); controller.rotateImage(nil)
                try await snapshot("03-viewer")
                key(124, characters: "\u{F703}")
                await settle(300)
                try check(controller.state.selectedID != selected, "Arrow key event changes the selected image")
                controller.state.select(selected)
                if hasActiveDisplay {
                    controller.toggleFullscreen(nil)
                    await settle(1300)
                    try check(controller.isFullscreen && controller.viewer.isFullscreen, "Native fullscreen enables the glass controls")
                    try await snapshot("04-fullscreen")
                    controller.window?.makeFirstResponder(controller.viewer.canvas)
                    key(53, characters: "\u{1B}")
                    for _ in 0..<40 {
                        if !controller.isFullscreen { break }
                        await settle(100)
                    }
                    await settle(250)
                    try check(!controller.isFullscreen && controller.state.mode == .viewer, "Escape exits fullscreen and restores the viewer window")
                    try check(controller.window?.toolbar?.isVisible == true, "Viewer toolbar returns after fullscreen animation")
                } else {
                    skipped.append("Native fullscreen round trip: macOS session is locked or display is asleep")
                }
                key(53, characters: "\u{1B}")
                await settle()
                try check(controller.state.mode == .browser && controller.state.selectedID == selected, "Returning to browser preserves selection")
                try check(controller.window?.toolbar?.isVisible == true, "Browser toolbar stays visible after fullscreen round trip")
                let other = controller.state.allPhotos[0].id
                controller.state.setRating(5, for: other)
                controller.state.setRatingFilter(.atLeast(6))
                try check(controller.state.visiblePhotos.count == 1 && controller.state.selectedID == selected, "Minimum score filter retains matching rated photos")
                controller.openSelected(nil)
                controller.state.setRating(5)
                try check(controller.state.visiblePhotos.isEmpty && controller.state.mode == .browser, "Grading below an active filter leaves a valid empty browser")
                controller.state.setRatingFilter(.all)
                controller.state.select(selected)
                controller.state.setRating(8)
                if let item = controller.ratingFilterMenu.itemArray.first(where: { $0.representedObject as? String == "exact:5" }) { controller.ratingFilterMenu.select(item) }
                _ = controller.ratingFilterMenu.sendAction(controller.ratingFilterMenu.action, to: controller.ratingFilterMenu.target)
                try check(controller.state.visiblePhotos.count == 1 && controller.state.selectedID == other, "Native score filter menu selects an exact grade")
                controller.state.setRatingFilter(.all)
                controller.state.select(selected)
                controller.state.setSort(.rating)
                try check(controller.state.visiblePhotos.first?.id == selected, "Rating sort puts the highest grade first")
                controller.state.setSort(.name)
                try await snapshot("07-ratings")
                controller.window?.appearance = NSAppearance(named: .darkAqua)
                try await snapshot("06-dark-browser")
                controller.window?.appearance = nil
                controller.state.showFavorites()
                try await loaded()
                try check(controller.state.visiblePhotos.count == 1, "Favorites view reads persisted file URLs")
                controller.back(nil)
                try check(controller.state.source == .demo && controller.state.selectedID == selected, "Back restores library selection")
                controller.forward(nil)
                try check(controller.state.source == .favorites, "Forward restores the favorites library")
                controller.state.toggleFavorite()
                try check(controller.state.visiblePhotos.isEmpty, "Removing the last favorite leaves a valid empty state")
                try await snapshot("05-empty-favorites")
                let fixtures = output.appendingPathComponent("Fixtures")
                if FileManager.default.fileExists(atPath: fixtures.path) { try FileManager.default.removeItem(at: fixtures) }
                try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
                for (index, photo) in controller.state.allPhotos.prefix(1).enumerated() {
                    let target = fixtures.appendingPathComponent("image\(index + 1).jpg")
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.copyItem(at: photo.url, to: target)
                }
                let target = fixtures.appendingPathComponent("image1.jpg")
                controller.state.open([target])
                try await loaded()
                await settle(200)
                try check(controller.state.mode == .viewer && controller.state.selectedPhoto?.url == target, "Opening a local file selects it in the native viewer")
                try check(controller.state.recentPaths.contains(target.path), "Local file opening updates recent items")
                controller.state.setRating(7)
                controller.state.toggleFavorite()
                controller.state.defaults.set(["旅行"], forKey: "tags:\(target.path)")
                let renamed = try PhotoFileOperations.rename(target, to: "renamed.jpg")
                controller.state.renamedFile(from: target, to: renamed)
                try await loaded()
                try check(controller.state.selectedPhoto?.url == renamed && controller.state.selectedRating == 7 && controller.state.isFavorite,
                          "Renaming a file keeps its grade and favorite state")
                try check(controller.state.defaults.stringArray(forKey: "tags:\(renamed.path)") == ["旅行"], "Renaming a file moves its local tags")
                controller.copyFileName(nil)
                try check(controller.clipboard.string(forType: .string) == "renamed.jpg", "Context copy filename writes the real filesystem name")
                controller.copyFilePath(nil)
                try check(controller.clipboard.string(forType: .string) == renamed.path, "Context copy path writes the absolute file path")
                controller.copyFile(nil)
                try check(controller.copiedFileURLs == [renamed], "Copy file places a native file URL on an isolated pasteboard")
                controller.pasteFiles(nil)
                try await loaded()
                let pasted = try requireURL(controller.state.selectedPhoto?.url)
                try check(pasted != renamed && (try? Data(contentsOf: pasted)) == (try? Data(contentsOf: renamed)), "Pasting files copies image bytes without overwriting the original")
                controller.duplicateFile(nil)
                try await loaded()
                try check(controller.state.selectedPhoto?.url != pasted && controller.state.allPhotos.count == 3, "Duplicate creates another file and refreshes the library")
                let commands = controller.photoMenu().items.map(\.title)
                try check(["复制文件名", "复制文件", "打开所在文件夹", "重命名…", "制作副本", "移到废纸篓"].allSatisfy(commands.contains), "Photo context menu contains standard filesystem actions")
                let rawFixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/LumaCoreTests/Fixtures/synthetic.dng")
                let rawURL = fixtures.appendingPathComponent("camera.dng")
                try FileManager.default.copyItem(at: rawFixture, to: rawURL)
                controller.state.open([rawURL])
                try await loaded()
                for _ in 0..<50 {
                    if controller.viewer.canvas.image != nil && controller.viewer.canvas.photo?.url == rawURL { break }
                    await settle(50)
                }
                try check(controller.state.selectedPhoto?.metadata.isRAW == true && controller.viewer.canvas.image != nil, "Genuine Bayer DNG opens and renders in the native detail viewer")
                try await snapshot("08-raw-viewer")
                try ("PASS\n" + passed.joined(separator: "\n") + "\n" + skipped.map { "SKIP: " + $0 }.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                controller.state.defaults.removePersistentDomain(forName: domain)
                print("Luma UI validation passed: \(passed.count) checks, \(skipped.count) skipped. Evidence: \(output.path)")
                NSApp.terminate(nil)
            } catch {
                let message = (error as? Failure)?.message ?? error.localizedDescription
                try? ("FAIL: \(message)\n" + passed.joined(separator: "\n")).write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                controller.state.defaults.removePersistentDomain(forName: domain)
                fputs("Luma UI validation failed: \(message)\n", stderr)
                Darwin.exit(1)
            }
        }
    }
    private static var hasActiveDisplay: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool != true && CGDisplayIsActive(CGMainDisplayID()) != 0
    }
    private static func requireURL(_ url: URL?) throws -> URL {
        guard let url else { throw Failure(message: "Missing selected file URL") }
        return url
    }
}
#endif
