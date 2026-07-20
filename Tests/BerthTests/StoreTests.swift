import XCTest

@testable import Berth

// setUp/tearDown override nonisolated XCTestCase methods, so the class stays
// nonisolated and only the test methods hop onto the main actor (where
// BookmarkStore lives). XCTest runs everything on the main thread anyway.
final class StoreTests: XCTestCase {
    private nonisolated(unsafe) var storeURL: URL!
    private nonisolated(unsafe) var savedSortPref: String?

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("berth-tests-\(UUID().uuidString).json")
        // The store persists its sort order to UserDefaults; don't clobber
        // the real preference from tests.
        savedSortPref = UserDefaults.standard.string(forKey: "berth.sortOrder")
    }

    override func tearDown() {
        if let savedSortPref {
            UserDefaults.standard.set(savedSortPref, forKey: "berth.sortOrder")
        } else {
            UserDefaults.standard.removeObject(forKey: "berth.sortOrder")
        }
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    @MainActor
    private func makeStore() -> BookmarkStore {
        let store = BookmarkStore(storeURL: storeURL, fetchesMetadata: false)
        store.sortOrder = .dateAdded
        return store
    }

    // MARK: - Adding & duplicate detection

    @MainActor func testAddNewInsertsAtTopAndSelects() {
        let store = makeStore()
        store.addNew(urlString: "https://example.com/a")
        let b = store.addNew(urlString: "https://example.com/b")
        XCTAssertEqual(store.bookmarks.map(\.url), ["https://example.com/b", "https://example.com/a"])
        XCTAssertEqual(store.selectedID, b.id)
    }

    @MainActor func testAddOrSelectDeduplicatesByNormalizedURL() {
        let store = makeStore()
        let first = store.addNew(urlString: "https://www.example.com/Article")
        // Same page, different trailing slash + fragment: must not add a duplicate.
        let second = store.addOrSelect(urlString: "https://www.example.com/Article/#comments")
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.selectedID, first.id)
    }

    @MainActor func testFindExistingNormalizes() {
        let store = makeStore()
        store.addNew(urlString: "HTTPS://Example.com/x/")
        XCTAssertNotNil(store.findExisting(urlString: "https://example.com/x"))
        XCTAssertNil(store.findExisting(urlString: "https://example.com/y"))
    }

    // MARK: - Delete & undo

    @MainActor func testDeleteThenUndoRestoresOrder() {
        let store = makeStore()
        let a = store.addNew(urlString: "https://example.com/a")
        let b = store.addNew(urlString: "https://example.com/b")
        let c = store.addNew(urlString: "https://example.com/c")
        // Order is [c, b, a]; delete the middle one.
        store.delete(ids: [b.id])
        XCTAssertEqual(store.bookmarks.map(\.id), [c.id, a.id])
        XCTAssertTrue(store.canUndoDelete)

        store.undoDelete()
        XCTAssertEqual(store.bookmarks.map(\.id), [c.id, b.id, a.id])
        XCTAssertEqual(store.selectedID, b.id)
        XCTAssertFalse(store.canUndoDelete)
    }

    @MainActor func testDeleteClearsSelectionOfDeleted() {
        let store = makeStore()
        let a = store.addNew(urlString: "https://example.com/a")
        store.delete(ids: [a.id])
        XCTAssertNil(store.selectedID)
        XCTAssertTrue(store.bookmarks.isEmpty)
    }

    @MainActor func testMultiDeleteUndoesAsOneBatch() {
        let store = makeStore()
        let a = store.addNew(urlString: "https://example.com/a")
        let b = store.addNew(urlString: "https://example.com/b")
        store.delete(ids: [a.id, b.id])
        XCTAssertTrue(store.bookmarks.isEmpty)
        store.undoDelete()
        XCTAssertEqual(Set(store.bookmarks.map(\.id)), [a.id, b.id])
    }

    // MARK: - Tags

    @MainActor func testTagCountsAreCaseInsensitive() {
        let store = makeStore()
        store.addNew(urlString: "https://example.com/1", tags: ["Swift", "macos"])
        store.addNew(urlString: "https://example.com/2", tags: ["swift"])
        let counts = Dictionary(
            uniqueKeysWithValues: store.tagCounts.map { ($0.tag.lowercased(), $0.count) })
        XCTAssertEqual(counts, ["swift": 2, "macos": 1])
    }

    // MARK: - Filtering & sorting

    @MainActor func testSidebarAndSearchFilters() {
        let store = makeStore()
        let fav = store.addNew(urlString: "https://example.com/fav", title: "Starred", tags: ["keep"])
        store.toggleFavorite(fav.id)
        store.addNew(urlString: "https://example.com/plain", title: "Plain")

        store.sidebarSelection = [.favorites]
        XCTAssertEqual(store.visibleBookmarks.map(\.id), [fav.id])

        store.sidebarSelection = [.untagged]
        XCTAssertEqual(store.visibleBookmarks.map(\.title), ["Plain"])

        store.sidebarSelection = [.tag("KEEP")]  // tag filter is case-insensitive
        XCTAssertEqual(store.visibleBookmarks.map(\.id), [fav.id])

        store.sidebarSelection = [.all]
        store.searchText = "starred"
        XCTAssertEqual(store.visibleBookmarks.map(\.id), [fav.id])
    }

    @MainActor func testCombinedTagFiltersRequireAllTags() {
        let store = makeStore()
        let both = store.addNew(urlString: "https://example.com/1", tags: ["a", "b"])
        store.addNew(urlString: "https://example.com/2", tags: ["a"])
        store.sidebarSelection = [.tag("a"), .tag("b")]
        XCTAssertEqual(store.visibleBookmarks.map(\.id), [both.id])
    }

    @MainActor func testSortByTitleAndDomain() {
        let store = makeStore()
        store.addNew(urlString: "https://zeta.org/1", title: "Beta")
        store.addNew(urlString: "https://alpha.com/2", title: "alpha")

        store.sortOrder = .title
        XCTAssertEqual(store.visibleBookmarks.map(\.title), ["alpha", "Beta"])

        store.sortOrder = .domain
        XCTAssertEqual(store.visibleBookmarks.map(\.displayHost), ["alpha.com", "zeta.org"])
    }

    // MARK: - Persistence

    @MainActor func testSaveNowThenReloadRoundTrips() {
        var addedID: Bookmark.ID?
        do {
            let store = makeStore()
            let b = store.addNew(urlString: "https://example.com/persist", tags: ["disk"])
            store.update(b.id) { $0.note = "survives restarts" }
            store.toggleFavorite(b.id)
            store.saveNow()
            addedID = b.id
        }

        let reloaded = BookmarkStore(storeURL: storeURL, fetchesMetadata: false)
        XCTAssertEqual(reloaded.bookmarks.count, 1)
        let b = reloaded.bookmarks[0]
        XCTAssertEqual(b.id, addedID)
        XCTAssertEqual(b.url, "https://example.com/persist")
        XCTAssertEqual(b.tags, ["disk"])
        XCTAssertEqual(b.note, "survives restarts")
        XCTAssertTrue(b.isFavorite)
    }

    @MainActor func testMissingStoreFileYieldsEmptyStore() {
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)
    }

    @MainActor func testCorruptStoreFileYieldsEmptyStoreWithoutCrashing() throws {
        try Data("not json{{".utf8).write(to: storeURL)
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)
    }
}
