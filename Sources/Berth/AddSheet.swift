import AppKit
import SwiftUI

struct AddBookmarkSheet: View {
    @EnvironmentObject private var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var titleText = ""
    @State private var tagsText = ""
    @FocusState private var urlFocused: Bool

    private var candidateURL: URL? {
        URLNormalizer.completeURL(from: urlText)
    }

    private var duplicate: Bookmark? {
        candidateURL.flatMap { store.findExisting(urlString: $0.absoluteString) }
    }

    private var enteredTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The tag fragment currently being typed (after the last comma).
    private var currentFragment: String {
        tagsText.split(separator: ",", omittingEmptySubsequences: false)
            .last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private var tagSuggestions: [String] {
        let fragment = currentFragment
        return store.allTags.filter { candidate in
            let used = enteredTags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            guard !used else { return false }
            return fragment.isEmpty || candidate.localizedCaseInsensitiveContains(fragment)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Bookmark")
                .font(.headline)

            TextField("URL", text: $urlText, prompt: Text("https://example.com/page"))
                .textFieldStyle(.roundedBorder)
                .focused($urlFocused)

            TextField("Title (optional — fetched from the page if left blank)", text: $titleText)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            if !tagSuggestions.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button(tag) { appendTag(tag) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            if let dup = duplicate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Already saved \(dup.addedAt.formatted(date: .abbreviated, time: .omitted)) — “\(dup.displayTitle)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("Show Existing") {
                        store.reveal(dup.id)
                        dismiss()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(duplicate == nil ? "Add" : "Add Anyway") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(candidateURL == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            prefillFromClipboard()
            urlFocused = true
        }
    }

    private func appendTag(_ tag: String) {
        var kept = tagsText.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if !kept.isEmpty { kept.removeLast() } // drop the fragment being typed
        kept.removeAll(where: \.isEmpty)
        kept.append(tag)
        tagsText = kept.joined(separator: ", ") + ", "
    }

    /// If the clipboard holds a URL and the field is empty, offer it prefilled.
    private func prefillFromClipboard() {
        guard urlText.isEmpty else { return }
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        if let url = URLNormalizer.completeURL(from: pasted),
           pasted.trimmingCharacters(in: .whitespacesAndNewlines).contains("://") {
            urlText = url.absoluteString
        }
    }

    private func save() {
        guard let url = candidateURL else { return }
        store.addNew(urlString: url.absoluteString, title: titleText, tags: enteredTags)
        dismiss()
    }
}
