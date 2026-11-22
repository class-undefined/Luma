import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: WindowController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        let controller = WindowController(state: state)
        self.controller = controller
        buildMenu(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        let arguments = CommandLine.arguments.dropFirst()
        if !pendingURLs.isEmpty { state.open(pendingURLs) }
        else if arguments.contains("--demo") { state.showDemo() }
        else if !arguments.contains("--empty") {
            let paths = arguments.filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
            if paths.isEmpty { state.restoreLastFolder() } else { state.open(paths) }
        }
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if let controller { controller.state.open(urls) } else { pendingURLs = urls }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showWindow(nil)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu(_ controller: WindowController) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Luma")
        appMenu.addItem(withTitle: "关于 Luma", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "服务")
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Luma", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Luma", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            item.submenu = child; menu.addItem(item)
            return child
        }
        func add(_ parent: NSMenu, _ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            let item = parent.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = controller
            item.keyEquivalentModifierMask = modifiers
        }
        let file = submenu("文件")
        add(file, "打开…", #selector(WindowController.openFiles(_:)), "o")
        add(file, "打开示例图库", #selector(WindowController.openDemo(_:)), "o", modifiers: [.command, .shift])
        file.addItem(.separator())
        add(file, "在 Finder 中显示", #selector(WindowController.showInFinder(_:)), "r", modifiers: [.command, .shift])
        add(file, "共享…", #selector(WindowController.share(_:)))
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("拷贝", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let view = submenu("显示")
        add(view, "切换侧边栏", #selector(WindowController.toggleSidebar(_:)), "s", modifiers: [.command, .control])
        let image = submenu("图像")
        add(image, "打开选中图像", #selector(WindowController.openSelected(_:)), "\r", modifiers: [])
        add(image, "添加或取消收藏", #selector(WindowController.favorite(_:)), "d")
        let windows = submenu("窗口")
        windows.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = menu
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
