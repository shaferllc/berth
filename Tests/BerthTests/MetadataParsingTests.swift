import XCTest

@testable import Berth

final class MetadataParsingTests: XCTestCase {
    // MARK: - parse(html:)

    func testParsesTitleAndDecodesEntities() {
        let head = PageMetadata.parse(html: "<html><head><title>Tips &amp; Tricks</title></head>")
        XCTAssertEqual(head.title, "Tips & Tricks")
    }

    func testCollapsesWhitespaceInTitle() {
        let head = PageMetadata.parse(html: "<title>\n  Hello\n\t World  </title>")
        XCTAssertEqual(head.title, "Hello World")
    }

    func testOGTitleFillsInWhenTitleTagIsEmpty() {
        let html = """
            <title></title>
            <meta property="og:title" content="From OpenGraph">
            """
        XCTAssertEqual(PageMetadata.parse(html: html).title, "From OpenGraph")
    }

    func testTitleTagBeatsOGTitle() {
        let html = """
            <title>Real Title</title>
            <meta property="og:title" content="OG Title">
            """
        XCTAssertEqual(PageMetadata.parse(html: html).title, "Real Title")
    }

    func testMetaDescriptionPreferredOverOGDescription() {
        let html = """
            <meta property="og:description" content="og desc">
            <meta name="description" content="plain desc">
            """
        XCTAssertEqual(PageMetadata.parse(html: html).description, "plain desc")
    }

    func testOGDescriptionUsedWhenNoPlainDescription() {
        let html = #"<meta property="og:description" content="og desc">"#
        XCTAssertEqual(PageMetadata.parse(html: html).description, "og desc")
    }

    func testFindsIconLinks() {
        let html = """
            <link rel="stylesheet" href="/style.css">
            <link rel="icon" href="/favicon-32.png">
            <link rel="SHORTCUT ICON" href="legacy.ico">
            <link rel="apple-touch-icon" href="/touch.png">
            """
        let head = PageMetadata.parse(html: html)
        XCTAssertEqual(head.iconHrefs, ["/favicon-32.png", "legacy.ico"])
    }

    func testEmptyHTMLYieldsNothing() {
        let head = PageMetadata.parse(html: "<p>no head content</p>")
        XCTAssertNil(head.title)
        XCTAssertNil(head.description)
        XCTAssertEqual(head.iconHrefs, [])
    }

    func testUnquotedAttributesStillParse() {
        let html = "<meta name=description content=hello>"
        XCTAssertEqual(PageMetadata.parse(html: html).description, "hello")
    }

    // MARK: - decodeEntities

    func testDecodesNamedEntities() {
        XCTAssertEqual(
            PageMetadata.decodeEntities("Fish &amp; Chips &mdash; &pound;5"),
            "Fish & Chips — &pound;5")  // unknown entity left intact
        XCTAssertEqual(PageMetadata.decodeEntities("&lt;b&gt;"), "<b>")
        XCTAssertEqual(PageMetadata.decodeEntities("&ldquo;hi&rdquo;"), "\u{201C}hi\u{201D}")
    }

    func testDecodesNumericEntities() {
        XCTAssertEqual(PageMetadata.decodeEntities("&#65;&#66;"), "AB")
        XCTAssertEqual(PageMetadata.decodeEntities("&#x41;&#X42;"), "AB")
        XCTAssertEqual(PageMetadata.decodeEntities("&#8212;"), "—")
    }

    func testLeavesInvalidEntitiesAlone() {
        XCTAssertEqual(PageMetadata.decodeEntities("&bogus;"), "&bogus;")
        XCTAssertEqual(PageMetadata.decodeEntities("AT&T"), "AT&T")
        XCTAssertEqual(PageMetadata.decodeEntities("trailing &"), "trailing &")
        XCTAssertEqual(PageMetadata.decodeEntities("&#xZZ;"), "&#xZZ;")
    }

    func testStringWithoutAmpersandPassesThrough() {
        XCTAssertEqual(PageMetadata.decodeEntities("plain text"), "plain text")
    }
}
