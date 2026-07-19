import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: BookmarkStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 300)
        } content: {
            ListPane()
                .navigationSplitViewColumnWidth(min: 300, ideal: 370)
        } detail: {
            DetailPane()
        }
        .sheet(isPresented: $store.showingAddSheet) {
            AddBookmarkSheet()
        }
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.scheme == "http" || url.scheme == "https" else { return }
                    Task { @MainActor in
                        BookmarkStore.shared.addOrSelect(urlString: url.absoluteString)
                    }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string,
                          let url = URLNormalizer.completeURL(from: string) else { return }
                    Task { @MainActor in
                        BookmarkStore.shared.addOrSelect(urlString: url.absoluteString)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: BookmarkStore

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("Library") {
                Label("All Bookmarks", systemImage: "books.vertical")
                    .badge(store.bookmarks.count)
                    .tag(SidebarItem.all)
                Label("Favorites", systemImage: "star")
                    .badge(store.favoritesCount)
                    .tag(SidebarItem.favorites)
                Label("Untagged", systemImage: "tag.slash")
                    .badge(store.untaggedCount)
                    .tag(SidebarItem.untagged)
            }
            if !store.tagCounts.isEmpty {
                Section("Tags") {
                    ForEach(store.tagCounts, id: \.tag) { entry in
                        Label(entry.tag, systemImage: "tag")
                            .badge(entry.count)
                            .tag(SidebarItem.tag(entry.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Berth")
    }
}
