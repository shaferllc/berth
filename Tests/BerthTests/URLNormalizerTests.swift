import XCTest

@testable import Berth

final class URLNormalizerTests: XCTestCase {
    // MARK: - normalize

    func testLowercasesSchemeAndHostOnly() {
        XCTAssertEqual(
            URLNormalizer.normalize("HTTPS://Example.COM/Some/Path"),
            "https://example.com/Some/Path")
    }

    func testStripsFragment() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/page#section-2"),
            "https://example.com/page")
    }

    func testStripsTrailingSlashes() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/a/b///"),
            "https://example.com/a/b")
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/"),
            "https://example.com")
    }

    func testDropsDefaultPorts() {
        XCTAssertEqual(
            URLNormalizer.normalize("http://example.com:80/x"),
            "http://example.com/x")
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com:443/x"),
            "https://example.com/x")
    }

    func testKeepsNonDefaultPorts() {
        XCTAssertEqual(
            URLNormalizer.normalize("http://example.com:8080/x"),
            "http://example.com:8080/x")
        // https on port 80 is unusual but not a default pair — keep it.
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com:80/x"),
            "https://example.com:80/x")
    }

    func testKeepsQuery() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/search?q=Swift#frag"),
            "https://example.com/search?q=Swift")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            URLNormalizer.normalize("  https://example.com  \n"),
            "https://example.com")
    }

    func testNonURLTextIsHandledGracefully() {
        // Modern Foundation parses almost anything (percent-encoding as
        // needed); what matters is the result is stable — normalizing twice
        // changes nothing — so duplicate detection stays consistent.
        let once = URLNormalizer.normalize("Not A URL At All^^")
        XCTAssertFalse(once.isEmpty)
        XCTAssertEqual(URLNormalizer.normalize(once), once)
    }

    func testEquivalentURLsNormalizeIdentically() {
        let variants = [
            "https://www.Example.com/Article/",
            "https://www.example.com:443/Article",
            "https://www.example.com/Article#comments",
        ]
        let normalized = Set(variants.map(URLNormalizer.normalize))
        XCTAssertEqual(normalized.count, 1)
    }

    // MARK: - completeURL

    func testCompletesBareDomain() {
        XCTAssertEqual(
            URLNormalizer.completeURL(from: "example.com/x")?.absoluteString,
            "https://example.com/x")
    }

    func testKeepsExplicitScheme() {
        XCTAssertEqual(
            URLNormalizer.completeURL(from: "http://example.com")?.absoluteString,
            "http://example.com")
    }

    func testAcceptsLocalhost() {
        XCTAssertEqual(
            URLNormalizer.completeURL(from: "localhost:8080/dev")?.absoluteString,
            "https://localhost:8080/dev")
    }

    func testRejectsNonWebInput() {
        XCTAssertNil(URLNormalizer.completeURL(from: ""))
        XCTAssertNil(URLNormalizer.completeURL(from: "   "))
        XCTAssertNil(URLNormalizer.completeURL(from: "hello world"))
        XCTAssertNil(URLNormalizer.completeURL(from: "just-some-words"))
        XCTAssertNil(URLNormalizer.completeURL(from: "ftp://example.com/file"))
        XCTAssertNil(URLNormalizer.completeURL(from: "file:///etc/passwd"))
    }
}
