import XCTest

@testable import Berth

final class BookmarkTests: XCTestCase {
    // MARK: - Display helpers

    func testDisplayHostStripsWWW() {
        XCTAssertEqual(Bookmark(url: "https://www.example.com/x").displayHost, "example.com")
        XCTAssertEqual(Bookmark(url: "https://blog.example.com").displayHost, "blog.example.com")
    }

    func testDisplayTitleFallsBackToHostThenURL() {
        XCTAssertEqual(
            Bookmark(url: "https://example.com", title: "A Page").displayTitle, "A Page")
        XCTAssertEqual(
            Bookmark(url: "https://www.example.com", title: "  \n ").displayTitle, "example.com")
        // No parseable host: fall all the way back to the raw string.
        XCTAssertEqual(Bookmark(url: "not a url").displayTitle, "not a url")
    }

    func testInitComputesNormalizedURL() {
        let b = Bookmark(url: "HTTPS://Example.com/Path/#frag")
        XCTAssertEqual(b.normalizedURL, "https://example.com/Path")
    }

    // MARK: - Search matching

    func testMatchesSearchesAllFields() {
        let b = Bookmark(
            url: "https://example.com/swift-concurrency",
            title: "Concurrency Guide",
            pageDescription: "All about actors",
            note: "read before refactor",
            tags: ["Swift", "reference"])

        XCTAssertTrue(b.matches(query: "concurrency guide"))  // title, case-insensitive
        XCTAssertTrue(b.matches(query: "example.com"))        // url
        XCTAssertTrue(b.matches(query: "ACTORS"))             // description
        XCTAssertTrue(b.matches(query: "refactor"))           // note
        XCTAssertTrue(b.matches(query: "swift"))              // tag
        XCTAssertFalse(b.matches(query: "python"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(Bookmark(url: "https://example.com").matches(query: ""))
    }

    // MARK: - Tolerant decoding

    func testDecodesMinimalJSON() throws {
        let json = Data(#"{"url": "https://example.com/x"}"#.utf8)
        let b = try JSONDecoder().decode(Bookmark.self, from: json)
        XCTAssertEqual(b.url, "https://example.com/x")
        XCTAssertEqual(b.normalizedURL, "https://example.com/x")
        XCTAssertEqual(b.title, "")
        XCTAssertEqual(b.tags, [])
        XCTAssertFalse(b.isFavorite)
        XCTAssertEqual(b.metadataState, .done)
    }

    func testInterruptedFetchDecodesAsPending() throws {
        let json = Data(#"{"url": "https://example.com", "metadataState": "fetching"}"#.utf8)
        let b = try JSONDecoder().decode(Bookmark.self, from: json)
        XCTAssertEqual(b.metadataState, .pending)
    }

    func testMissingURLFailsToDecode() {
        let json = Data(#"{"title": "no url here"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Bookmark.self, from: json))
    }

    func testRoundTripPreservesFields() throws {
        let original = Bookmark(
            url: "https://example.com/x",
            title: "Title",
            pageDescription: "Desc",
            note: "Note",
            tags: ["a", "b"],
            isFavorite: true,
            metadataState: .failed)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Bookmark.self, from: encoder.encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.pageDescription, original.pageDescription)
        XCTAssertEqual(decoded.note, original.note)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.isFavorite, original.isFavorite)
        XCTAssertEqual(decoded.metadataState, original.metadataState)
    }
}
