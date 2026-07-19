import SwiftUI

struct ListPane: View {
    @EnvironmentObject private var store: BookmarkStore
    @AppStorage("berth.compactRows") private var compact = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            listOrPlaceholder
        }
        .navigationTitle(paneTitle)
        .toolbar {
            ToolbarItemGroup {
                Picker("Layout", selection: $compact) {
                    Image(systemName: "rectangle.grid.1x2").tag(false)
                        .help("List view")
                    Image(systemName: "list.bullet").tag(true)
                        .help("Compact view")
                }
                .pickerStyle(.segmented)
                Menu {
                    Picker("Sort By", selection: $store.sortOrder) {
                        ForEach(BookmarkSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort bookmarks")
                Button {
                    store.showingAddSheet = true
                } label: {
                    Label("New Bookmark", systemImage: "plus")
                }
                .help("New Bookmark (⌘N)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .berthFocusSearch)) { _ in
            searchFocused = true
        }
    }

    private var paneTitle: String {
        let sel = store.sidebarSelection
        if sel.count == 1, let item = sel.first {
            switch item {
            case .all: return "All Bookmarks"
            case .favorites: return "Favorites"
            case .untagged: return "Untagged"
            case .tag(let t): return t
            }
        }
        return sel.isEmpty ? "All Bookmarks" : "Filtered"
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search title, URL, notes, tags", text: $store.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var listOrPlaceholder: some View {
        let visible = store.visibleBookmarks
        if visible.isEmpty {
            if store.bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks Yet", systemImage: "bookmark")
                } description: {
                    Text("Press ⌘N to add a link, ⌘⇧V to grab one from the clipboard, or drag a URL from your browser onto this window.")
                }
            } else {
                ContentUnavailableView.search
            }
        } else {
            List(selection: $store.selectedID) {
                ForEach(visible) { bookmark in
                    BookmarkRow(bookmark: bookmark, compact: compact)
                        .tag(bookmark.id)
                        .contextMenu { rowMenu(bookmark) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            store.open(bookmark)
                        })
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { store.deleteSelected() }
            .onKeyPress(.return) {
                store.openSelected()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ bookmark: Bookmark) -> some View {
        Button("Open in Browser") { store.open(bookmark) }
        Button("Copy URL") { store.copyURL(bookmark) }
        Button(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            store.toggleFavorite(bookmark.id)
        }
        Divider()
        Button("Refresh Metadata") { store.refreshMetadata(for: bookmark.id) }
        Divider()
        Button("Delete", role: .destructive) { store.delete(ids: [bookmark.id]) }
    }
}

struct BookmarkRow: View {
    @EnvironmentObject private var store: BookmarkStore
    let bookmark: Bookmark
    let compact: Bool

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                FaviconView(host: bookmark.host, size: 14, refreshToken: bookmark.metadataState)
                Text(bookmark.displayTitle)
                    .lineLimit(1)
                if bookmark.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
                Spacer(minLength: 8)
                Text(bookmark.displayHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(bookmark.addedAt, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .padding(.vertical, 1)
        } else {
            HStack(alignment: .top, spacing: 9) {
                FaviconView(host: bookmark.host, size: 16, refreshToken: bookmark.metadataState)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(bookmark.displayTitle)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if bookmark.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                        if bookmark.metadataState == .fetching {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(bookmark.displayHost)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ForEach(bookmark.tags.prefix(4), id: \.self) { tag in
                            TagChip(tag: tag, onTap: {
                                store.sidebarSelection = [.tag(tag)]
                            })
                        }
                        if bookmark.tags.count > 4 {
                            Text("+\(bookmark.tags.count - 4)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(bookmark.addedAt, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .padding(.top, 2)
            }
            .padding(.vertical, 3)
        }
    }
}
