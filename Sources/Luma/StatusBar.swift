import AppKit
import LumaCore

final class StatusBar: FlippedView {
    let path = label(size: 10, color: .secondaryLabelColor)
    let count = label(size: 10, color: .secondaryLabelColor)
    let profile = label(size: 10, color: .secondaryLabelColor)
    let hint = label("⌘ 滚轮", size: 10, color: .tertiaryLabelColor)
    let sizeMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    let slider = NSSlider(value: 2, minValue: 0, maxValue: 4, target: nil, action: nil)
    let smaller = ActionButton(symbol: "photo", title: "减小缩略图", size: 12)
    let larger = ActionButton(symbol: "photo", title: "放大缩略图", size: 17)
    private let state: AppState
    private let line = NSBox()

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        count.alignment = .center
        profile.alignment = .right
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(slide)
        slider.setAccessibilityLabel("缩略图大小")
        sizeMenu.isBordered = false
        sizeMenu.font = .systemFont(ofSize: 11)
        sizeMenu.controlSize = .small
        for size in ThumbnailSize.allCases { sizeMenu.addItem(withTitle: "\(size.title) · \(Int(size.width)) pt") }
        sizeMenu.target = self
        sizeMenu.action = #selector(choose)
        sizeMenu.setAccessibilityLabel("缩略图尺寸档位")
        smaller.actionHandler = { [weak self] in self?.state.stepSize(-1) }
        larger.actionHandler = { [weak self] in self?.state.stepSize(1) }
        line.boxType = .separator
        for v in [path, count, profile, hint, sizeMenu, slider, smaller, larger, line] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func slide() { state.setSize(ThumbnailSize(clamping: Int(slider.doubleValue.rounded()))) }
    @objc private func choose() { state.setSize(ThumbnailSize(clamping: sizeMenu.indexOfSelectedItem)) }
    func update() {
        slider.integerValue = state.thumbnailSize.rawValue
        sizeMenu.selectItem(at: state.thumbnailSize.rawValue)
        smaller.isEnabled = state.thumbnailSize != .tiny
        larger.isEnabled = state.thumbnailSize != .huge
        let viewer = state.mode == .viewer
        for v in [hint, sizeMenu, slider, smaller, larger] { v.isHidden = viewer || state.listMode }
        profile.isHidden = !viewer
        if viewer, let photo = state.selectedPhoto {
            path.stringValue = "\(photo.metadata.dimensions)  ·  \(photo.metadata.fileSize)  ·  \(photo.metadata.format)"
            count.stringValue = "第 \((state.selectedIndex ?? 0) + 1) 张，共 \(state.visiblePhotos.count) 张"
            profile.stringValue = photo.metadata.colorProfile
        } else {
            path.stringValue = state.path
            count.stringValue = state.isLoading ? "正在读取图像…" : "\(state.visiblePhotos.count) 张图像" + (state.selectedID == nil ? "" : "，已选择 1 张") + (state.skipped > 0 ? " · 跳过 \(state.skipped) 个无法读取的文件" : "")
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        let width = bounds.width
        let viewer = state.mode == .viewer
        let left: CGFloat = !viewer && state.sidebarVisible ? 234 : 18
        let controlWidth: CGFloat = viewer || state.listMode ? 18 : 340
        path.frame = NSRect(x: left, y: 6, width: max(100, min(420, (width - left - controlWidth) * 0.5)), height: 16)
        let countLeft = path.frame.maxX + 10
        count.frame = NSRect(x: countLeft, y: 6, width: max(70, width - controlWidth - countLeft - 20), height: 16)
        let start = width - 338
        hint.frame = NSRect(x: start, y: 6, width: 44, height: 16)
        sizeMenu.frame = NSRect(x: start + 50, y: 1, width: 112, height: 24)
        smaller.frame = NSRect(x: start + 163, y: 1, width: 24, height: 24)
        slider.frame = NSRect(x: start + 193, y: 4, width: 108, height: 21)
        larger.frame = NSRect(x: width - 30, y: 1, width: 24, height: 24)
        profile.frame = NSRect(x: width - 170, y: 6, width: 152, height: 16)
    }
}
