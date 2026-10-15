import XCTest
@testable import WorkScreenTimeCore

final class PhotoStoreTests: XCTestCase {
    private var directory: URL!
    private var sourceDirectory: URL!
    private var store: PhotoStore!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("Photos", isDirectory: true)
        sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        store = PhotoStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func makeSource(_ name: String) throws -> URL {
        let url = sourceDirectory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    func testListIsEmptyWhenDirectoryIsMissing() {
        XCTAssertEqual(store.list(), [])
    }

    func testAddCopiesSupportedImagesAndSkipsOthers() throws {
        let png = try makeSource("beach.PNG")
        let text = try makeSource("notes.txt")

        let added = try store.add([png, text])

        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(names(store.list()), names(added))
        XCTAssertEqual(try Data(contentsOf: added[0]), Data("beach.PNG".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "original is kept")
    }

    func testListKeepsInsertionOrderAcrossAdds() throws {
        let first = try store.add([try makeSource("a.jpg")], now: Date(timeIntervalSince1970: 1_000))
        let second = try store.add([try makeSource("b.jpg"), try makeSource("c.jpg")], now: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(names(store.list()), names(first + second))
    }

    func testRemoveDeletesStoredPhotoButIgnoresOutsideFiles() throws {
        let outside = try makeSource("keep.jpg")
        let added = try store.add([outside])

        try store.remove(outside)
        try store.remove(added[0])

        XCTAssertEqual(store.list(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
