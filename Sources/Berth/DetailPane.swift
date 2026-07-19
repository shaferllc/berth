import SwiftUI

struct DetailPane: View {
    @EnvironmentObject private var store: BookmarkStore

    var body: some View {
        if let bookmark = store.selectedBookmark {
            BookmarkDetail(bookmark: bookmark)
                .id(bookmark.id) // reset scroll/edit state when switching
        } else {
            ContentUnavailableView {
                Label("No Bookmark Selected", systemImage: "bookmark")
            } description: {
                Text("Select a bookmark from the list, or press ⌘N to add one.")
            }
        }
    }
}

struct BookmarkDetail: View {
    @EnvironmentObject private var store: BookmarkStore
    let bookmark: Bookmark

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                urlRow
                actionRow
                metadataStatus
                if !bookmark.pageDescription.isEmpty {
                    section("Description") {
                        Text(bookmark.pageDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("Note") {
                    TextEditor(text: Binding(
                        get: { bookmark.note },
                        set: { value in store.update(bookmark.id) { $0.note = value } }
                    ))
                    .font(.body)
                    .frame(minHeight: 72, maxHeight: 160)
                    .padding(4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1))
                    .scrollContentBackground(.hidden)
                }
                section("Tags") {
                    TagEditor(bookmark: bookmark)
                }
                Divider()
                footer
            }
            .padding(22)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            FaviconView(host: bookmark.host, size: 28, refreshToken: bookmark.metadataState)
            TextField(
                "Title",
                text: Binding(
                    get: { bookmark.title },
                    set: { value in store.update(bookmark.id) { $0.title = value } }
                ),
                prompt: Text(bookmark.displayHost.isEmpty ? "Untitled" : bookmark.displayHost)
            )
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            Button {
                store.toggleFavorite(bookmark.id)
            } label: {
                Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(bookmark.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    private var urlRow: some View {
        HStack(spacing: 6) {
            Text(bookmark.url)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                store.copyURL(bookmark)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy URL (⌘⇧C)")
            Spacer()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                store.open(bookmark)
            } label: {
                Label("Open in Browser", systemImage: "arrow.up.forward.app")
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
            Button(role: .destructive) {
                store.delete(ids: [bookmark.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete — undo with ⌘Z")
        }
    }

    @ViewBuilder
    private var metadataStatus: some View {
        switch bookmark.metadataState {
        case .fetching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Fetching page info…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .pending:
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Page info pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Fetch Now") { store.refreshMetadata(for: bookmark.id) }
                    .controlSize(.small)
            }
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Couldn't fetch page info — link is saved anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") { store.refreshMetadata(for: bookmark.id) }
                    .controlSize(.small)
            }
        case .done:
            EmptyView()
        }
    }

    private var footer: some View {
        Text("Added \(bookmark.addedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}
