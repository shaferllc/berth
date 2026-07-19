import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case all
    case favorites
    case untagged
    case tag(String)
}

enum BookmarkSort: String, CaseIterable, Identifiable {
    case dateAdded
    case title
    case domain

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateAdded: "Date Added"
        case .title: "Title"
        case .domain: "Domain"
        }
    }
}

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published var bookmarks: [Bookmark] = []
    @Published var sidebarSelection: Set<SidebarItem> = [.all]
    @Published var selectedID: Bookmark.ID?
    @Published var searchText = ""
    @Published var showingAddSheet = false
    @Published var sortOrder: BookmarkSort {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "berth.sortOrder") }
    }

    // Soft-delete stack: each entry is one delete action, with original
    // positions so ⌘Z restores order exactly.
    @Published private(set) var deletedStack: [[(index: Int, bookmark: Bookmark)]] = []
    var canUndoDelete: Bool { !deletedStack.isEmpty }

    private var saveTask: Task<Void, Never>?

    init() {
        let savedSort = UserDefaults.standard.string(forKey: "berth.sortOrder")
        sortOrder = savedSort.flatMap(BookmarkSort.init(rawValue:)) ?? .dateAdded
        load()
        // Resume any fetches that never completed (fresh saves, crashes, offline).
        for b in bookmarks where b.metadataState == .pending {
            refreshMetadata(for: b.id)
        }
    }

    // MARK: - Derived collections

    var selectedBookmark: Bookmark? {
        selectedID.flatMap { id in bookmarks.first { $0.id == id } }
    }

    var visibleBookmarks: [Bookmark] {
        var items = bookmarks
        let sel = sidebarSelection
        if sel.contains(.favorites) { items = items.filter(\.isFavorite) }
        if sel.contains(.untagged) { items = items.filter { $0.tags.isEmpty } }
        let selectedTags = sel.compactMap { item -> String? in
            if case .tag(let t) = item { return t }
            return nil
        }
        if !selectedTags.isEmpty {
            items = items.filter { b in
                selectedTags.allSatisfy { t in
                    b.tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame }
                }
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { items = items.filter { $0.matches(query: query) } }

        switch sortOrder {
        case .dateAdded:
            items.sort { $0.addedAt > $1.addedAt }
        case .title:
            items.sort {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .domain:
            items.sort {
                let c = $0.displayHost.localizedCaseInsensitiveCompare($1.displayHost)
                if c != .orderedSame { return c == .orderedAscending }
                return $0.addedAt > $1.addedAt
            }
        }
        return items
    }

    /// Unique tags with usage counts, case-insensitive, alphabetical.
    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: (display: String, count: Int)] = [:]
        for b in bookmarks {
            for t in b.tags {
                let key = t.lowercased()
                if let existing = counts[key] {
                    counts[key] = (existing.display, existing.count + 1)
                } else {
                    counts[key] = (t, 1)
                }
            }
        }
        return counts.values
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
            .map { (tag: $0.display, count: $0.count) }
    }

    var allTags: [String] { tagCounts.map(\.tag) }
    var favoritesCount: Int { bookmarks.count(where: \.isFavorite) }
    var untaggedCount: Int { bookmarks.count(where: { $0.tags.isEmpty }) }

    // MARK: - Adding

    func findExisting(urlString: String) -> Bookmark? {
        let norm = URLNormalizer.normalize(urlString)
        return bookmarks.first { $0.normalizedURL == norm }
    }

    /// Add if new; if the normalized URL is already saved, reveal it instead.
    @discardableResult
    func addOrSelect(urlString: String, title: String = "", tags: [String] = []) -> Bookmark {
        if let existing = findExisting(urlString: urlString) {
            reveal(existing.id)
            return existing
        }
        return addNew(urlString: urlString, title: title, tags: tags)
    }

    @discardableResult
    func addNew(urlString: String, title: String = "", tags: [String] = []) -> Bookmark {
        let bookmark = Bookmark(url: urlString, title: title, tags: tags)
        bookmarks.insert(bookmark, at: 0)
        reveal(bookmark.id)
        refreshMetadata(for: bookmark.id)
        scheduleSave()
        return bookmark
    }

    func addFromClipboard() {
        let pb = NSPasteboard.general
        var raw = pb.string(forType: .URL) ?? pb.string(forType: .string)
        if let url = pb.readObjects(forClasses: [NSURL.self])?.first as? URL {
            raw = url.absoluteString
        }
        guard let raw, let url = URLNormalizer.completeURL(from: raw) else {
            NSSound.beep()
            return
        }
        addOrSelect(urlString: url.absoluteString)
    }

    /// Select a bookmark, clearing any filter that would hide it.
    func reveal(_ id: Bookmark.ID) {
        if !visibleBookmarks.contains(where: { $0.id == id }) {
            sidebarSelection = [.all]
            searchText = ""
        }
        selectedID = id
    }

    // MARK: - Editing

    func update(_ id: Bookmark.ID, _ mutate: (inout Bookmark) -> Void) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&bookmarks[i])
        scheduleSave()
    }

    func toggleFavorite(_ id: Bookmark.ID) {
        update(id) { $0.isFavorite.toggle() }
    }

    func toggleFavoriteSelected() {
        if let id = selectedID { toggleFavorite(id) }
    }

    // MARK: - Delete / undo

    func delete(ids: [Bookmark.ID]) {
        var removed: [(index: Int, bookmark: Bookmark)] = []
        for id in ids {
            if let i = bookmarks.firstIndex(where: { $0.id == id }) {
                removed.append((i, bookmarks[i]))
                bookmarks.remove(at: i)
            }
        }
        guard !removed.isEmpty else { return }
        deletedStack.append(removed)
        if deletedStack.count > 100 { deletedStack.removeFirst() }
        if let sel = selectedID, ids.contains(sel) { selectedID = nil }
        scheduleSave()
    }

    func deleteSelected() {
        if let id = selectedID { delete(ids: [id]) }
    }

    func undoDelete() {
        guard let batch = deletedStack.popLast() else { return }
        for (index, bookmark) in batch.sorted(by: { $0.index < $1.index }) {
            bookmarks.insert(bookmark, at: min(index, bookmarks.count))
        }
        if let first = batch.first { selectedID = first.bookmark.id }
        scheduleSave()
    }

    // MARK: - Actions

    func open(_ bookmark: Bookmark) {
        guard let url = URL(string: bookmark.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func openSelected() {
        if let b = selectedBookmark { open(b) }
    }

    func copyURL(_ bookmark: Bookmark) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(bookmark.url, forType: .string)
    }

    func copySelectedURL() {
        if let b = selectedBookmark { copyURL(b) }
    }

    // MARK: - Metadata

    func refreshMetadata(for id: Bookmark.ID) {
        Task { await fetchMetadata(id: id) }
    }

    private func fetchMetadata(id: Bookmark.ID) async {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }),
              let url = URL(string: bookmarks[i].url)
        else { return }
        guard bookmarks[i].metadataState != .fetching else { return }
        bookmarks[i].metadataState = .fetching
        let host = url.host ?? ""
        do {
            let meta = try await PageMetadata.fetch(url)
            guard let j = bookmarks.firstIndex(where: { $0.id == id }) else { return }
            if bookmarks[j].title.trimmingCharacters(in: .whitespaces).isEmpty,
               let t = meta.title, !t.isEmpty {
                bookmarks[j].title = t
            }
            if let d = meta.description, !d.isEmpty {
                bookmarks[j].pageDescription = d
            }
            if let iconData = meta.faviconData {
                FaviconCache.store(iconData, host: host)
            }
            bookmarks[j].metadataState = .done
        } catch {
            guard let j = bookmarks.firstIndex(where: { $0.id == id }) else { return }
            bookmarks[j].metadataState = .failed
        }
        scheduleSave()
    }

    // MARK: - Persistence (single JSON store, debounced, atomic)

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.storeFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Bookmark].self, from: data) {
            bookmarks = loaded
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookmarks) else { return }
        try? data.write(to: AppPaths.storeFile, options: .atomic)
    }

    // MARK: - Import / export

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Berth Bookmarks.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(bookmarks)
            try data.write(to: url, options: .atomic)
        } catch {
            presentAlert("Export Failed", error.localizedDescription)
        }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let imported = try decoder.decode([Bookmark].self, from: data)
            var added = 0
            var skipped = 0
            for var b in imported {
                b.normalizedURL = URLNormalizer.normalize(b.url)
                if findExisting(urlString: b.url) == nil {
                    bookmarks.append(b)
                    added += 1
                    if b.metadataState == .pending { refreshMetadata(for: b.id) }
                } else {
                    skipped += 1
                }
            }
            scheduleSave()
            presentAlert(
                "Import Complete",
                "Added \(added) bookmark\(added == 1 ? "" : "s")."
                    + (skipped > 0 ? " Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")." : ""))
        } catch {
            presentAlert("Import Failed", "That file doesn't look like a Berth JSON export.")
        }
    }

    /// Netscape bookmarks HTML — the interchange format every browser imports.
    func exportNetscapeHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Berth Bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- Generated by Berth -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>

        """
        for b in bookmarks.sorted(by: { $0.addedAt < $1.addedAt }) {
            let stamp = Int(b.addedAt.timeIntervalSince1970)
            var attrs = "HREF=\"\(esc(b.url))\" ADD_DATE=\"\(stamp)\""
            if !b.tags.isEmpty { attrs += " TAGS=\"\(esc(b.tags.joined(separator: ",")))\"" }
            out += "    <DT><A \(attrs)>\(esc(b.displayTitle))</A>\n"
        }
        out += "</DL><p>\n"
        do {
            try out.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            presentAlert("Export Failed", error.localizedDescription)
        }
    }

    private func presentAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
