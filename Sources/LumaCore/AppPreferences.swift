import Foundation

public enum ViewerStyle: String, Sendable { case details, imageOnly }

public enum OpenMode: String, CaseIterable, Sendable {
    case automatic, browser, details, imageOnly
    public var title: String {
        switch self {
        case .automatic: return "自动（单张看图，文件夹浏览）"
        case .browser: return "图库浏览"
        case .details: return "照片详情"
        case .imageOnly: return "纯图片查看"
        }
    }
    public func opensViewer(singleImage: Bool) -> Bool { self == .automatic ? singleImage : self != .browser }
    public var viewerStyle: ViewerStyle { self == .imageOnly ? .imageOnly : .details }
}

public struct AppPreferences: Equatable, Sendable {
    public var openMode: OpenMode
    public var restoreLastFolder: Bool
    public var loadAdjacentImages: Bool
    public var showFilmstrip: Bool
    public var showStatusBar: Bool

    public init(defaults: UserDefaults) {
        openMode = OpenMode(rawValue: defaults.string(forKey: "openMode") ?? "") ?? .automatic
        restoreLastFolder = defaults.object(forKey: "restoreLastFolder") as? Bool ?? true
        loadAdjacentImages = defaults.object(forKey: "loadAdjacentImages") as? Bool ?? true
        showFilmstrip = defaults.object(forKey: "showFilmstrip") as? Bool ?? true
        showStatusBar = defaults.object(forKey: "showStatusBar") as? Bool ?? true
    }
    public func save(to defaults: UserDefaults) {
        defaults.set(openMode.rawValue, forKey: "openMode")
        defaults.set(restoreLastFolder, forKey: "restoreLastFolder")
        defaults.set(loadAdjacentImages, forKey: "loadAdjacentImages")
        defaults.set(showFilmstrip, forKey: "showFilmstrip")
        defaults.set(showStatusBar, forKey: "showStatusBar")
    }
}
