import AppKit
import LumaCore

@MainActor
final class AppState {
    enum Mode { case empty, browser, viewer }
    enum Change { case content, selection, preferences, loading }
    enum Source: Equatable {
        case demo, recent, favorites, folder(URL), files
    }

    let defaults: UserDefaults
    var onChange: ((Change) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var mode: Mode = .empty
    private(set) var source: Source = .files
    private(set) var allPhotos: [Photo] = []
    private(set) var visiblePhotos: [Photo] = []
    private(set) var selectedID: String?
    private(set) var isLoading = false
    private(set) var skipped = 0
    private(set) var title = "Luma"
    private(set) var folders: [URL]
    private(set) var favoritePaths: Set<String>
    private(set) var recentPaths: [String]
    private(set) var thumbnailSize: ThumbnailSize
    private(set) var sort: PhotoSort
    private(set) var query = ""
    private(set) var listMode: Bool
    private(set) var sidebarVisible: Bool
    private(set) var inspectorVisible: Bool
    private(set) var ratings: [String: Int]
    private(set) var ratingFilter: RatingFilter
    private(set) var preferences: AppPreferences
    private(set) var viewerStyle: ViewerStyle = .details
    var isImageOnly: Bool { mode == .viewer && viewerStyle == .imageOnly }
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private struct Location {
        let source: Source
        let title: String
        let photos: [Photo]
        let selectedID: String?
        let query: String
        let skipped: Int
    }
    private var backHistory: [Location] = []
    private var forwardHistory: [Location] = []
    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    var selectedPhoto: Photo? { visiblePhotos.first { $0.id == selectedID } }
    var selectedIndex: Int? { visiblePhotos.firstIndex { $0.id == selectedID } }
    var hasPhotos: Bool { !visiblePhotos.isEmpty }
    var isFavorite: Bool { selectedID.map { favoritePaths.contains($0) } ?? false }
    var path: String {
        switch source {
        case .demo: return "示例图库  ›  山海之间"
        case .recent: return "个人收藏  ›  最近打开"
        case .favorites: return "个人收藏  ›  个人收藏"
        case .folder(let url): return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        case .files: return selectedPhoto?.url.deletingLastPathComponent().path ?? ""
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = AppPreferences(defaults: defaults)
        thumbnailSize = ThumbnailSize(clamping: defaults.object(forKey: "thumbnailSize") as? Int ?? 2)
        sort = PhotoSort(rawValue: defaults.string(forKey: "sort") ?? "") ?? .name
        listMode = defaults.bool(forKey: "listMode")
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true
        inspectorVisible = defaults.object(forKey: "inspectorVisible") as? Bool ?? true
        folders = (defaults.stringArray(forKey: "folders") ?? []).map { URL(fileURLWithPath: $0) }
        favoritePaths = Set(defaults.stringArray(forKey: "favorites") ?? [])
        recentPaths = defaults.stringArray(forKey: "recents") ?? []
        ratings = (defaults.dictionary(forKey: "ratings") ?? [:]).compactMapValues { ($0 as? NSNumber).map { PhotoRating($0.intValue).value } }
        ratingFilter = RatingFilter(stored: defaults.string(forKey: "ratingFilter") ?? "all")
    }

    func setSize(_ size: ThumbnailSize) {
        guard size != thumbnailSize else { return }
        thumbnailSize = size
        defaults.set(size.rawValue, forKey: "thumbnailSize")
        onChange?(.preferences)
    }

    func stepSize(_ delta: Int) { setSize(thumbnailSize.stepping(delta)) }

    func updatePreferences(_ update: (inout AppPreferences) -> Void) {
        var updated = preferences
        update(&updated)
        guard updated != preferences else { return }
        preferences = updated
        updated.save(to: defaults)
        onChange?(.preferences)
    }

    func setViewerStyle(_ style: ViewerStyle) {
        guard selectedPhoto != nil else { return }
        viewerStyle = style
        if mode != .viewer { showViewer(style: style) } else { onChange?(.preferences) }
    }

    func setListMode(_ list: Bool) {
        listMode = list
        defaults.set(list, forKey: "listMode")
        onChange?(.preferences)
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
        defaults.set(sidebarVisible, forKey: "sidebarVisible")
        onChange?(.preferences)
    }

    func toggleInspector() {
        inspectorVisible.toggle()
        defaults.set(inspectorVisible, forKey: "inspectorVisible")
        onChange?(.preferences)
    }

    func setQuery(_ query: String) { self.query = query; filter() }
    func setSort(_ sort: PhotoSort) {
        self.sort = sort
        defaults.set(sort.rawValue, forKey: "sort")
        filter()
    }

    private func filter() {
        let previousIndex = selectedIndex ?? 0
        visiblePhotos = sort.sorted(allPhotos.filter {
            (query.isEmpty || $0.name.localizedStandardContains(query)) &&
            (source != .favorites || favoritePaths.contains($0.id)) && ratingFilter.includes(rating(for: $0.id))
        }, ratings: ratings)
        if !visiblePhotos.contains(where: { $0.id == selectedID }) {
            selectedID = visiblePhotos.isEmpty ? nil : visiblePhotos[min(previousIndex, visiblePhotos.count - 1)].id
        }
        if visiblePhotos.isEmpty && mode == .viewer { mode = .browser }
        onChange?(.content)
    }

    func select(_ id: String?) {
        guard id == nil || visiblePhotos.contains(where: { $0.id == id }), id != selectedID else { return }
        selectedID = id
        onChange?(.selection)
    }

    func rating(for id: String) -> Int { ratings[id] ?? 0 }
    var selectedRating: Int { selectedID.map { rating(for: $0) } ?? 0 }
    func setRating(_ score: Int, for id: String? = nil) {
        guard let id = id ?? selectedID, allPhotos.contains(where: { $0.id == id }) else { return }
        let value = PhotoRating(score).value
        guard rating(for: id) != value else { return }
        if value == 0 { ratings.removeValue(forKey: id) } else { ratings[id] = value }
        defaults.set(ratings, forKey: "ratings")
        filter()
    }
    func setRatingFilter(_ filter: RatingFilter) {
        ratingFilter = filter
        defaults.set(filter.stored, forKey: "ratingFilter")
        self.filter()
    }

    func navigate(_ delta: Int) {
        guard !visiblePhotos.isEmpty else { return }
        let index = min(visiblePhotos.count - 1, max(0, (selectedIndex ?? 0) + delta))
        select(visiblePhotos[index].id)
        if mode == .viewer { recordRecent() }
    }

    func showViewer(style: ViewerStyle? = nil) {
        guard selectedPhoto != nil else { return }
        viewerStyle = style ?? preferences.openMode.viewerStyle
        mode = .viewer
        recordRecent()
        onChange?(.content)
    }

    func showBrowser() {
        mode = allPhotos.isEmpty && source == .files ? .empty : .browser
        onChange?(.content)
    }

    private var location: Location {
        Location(source: source, title: title, photos: allPhotos, selectedID: selectedID, query: query, skipped: skipped)
    }
    private func restore(_ location: Location) {
        loadTask?.cancel()
        loadGeneration = UUID()
        isLoading = false
        source = location.source
        title = location.title
        allPhotos = location.photos
        selectedID = location.selectedID
        query = location.query
        skipped = location.skipped
        mode = .browser
        filter()
    }
    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(location)
        restore(previous)
    }
    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(location)
        restore(next)
    }

    func toggleFavorite() {
        guard let photo = selectedPhoto else { return }
        if favoritePaths.contains(photo.id) { favoritePaths.remove(photo.id) } else { favoritePaths.insert(photo.id) }
        defaults.set(favoritePaths.sorted(), forKey: "favorites")
        if source == .favorites { filter() } else { onChange?(.selection) }
    }

    private func recordRecent() {
        guard let id = selectedID else { return }
        recentPaths.removeAll { $0 == id }
        recentPaths.insert(id, at: 0)
        recentPaths = Array(recentPaths.prefix(200))
        defaults.set(recentPaths, forKey: "recents")
    }

    func showDemo() {
        guard let directory = Bundle.module.url(forResource: "Demo", withExtension: nil) else {
            onError?("找不到示例图片，请重新构建应用。")
            return
        }
        load(urls: [directory], source: .demo, title: "山海之间", openViewer: preferences.openMode.opensViewer(singleImage: false))
    }

    func showRecent() {
        load(urls: existingURLs(recentPaths), source: .recent, title: "最近打开")
    }

    func showFavorites() {
        load(urls: existingURLs(Array(favoritePaths)), source: .favorites, title: "个人收藏")
    }

    private func existingURLs(_ paths: [String]) -> [URL] {
        paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let directory = urls.count == 1 && (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if directory {
            let url = urls[0].standardizedFileURL
            load(urls: [url], source: .folder(url), title: url.lastPathComponent,
                 openViewer: preferences.openMode.opensViewer(singleImage: false))
        } else if urls.count == 1 && ImageLibrary.supports(urls[0]) {
            // Finder's “Open With” keeps neighboring images available for arrow navigation.
            let url = urls[0].standardizedFileURL
            let parent = url.deletingLastPathComponent()
            if preferences.loadAdjacentImages {
                load(urls: [parent], source: .folder(parent), title: parent.lastPathComponent, preferred: url.path,
                     openViewer: preferences.openMode.opensViewer(singleImage: true), revealingPreferred: true, fallback: url)
            } else {
                load(urls: [url], source: .files, title: parent.lastPathComponent, preferred: url.path,
                     openViewer: preferences.openMode.opensViewer(singleImage: true), revealingPreferred: true)
            }
        } else {
            load(urls: urls, source: .files, title: "所选图像", openViewer: preferences.openMode.opensViewer(singleImage: false))
        }
    }

    func restoreLastFolder() {
        guard preferences.restoreLastFolder else { return }
        if let path = defaults.string(forKey: "lastFolder"), FileManager.default.fileExists(atPath: path) {
            open([URL(fileURLWithPath: path)])
        }
    }

    var currentDirectory: URL? {
        if case .folder(let url) = source { return url }
        return selectedPhoto?.url.deletingLastPathComponent()
    }

    func refresh(selecting url: URL? = nil) {
        let preferred = url?.path ?? selectedID
        let viewing = mode == .viewer
        switch source {
        case .favorites:
            load(urls: existingURLs(Array(favoritePaths)), source: .favorites, title: "个人收藏", preferred: preferred, openViewer: viewing, style: viewerStyle)
        case .recent:
            load(urls: existingURLs(recentPaths), source: .recent, title: "最近打开", preferred: preferred, openViewer: viewing, style: viewerStyle)
        case .folder(let directory):
            load(urls: [directory], source: .folder(directory), title: directory.lastPathComponent, preferred: preferred, openViewer: viewing, style: viewerStyle)
        case .files:
            load(urls: existingURLs(allPhotos.map(\.id)) + (url.map { [$0] } ?? []), source: .files, title: title, preferred: preferred, openViewer: viewing, style: viewerStyle)
        case .demo: showDemo()
        }
    }

    func renamedFile(from old: URL, to new: URL) {
        let oldID = old.standardizedFileURL.path, newID = new.standardizedFileURL.path
        if let value = ratings.removeValue(forKey: oldID) { ratings[newID] = value }
        if favoritePaths.remove(oldID) != nil { favoritePaths.insert(newID) }
        recentPaths = recentPaths.map { $0 == oldID ? newID : $0 }
        if let tags = defaults.stringArray(forKey: "tags:\(oldID)") {
            defaults.set(tags, forKey: "tags:\(newID)")
            defaults.removeObject(forKey: "tags:\(oldID)")
        }
        persistFileState()
        rewriteHistory(from: oldID, to: new)
        refresh(selecting: new)
    }

    func removedFile(_ url: URL) {
        let id = url.standardizedFileURL.path
        ratings.removeValue(forKey: id)
        favoritePaths.remove(id)
        recentPaths.removeAll { $0 == id }
        defaults.removeObject(forKey: "tags:\(id)")
        persistFileState()
        rewriteHistory(from: id, to: nil)
        refresh()
    }

    private func persistFileState() {
        defaults.set(ratings, forKey: "ratings")
        defaults.set(favoritePaths.sorted(), forKey: "favorites")
        defaults.set(recentPaths, forKey: "recents")
    }
    private func rewriteHistory(from id: String, to url: URL?) {
        func rewrite(_ entry: Location) -> Location {
            let photos = entry.photos.compactMap { photo -> Photo? in
                guard photo.id == id else { return photo }
                return url.map { Photo(url: $0, metadata: photo.metadata) }
            }
            return Location(source: entry.source, title: entry.title, photos: photos,
                            selectedID: entry.selectedID == id ? url?.path : entry.selectedID,
                            query: entry.query, skipped: entry.skipped)
        }
        backHistory = backHistory.map(rewrite)
        forwardHistory = forwardHistory.map(rewrite)
    }

    private func load(urls: [URL], source: Source, title: String, preferred: String? = nil, openViewer: Bool = false,
                      revealingPreferred: Bool = false, fallback: URL? = nil, style: ViewerStyle? = nil) {
        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        onChange?(.loading)
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    do { return try ImageLibrary.scan(urls: urls) }
                    catch { if let fallback { return try ImageLibrary.scan(urls: [fallback]) }; throw error }
                }
            }.value
            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            self.isLoading = false
            switch result {
            case .failure(let error):
                self.onChange?(.loading)
                self.onError?("无法打开图像：\(error.localizedDescription)")
            case .success(let scan):
                if self.mode != .empty && self.source != source {
                    self.backHistory.append(self.location)
                    self.backHistory = Array(self.backHistory.suffix(30))
                    self.forwardHistory.removeAll()
                }
                self.source = source
                self.title = title
                self.query = ""
                self.allPhotos = scan.photos
                self.skipped = scan.skipped
                self.selectedID = preferred ?? scan.photos.first?.id
                self.mode = openViewer && !scan.photos.isEmpty ? .viewer : .browser
                if self.mode == .viewer { self.viewerStyle = style ?? self.preferences.openMode.viewerStyle }
                if revealingPreferred, let preferred, !self.ratingFilter.includes(self.rating(for: preferred)) {
                    self.ratingFilter = .all
                    self.defaults.set(RatingFilter.all.stored, forKey: "ratingFilter")
                }
                if case .demo = source {
                    let names = ["03-mist", "02-cliffs", "04-coast", "01-cove", "05-shore", "06-ocean", "07-waves", "08-beach", "10-rocks", "11-forest", "12-road", "09-water"]
                    self.allPhotos = names.enumerated().compactMap { index, stem in
                        scan.photos.first(where: { $0.url.deletingPathExtension().lastPathComponent == stem }).map {
                            Photo(url: $0.url, name: "DSCF_\(2405 + index).jpg", metadata: $0.metadata)
                        }
                    }
                    self.selectedID = self.allPhotos.dropFirst(3).first?.id ?? self.allPhotos.first?.id
                }
                if case .folder(let url) = source {
                    self.folders.removeAll { $0 == url }
                    self.folders.insert(url, at: 0)
                    self.folders = Array(self.folders.prefix(20))
                    self.defaults.set(self.folders.map(\.path), forKey: "folders")
                    self.defaults.set(url.path, forKey: "lastFolder")
                }
                self.filter()
                if self.mode == .viewer { self.recordRecent() }
            }
        }
    }
}
