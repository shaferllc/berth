import AppKit
import Foundation

// MARK: - Paths

@MainActor
enum AppPaths {
    static var support: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Berth", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var storeFile: URL { support.appendingPathComponent("bookmarks.json") }

    static var faviconDir: URL {
        let dir = support.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Favicon cache (disk + memory, keyed by host)

@MainActor
enum FaviconCache {
    private static let memory = NSCache<NSString, NSImage>()
    private static var known: Set<String> = []   // hosts confirmed on disk
    private static var missing: Set<String> = [] // hosts confirmed absent

    private static func fileURL(for host: String) -> URL {
        let safe = host.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "." || ch == "-") ? ch : "_"
        }
        return AppPaths.faviconDir.appendingPathComponent(String(safe) + ".fav")
    }

    static func image(for host: String) -> NSImage? {
        guard !host.isEmpty else { return nil }
        if let img = memory.object(forKey: host as NSString) { return img }
        guard !missing.contains(host) else { return nil }
        let url = fileURL(for: host)
        guard let data = try? Data(contentsOf: url), let img = NSImage(data: data) else {
            missing.insert(host)
            return nil
        }
        memory.setObject(img, forKey: host as NSString)
        known.insert(host)
        return img
    }

    static func store(_ data: Data, host: String) {
        guard !host.isEmpty else { return }
        try? data.write(to: fileURL(for: host), options: .atomic)
        memory.removeObject(forKey: host as NSString)
        missing.remove(host)
        known.insert(host)
    }
}

// MARK: - Page metadata fetch

struct PageMetadata: Sendable {
    var title: String?
    var description: String?
    var faviconData: Data?

    enum FetchError: Error { case badStatus(Int), notReachable }

    /// One lightweight GET of the page (5 s request timeout), plus at most a
    /// couple of small favicon requests. No cookies, ephemeral session.
    static func fetch(_ url: URL) async throws -> PageMetadata {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Berth/0.1",
            "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
        ]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FetchError.badStatus(http.statusCode)
        }
        let baseURL = response.url ?? url

        var meta = PageMetadata()
        var iconHrefs: [String] = []

        if let html = decodeText(Data(data.prefix(700_000))) {
            let head = parse(html: html)
            meta.title = head.title
            meta.description = head.description
            iconHrefs = head.iconHrefs
        }

        // Favicon: declared <link rel=icon> candidates first, then /favicon.ico.
        var candidates: [URL] = iconHrefs.compactMap {
            URL(string: $0, relativeTo: baseURL)?.absoluteURL
        }
        if var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            comps.path = "/favicon.ico"
            comps.query = nil
            comps.fragment = nil
            if let fallback = comps.url { candidates.append(fallback) }
        }
        for candidate in candidates.prefix(3) {
            if let data = try? await fetchImageData(session: session, url: candidate) {
                meta.faviconData = data
                break
            }
        }
        return meta
    }

    private static func fetchImageData(session: URLSession, url: URL) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
        guard data.count > 16, data.count < 2_000_000 else { return nil }
        // Reject HTML error pages served with 200.
        if data.first == UInt8(ascii: "<") { return nil }
        return data
    }

    /// What we scrape out of a page's <head>. Internal (not private) so the
    /// scraping is unit-testable without a network round-trip.
    struct ParsedHead: Sendable {
        var title: String?
        var description: String?
        var iconHrefs: [String] = []
    }

    static func parse(html: String) -> ParsedHead {
        var head = ParsedHead()
        if let raw = firstCapture("<title[^>]*>(.*?)</title>", in: html) {
            head.title = clean(raw)
        }
        // og:title beats an empty <title>
        if head.title?.isEmpty != false, let og = metaContent(in: html, keys: ["og:title"]) {
            head.title = clean(og)
        }
        head.description = metaContent(in: html, keys: ["description", "og:description"])
            .map(clean)
        head.iconHrefs = iconLinks(in: html)
        return head
    }

    // MARK: HTML scraping helpers (regex-based, good enough for metadata)

    private static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func clean(_ s: String) -> String {
        decodeEntities(s)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, options: [], range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        firstCapture("\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", in: tag)
            ?? firstCapture("\\b\(name)\\s*=\\s*([^\\s\"'>]+)", in: tag)
    }

    /// content= of the first <meta> whose name= or property= matches a key,
    /// tried in key order.
    private static func metaContent(in html: String, keys: [String]) -> String? {
        let tags = allMatches("<meta\\b[^>]*>", in: html)
        for key in keys {
            for tag in tags {
                let ident = attribute("name", in: tag) ?? attribute("property", in: tag)
                guard ident?.lowercased() == key else { continue }
                if let content = attribute("content", in: tag), !content.isEmpty {
                    return content
                }
            }
        }
        return nil
    }

    private static func iconLinks(in html: String) -> [String] {
        allMatches("<link\\b[^>]*>", in: html).compactMap { tag in
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.split(separator: " ").contains(where: { $0 == "icon" || $0 == "shortcut" }),
                  let href = attribute("href", in: tag), !href.isEmpty
            else { return nil }
            return href
        }
    }

    // MARK: Entity decoding

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ndash": "–", "mdash": "—", "hellip": "…",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "copy": "©", "reg": "®", "trade": "™", "middot": "·", "bull": "•", "raquo": "»",
        "laquo": "«", "times": "×", "eacute": "é", "egrave": "è", "agrave": "à", "uuml": "ü",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            guard let amp = s[i...].firstIndex(of: "&") else {
                result += s[i...]
                break
            }
            result += s[i..<amp]
            let tail = s[amp...]
            if let semi = tail.prefix(12).firstIndex(of: ";"), semi > amp {
                let name = String(s[s.index(after: amp)..<semi])
                if let decoded = decodeEntity(name) {
                    result += decoded
                    i = s.index(after: semi)
                    continue
                }
            }
            result.append("&")
            i = s.index(after: amp)
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let numPart = name.dropFirst()
            let value: UInt32?
            if numPart.hasPrefix("x") || numPart.hasPrefix("X") {
                value = UInt32(numPart.dropFirst(), radix: 16)
            } else {
                value = UInt32(numPart)
            }
            guard let v = value, let scalar = Unicode.Scalar(v) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[name.lowercased()]
    }
}
