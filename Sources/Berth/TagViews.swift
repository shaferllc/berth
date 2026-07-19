import AppKit
import SwiftUI

// MARK: - Flow layout for tag chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : maxX
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let tag: String
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            if let onTap {
                Button(action: onTap) { chipText }
                    .buttonStyle(.plain)
                    .help("Filter by “\(tag)”")
            } else {
                chipText
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove tag")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }

    private var chipText: some View {
        Text(tag)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
    }
}

// MARK: - Tag editor with autocomplete

struct TagEditor: View {
    @EnvironmentObject private var store: BookmarkStore
    let bookmark: Bookmark
    @State private var newTag = ""

    private var suggestions: [String] {
        let fragment = newTag.trimmingCharacters(in: .whitespaces)
        return store.allTags.filter { candidate in
            let alreadyUsed = bookmark.tags.contains {
                $0.caseInsensitiveCompare(candidate) == .orderedSame
            }
            guard !alreadyUsed else { return false }
            return fragment.isEmpty || candidate.localizedCaseInsensitiveContains(fragment)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !bookmark.tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(bookmark.tags, id: \.self) { tag in
                        TagChip(
                            tag: tag,
                            onTap: { store.sidebarSelection = [.tag(tag)] },
                            onRemove: { remove(tag) })
                    }
                }
            }
            TextField("Add tag…", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .onSubmit { add(newTag) }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag) { add(tag) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        let exists = bookmark.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        if !exists {
            store.update(bookmark.id) { $0.tags.append(tag) }
        }
        newTag = ""
    }

    private func remove(_ tag: String) {
        store.update(bookmark.id) {
            $0.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }
}

// MARK: - Favicon

struct FaviconView: View {
    let host: String
    var size: CGFloat = 16
    /// Included so the view re-renders once a fetch lands the icon on disk.
    var refreshToken: MetadataState = .done

    var body: some View {
        Group {
            if let image = FaviconCache.image(for: host) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}
