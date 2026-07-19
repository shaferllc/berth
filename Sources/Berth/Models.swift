import Foundation

/// How far along we are in enriching a saved link with page metadata.
enum MetadataState: String, Codable, Sendable {
    /// Saved, no fetch attempted yet (or a fetch was interrupted).
    case pending
    /// A fetch is in flight right now.
    case fetching
    /// Metadata fetch completed (even if the page had nothing useful).
    case done
    /// The fetch failed (offline, timeout, 4xx/5xx). Retry available.
    case failed
}

struct Bookmark: Identifiable, Hashable, Sendable {
    var id: UUID
    var url: String
    var normalizedURL: String
    var title: String
    var pageDescription: String
    var note: String
    var tags: [String]
    var isFavorite: Bool
    var addedAt: Date
    var metadataState: MetadataState

    init(
        id: UUID = UUID(),
        url: String,
        title: String = "",
        pageDescription: String = "",
        note: String = "",
        tags: [String] = [],
        isFavorite: Bool = false,
        addedAt: Date = Date(),
        metadataState: MetadataState = .pending
    ) {
        self.id = id
        self.url = url
        self.normalizedURL = URLNormalizer.normalize(url)
        self.title = title
        self.pageDescription = pageDescription
        self.note = note
        self.tags = tags
        self.isFavorite = isFavorite
        self.addedAt = addedAt
        self.metadataState = metadataState
    }

    var host: String {
        URL(string: url)?.host ?? ""
    }

    /// Host without a leading "www." — nicer in lists.
    var displayHost: String {
        let h = host
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return displayHost.isEmpty ? url : displayHost
    }

    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(query) { return true }
        if url.localizedCaseInsensitiveContains(query) { return true }
        if pageDescription.localizedCaseInsensitiveContains(query) { return true }
        if note.localizedCaseInsensitiveContains(query) { return true }
        return tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

// Tolerant Codable: every field except `url` has a fallback, so older or
// hand-edited stores still load.
extension Bookmark: Codable {
    enum CodingKeys: String, CodingKey {
        case id, url, normalizedURL, title, pageDescription, note, tags,
             isFavorite, addedAt, metadataState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let url = try c.decode(String.self, forKey: .url)
        self.url = url
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.normalizedURL = try c.decodeIfPresent(String.self, forKey: .normalizedURL)
            ?? URLNormalizer.normalize(url)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.pageDescription = try c.decodeIfPresent(String.self, forKey: .pageDescription) ?? ""
        self.note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        let state = try c.decodeIfPresent(MetadataState.self, forKey: .metadataState) ?? .done
        // An interrupted fetch resumes as pending.
        self.metadataState = (state == .fetching) ? .pending : state
    }
}

enum URLNormalizer {
    /// Canonical form used for duplicate detection: lowercased scheme/host,
    /// no fragment, no trailing slash, default ports dropped.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed) else { return trimmed.lowercased() }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        comps.fragment = nil
        if comps.port == 80, comps.scheme == "http" { comps.port = nil }
        if comps.port == 443, comps.scheme == "https" { comps.port = nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        return comps.string ?? trimmed.lowercased()
    }

    /// Turns loose user input ("example.com/x") into a full http(s) URL,
    /// or nil if it can't plausibly be a web link.
    static func completeURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") {
            guard text.contains(".") || text.hasPrefix("localhost") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
