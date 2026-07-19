import AppKit
import SwiftUI

@main
struct BerthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = BookmarkStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            BerthCommands(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs dragged onto the Dock icon (the app declares public.url in its
    /// Info.plist) arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "http" || url.scheme == "https" {
            BookmarkStore.shared.addOrSelect(urlString: url.absoluteString)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BookmarkStore.shared.saveNow()
    }
}

extension Notification.Name {
    static let berthFocusSearch = Notification.Name("berth.focusSearch")
}

struct BerthCommands: Commands {
    @ObservedObject var store: BookmarkStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Bookmark…") { store.showingAddSheet = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add from Clipboard") { store.addFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Import JSON…") { store.importJSON() }
            Button("Export JSON…") { store.exportJSON() }
            Button("Export Bookmarks HTML…") { store.exportNetscapeHTML() }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Delete") { store.undoDelete() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndoDelete)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .berthFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Bookmark") {
            Button("Open in Browser") { store.openSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.selectedBookmark == nil)
            Button("Copy URL") { store.copySelectedURL() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.selectedBookmark == nil)
            Button(store.selectedBookmark?.isFavorite == true
                   ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavoriteSelected()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(store.selectedBookmark == nil)
            Divider()
            Button("Refresh Metadata") {
                if let id = store.selectedID { store.refreshMetadata(for: id) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.selectedBookmark == nil)
            Divider()
            Button("Delete Bookmark") { store.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedBookmark == nil)
        }
    }
}
