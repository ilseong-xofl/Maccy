import AppKit
import CryptoKit
import SQLite3
import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class LinkPreviewSnapshotTests: XCTestCase {
  private let sourceURL = URL(string: "https://example.com/copied")!
  private let videoURL = URL(string: "https://youtu.be/abcdefghijk?t=42")!

  func testRoundTripKeepsCopiedAndResolvedURLsSeparate() throws {
    let resolvedURL = URL(string: "https://example.com/resolved")!
    let data = try encodedPreview(url: resolvedURL, title: "A page")
    XCTAssertTrue(data.starts(with: Data("bplist00".utf8)))
    XCTAssertEqual(LinkPreviewSnapshot.sourceURL(in: data), sourceURL)
    guard case .preview(let preview) = LinkPreviewSnapshot.decode(data, sourceURL: sourceURL) else {
      return XCTFail("Expected a saved preview")
    }
    XCTAssertEqual(preview.url, resolvedURL)
    XCTAssertEqual(preview.title, "A page")
    XCTAssertNil(preview.image)
  }

  func testRoundTripPreservesEveryFailure() throws {
    for failure in [LinkPreviewFailure.notFound, .unavailable, .connectionFailure] {
      let data = try XCTUnwrap(LinkPreviewSnapshot.encode(.failure(failure), sourceURL: sourceURL))
      guard case .failure(let decoded) = LinkPreviewSnapshot.decode(data, sourceURL: sourceURL) else {
        return XCTFail("Expected a saved failure")
      }
      XCTAssertEqual(decoded, failure)
    }
  }

  func testDifferentSourceURLCannotReuseSnapshot() throws {
    let data = try encodedPreview()
    XCTAssertNil(LinkPreviewSnapshot.decode(data, sourceURL: URL(string: "https://example.com/other")!))
  }

  func testMalformedAndFutureRecordsAreRejected() throws {
    XCTAssertNil(LinkPreviewSnapshot.decode(Data("not a property list".utf8), sourceURL: sourceURL))
    XCTAssertNil(LinkPreviewSnapshot.sourceURL(in: Data([0, 1, 2])))
    let future = try modifiedRecord { $0["version"] = 2 }
    XCTAssertNil(LinkPreviewSnapshot.decode(future, sourceURL: sourceURL))
    XCTAssertNil(LinkPreviewSnapshot.sourceURL(in: future))
  }

  func testUnknownFailureAndConflictingRecordAreRejected() throws {
    let unknown = try modifiedRecord { $0["failure"] = "newFailure" }
    XCTAssertNil(LinkPreviewSnapshot.decode(unknown, sourceURL: sourceURL))
    let conflicting = try modifiedRecord { $0["failure"] = "notFound" }
    XCTAssertNil(LinkPreviewSnapshot.decode(conflicting, sourceURL: sourceURL))
  }

  func testInvalidResolvedURLIsRejected() throws {
    let data = try modifiedRecord { $0["previewURL"] = "file:///tmp/image.png" }
    XCTAssertNil(LinkPreviewSnapshot.decode(data, sourceURL: sourceURL))
  }

  func testTitleIsLimitedWithoutBreakingUnicode() throws {
    let title = String(repeating: "가👩🏽‍💻", count: 3_000)
    let data = try encodedPreview(title: title)
    guard case .preview(let preview) = LinkPreviewSnapshot.decode(data, sourceURL: sourceURL) else {
      return XCTFail("Expected a saved preview")
    }
    XCTAssertLessThanOrEqual(preview.title.count, LinkPreviewSnapshot.maximumTitleCharacters)
    XCTAssertTrue(title.hasPrefix(preview.title))
  }

  func testCombiningCharacterTitleCannotExceedRecordBudget() throws {
    let title = "a" + String(repeating: "\u{0301}", count: 200_000)
    let data = try encodedPreview(title: title)
    XCTAssertLessThanOrEqual(data.count, LinkPreviewSnapshot.maximumRecordBytes)
    XCTAssertNotNil(LinkPreviewSnapshot.decode(data, sourceURL: sourceURL))
  }

  func testThumbnailBoundsAndAspectRatioArePreserved() throws {
    let image = try patternedImage(width: 2_400, height: 1_600)
    let result = LinkPreviewResult.preview(ClipboardLinkPreview(url: sourceURL, title: "Image", image: image))
    let data = try XCTUnwrap(LinkPreviewSnapshot.encode(result, sourceURL: sourceURL))
    let properties = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let thumbnail = try XCTUnwrap(properties["thumbnail"] as? Data)
    XCTAssertLessThanOrEqual(thumbnail.count, LinkPreviewSnapshot.maximumThumbnailBytes)
    XCTAssertLessThanOrEqual(data.count, LinkPreviewSnapshot.maximumRecordBytes)
    guard case .preview(let preview) = LinkPreviewSnapshot.decode(data, sourceURL: sourceURL) else {
      return XCTFail("Expected a saved image preview")
    }
    let decoded = try XCTUnwrap(preview.image)
    XCTAssertLessThanOrEqual(decoded.size.width, CGFloat(LinkPreviewSnapshot.maximumImageDimension))
    XCTAssertLessThanOrEqual(decoded.size.height, CGFloat(LinkPreviewSnapshot.maximumImageDimension))
    XCTAssertEqual(decoded.size.width / decoded.size.height, 1.5, accuracy: 0.01)
  }

  func testUnencodableImageStillPersistsTitle() throws {
    let result = LinkPreviewResult.preview(ClipboardLinkPreview(
      url: sourceURL, title: "No image representation", image: NSImage(size: .zero)
    ))
    let data = try XCTUnwrap(LinkPreviewSnapshot.encode(result, sourceURL: sourceURL))
    guard case .preview(let preview) = LinkPreviewSnapshot.decode(data, sourceURL: sourceURL) else {
      return XCTFail("Expected a title-only preview")
    }
    XCTAssertEqual(preview.title, "No image representation")
    XCTAssertNil(preview.image)
  }

  func testCorruptAndOversizedThumbnailsAreRejected() throws {
    let corrupt = try modifiedRecord { $0["thumbnail"] = Data("invalid image".utf8) }
    XCTAssertNil(LinkPreviewSnapshot.decode(corrupt, sourceURL: sourceURL))
    let oversized = try modifiedRecord {
      $0["thumbnail"] = Data(repeating: 0, count: LinkPreviewSnapshot.maximumThumbnailBytes + 1)
    }
    XCTAssertNil(LinkPreviewSnapshot.decode(oversized, sourceURL: sourceURL))
  }

  func testOversizedRecordIsRejected() {
    let data = Data(repeating: 0, count: LinkPreviewSnapshot.maximumRecordBytes + 1)
    XCTAssertNil(LinkPreviewSnapshot.decode(data, sourceURL: sourceURL))
    XCTAssertNil(LinkPreviewSnapshot.sourceURL(in: data))
  }

  func testExceptionallyLongURLDoesNotCreateAnUnboundedRecord() {
    let url = URL(string: "https://example.com/" + String(repeating: "a", count: 400_000))!
    XCTAssertNil(LinkPreviewSnapshot.encode(.failure(.unavailable), sourceURL: url))
  }

  func testModelUsesOriginalURLInsteadOfDisplayAlias() {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(sourceURL.absoluteString.utf8))
    ])
    item.title = "My bookmark"
    XCTAssertEqual(item.linkPreviewSourceURL, sourceURL)
    XCTAssertNil(item.linkPreviewSnapshot)
  }

  func testModelExcludesCopiedFilesEvenWhenTextContainsURL() {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(sourceURL.absoluteString.utf8)),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue, value: Data("file:///tmp/preview.png".utf8)
      )
    ])
    XCTAssertNil(item.linkPreviewSourceURL)
  }

  func testNewYouTubeVideoSuccessIsAlreadyMarked() throws {
    let data = try XCTUnwrap(LinkPreviewSnapshot.encode(
      .preview(ClipboardLinkPreview(url: videoURL, title: "Video title", image: nil)), sourceURL: videoURL
    ))
    let properties = try snapshotProperties(data)
    XCTAssertEqual(properties["version"] as? Int, 1)
    XCTAssertEqual(properties["youtubeTitleVersion"] as? Int, 1)
    XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(data, sourceURL: videoURL))
  }

  func testLegacyYouTubeCorrectionPreservesThumbnailBytesAndURLs() throws {
    let image = try patternedImage(width: 160, height: 90)
    let legacy = try legacyYouTubeSnapshot(image: image)
    XCTAssertTrue(LinkPreviewSnapshot.needsYouTubeTitleRepair(legacy, sourceURL: videoURL))
    let corrected = try XCTUnwrap(LinkPreviewSnapshot.markYouTubeTitleRepaired(
      legacy, sourceURL: videoURL, title: "  Actual video title\n"
    ))
    let before = try snapshotProperties(legacy)
    let after = try snapshotProperties(corrected)
    let thumbnail = try XCTUnwrap(before["thumbnail"] as? Data)
    XCTAssertEqual(after["thumbnail"] as? Data, thumbnail)
    XCTAssertEqual(after["sourceURL"] as? String, before["sourceURL"] as? String)
    XCTAssertEqual(after["previewURL"] as? String, before["previewURL"] as? String)
    XCTAssertEqual(after["title"] as? String, "Actual video title")
    XCTAssertEqual(after["youtubeTitleVersion"] as? Int, 1)
    XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(corrected, sourceURL: videoURL))
  }

  func testUnsuccessfulTitleCorrectionKeepsTitleAndMarksCompletedAttempt() throws {
    let legacy = try legacyYouTubeSnapshot()
    for title in [nil, " \n\t"] as [String?] {
      let corrected = try XCTUnwrap(LinkPreviewSnapshot.markYouTubeTitleRepaired(
        legacy, sourceURL: videoURL, title: title
      ))
      let properties = try snapshotProperties(corrected)
      XCTAssertEqual(properties["title"] as? String, "Legacy channel title")
      XCTAssertEqual(properties["youtubeTitleVersion"] as? Int, 1)
      XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(corrected, sourceURL: videoURL))
    }
  }

  func testCorrectedVideoTitleRemainsBounded() throws {
    let legacy = try legacyYouTubeSnapshot()
    let corrected = try XCTUnwrap(LinkPreviewSnapshot.markYouTubeTitleRepaired(
      legacy, sourceURL: videoURL, title: String(repeating: "가", count: 5_000)
    ))
    guard case .preview(let preview) = LinkPreviewSnapshot.decode(corrected, sourceURL: videoURL) else {
      return XCTFail("Expected a corrected preview")
    }
    XCTAssertEqual(preview.title.count, LinkPreviewSnapshot.maximumTitleCharacters)
    XCTAssertLessThanOrEqual(corrected.count, LinkPreviewSnapshot.maximumRecordBytes)
  }

  func testSavedFailuresAndNonVideoPagesDoNotNeedTitleCorrection() throws {
    let failure = try XCTUnwrap(LinkPreviewSnapshot.encode(.failure(.notFound), sourceURL: videoURL))
    let ordinary = try encodedPreview()
    let channelURL = URL(string: "https://www.youtube.com/@example")!
    let channel = try XCTUnwrap(LinkPreviewSnapshot.encode(
      .preview(ClipboardLinkPreview(url: channelURL, title: "Channel", image: nil)), sourceURL: channelURL
    ))
    for (data, url) in [(failure, videoURL), (ordinary, sourceURL), (channel, channelURL)] {
      XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(data, sourceURL: url))
      XCTAssertNil(LinkPreviewSnapshot.markYouTubeTitleRepaired(data, sourceURL: url, title: "Unexpected"))
      XCTAssertNil(try snapshotProperties(data)["youtubeTitleVersion"])
    }
  }

  func testFutureTitleCorrectionVersionIsPreserved() throws {
    var properties = try snapshotProperties(legacyYouTubeSnapshot())
    properties["youtubeTitleVersion"] = 2
    let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
    XCTAssertNotNil(LinkPreviewSnapshot.decode(data, sourceURL: videoURL))
    XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(data, sourceURL: videoURL))
    XCTAssertNil(LinkPreviewSnapshot.markYouTubeTitleRepaired(data, sourceURL: videoURL, title: "Unexpected"))
  }

  func testOldTitleCorrectionVersionAndInvalidSources() throws {
    var properties = try snapshotProperties(legacyYouTubeSnapshot())
    properties["youtubeTitleVersion"] = 0
    let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
    XCTAssertTrue(LinkPreviewSnapshot.needsYouTubeTitleRepair(data, sourceURL: videoURL))
    let otherVideo = URL(string: "https://youtu.be/ABCDEFGHIJK")!
    XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(data, sourceURL: otherVideo))
    XCTAssertNil(LinkPreviewSnapshot.markYouTubeTitleRepaired(data, sourceURL: otherVideo, title: "Unexpected"))
    XCTAssertFalse(LinkPreviewSnapshot.needsYouTubeTitleRepair(Data([0, 1, 2]), sourceURL: videoURL))
  }

  func testOptionalPrechangeStoreMigratesWithoutLosingHistory() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let fixture = environment["MACCY_MIGRATION_STORE"], !fixture.isEmpty,
          !fixture.contains("$(") else {
      throw XCTSkip("Set MACCY_MIGRATION_STORE to validate a copy of a pre-change history store")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaccyMigration-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Storage.sqlite")
    // The provided fixture is a consistent SQLite backup. Only this temporary copy is migrated.
    try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: storeURL)
    let originalCounts = try autoreleasepool { try migrateAndSaveFixture(at: storeURL) }
    if let expected = environment["MACCY_MIGRATION_EXPECTED_ITEMS"].flatMap(Int.init) {
      XCTAssertEqual(originalCounts.items, expected)
    }
    if let expected = environment["MACCY_MIGRATION_EXPECTED_CONTENTS"].flatMap(Int.init) {
      XCTAssertEqual(originalCounts.contents, expected)
    }
    try autoreleasepool {
      let container = try ModelContainer(
        for: HistoryItem.self, configurations: ModelConfiguration(url: storeURL)
      )
      let items = try container.mainContext.fetch(FetchDescriptor<HistoryItem>())
      XCTAssertEqual(items.count, originalCounts.items)
      let contentsCount = try container.mainContext.fetchCount(FetchDescriptor<HistoryItemContent>())
      XCTAssertEqual(contentsCount, originalCounts.contents)
      let snapshots = items.compactMap(\.linkPreviewSnapshot)
      XCTAssertEqual(snapshots.count, 1)
      let data = try XCTUnwrap(snapshots.first)
      let savedURL = try XCTUnwrap(LinkPreviewSnapshot.sourceURL(in: data))
      guard case .failure(.unavailable) = LinkPreviewSnapshot.decode(data, sourceURL: savedURL) else {
        return XCTFail("The added snapshot must survive reopening the migrated store")
      }
    }
  }

  private func migrateAndSaveFixture(at storeURL: URL) throws -> (items: Int, contents: Int) {
    let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: storeURL))
    let items = try container.mainContext.fetch(FetchDescriptor<HistoryItem>())
    let contentsCount = try container.mainContext.fetchCount(FetchDescriptor<HistoryItemContent>())
    XCTAssertTrue(items.allSatisfy { $0.linkPreviewSnapshot == nil })
    let target = try XCTUnwrap(items.first)
    target.linkPreviewSnapshot = LinkPreviewSnapshot.encode(
      .failure(.unavailable), sourceURL: target.linkPreviewSourceURL ?? sourceURL
    )
    try container.mainContext.save()
    return (items.count, contentsCount)
  }

  private func encodedPreview(url: URL? = nil, title: String = "Example") throws -> Data {
    try XCTUnwrap(LinkPreviewSnapshot.encode(
      .preview(ClipboardLinkPreview(url: url ?? sourceURL, title: title, image: nil)), sourceURL: sourceURL
    ))
  }

  private func legacyYouTubeSnapshot(image: NSImage? = nil) throws -> Data {
    let resolvedURL = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
    let data = try XCTUnwrap(LinkPreviewSnapshot.encode(.preview(ClipboardLinkPreview(
      url: resolvedURL, title: "Legacy channel title", image: image
    )), sourceURL: videoURL))
    var properties = try snapshotProperties(data)
    properties.removeValue(forKey: "youtubeTitleVersion")
    return try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
  }

  private func snapshotProperties(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  private func modifiedRecord(_ modify: (inout [String: Any]) -> Void) throws -> Data {
    var properties = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: encodedPreview(), format: nil) as? [String: Any]
    )
    modify(&properties)
    return try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
  }

  private func patternedImage(width: Int, height: Int) throws -> NSImage {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
      samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: width * 3, bitsPerPixel: 24
    ))
    let bytes = try XCTUnwrap(bitmap.bitmapData)
    var random: UInt32 = 42
    for index in 0..<(bitmap.bytesPerRow * height) {
      random = random &* 1_664_525 &+ 1_013_904_223
      bytes[index] = UInt8(truncatingIfNeeded: random >> 24)
    }
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
  }
}

@MainActor
final class FavoritesPersistenceTests: XCTestCase {
  func testOptionalPrechangeStorePreservesHistoryAndSavesFavorite() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let fixture = environment["MACCY_FAVORITES_MIGRATION_STORE"], !fixture.isEmpty,
          !fixture.contains("$(") else {
      throw XCTSkip("Set MACCY_FAVORITES_MIGRATION_STORE to validate a copy of a pre-favorites store")
    }
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Storage.sqlite")
    // Supply a consistent standalone SQLite backup. The original is never opened by SwiftData.
    try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: storeURL)
    let original = try storedHistory(at: storeURL)
    if let expected = environment["MACCY_FAVORITES_MIGRATION_EXPECTED_ITEMS"].flatMap(Int.init) {
      XCTAssertEqual(original.items.count, expected)
    }
    if let expected = environment["MACCY_FAVORITES_MIGRATION_EXPECTED_CONTENTS"].flatMap(Int.init) {
      XCTAssertEqual(original.contents.count, expected)
    }

    let favoriteID = try autoreleasepool {
      let container = try openStore(at: storeURL)
      let context = container.mainContext
      let items = try context.fetch(FetchDescriptor<HistoryItem>())
      XCTAssertEqual(items.count, original.items.count)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItemContent>()), original.contents.count)
      XCTAssertTrue(items.allSatisfy { !$0.isFavorite })
      // Check the SQL-backed predicate as well as materialized defaults after migration.
      try assertFavoriteCounts(in: context, favorites: 0, ordinary: original.items.count)
      let target = try XCTUnwrap(items.first)
      target.isFavorite = true
      try context.save()
      return try stableIdentifier(for: target)
    }
    XCTAssertEqual(try storedHistory(at: storeURL), original)

    // Recreate the whole container, not merely another context on the existing store.
    try autoreleasepool {
      let container = try openStore(at: storeURL)
      let context = container.mainContext
      let items = try context.fetch(FetchDescriptor<HistoryItem>())
      XCTAssertEqual(items.count, original.items.count)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItemContent>()), original.contents.count)
      XCTAssertEqual(try items.filter(\.isFavorite).map { try stableIdentifier(for: $0) }, [favoriteID])
      try assertFavoriteCounts(in: context, favorites: 1, ordinary: original.items.count - 1)
    }
    // Fingerprints cover every original field, including pin, contents, relationships and preview bytes.
    XCTAssertEqual(try storedHistory(at: storeURL), original)
  }

  func testFavoriteCanBeSavedAndRemovedAcrossFreshDiskStoreReopens() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Storage.sqlite")
    let favoriteID = try autoreleasepool {
      let container = try openStore(at: storeURL)
      let item = HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                           value: Data("https://example.com/favorite".utf8)),
        HistoryItemContent(type: "com.example.empty", value: Data()),
        HistoryItemContent(type: "com.example.nil")
      ])
      item.application = "com.example.source"
      item.title = "Saved favorite"
      item.firstCopiedAt = Date(timeIntervalSince1970: 1_700_000_000)
      item.lastCopiedAt = Date(timeIntervalSince1970: 1_700_000_100)
      item.numberOfCopies = 3
      item.pin = "b"
      item.previewImageBookmark = Data([0, 1, 2, 3])
      item.previewImageFiles = Data([4, 5, 6])
      item.linkPreviewSnapshot = try XCTUnwrap(LinkPreviewSnapshot.encode(
        .failure(.unavailable), sourceURL: URL(string: "https://example.com/favorite")!
      ))
      XCTAssertFalse(item.isFavorite)
      item.isFavorite = true
      container.mainContext.insert(item)
      container.mainContext.insert(HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("Ordinary row".utf8))
      ]))
      try container.mainContext.save()
      return try stableIdentifier(for: item)
    }
    let original = try storedHistory(at: storeURL)
    XCTAssertEqual(original.items.count, 2)
    XCTAssertEqual(original.contents.count, 4)

    try autoreleasepool {
      let container = try openStore(at: storeURL)
      let context = container.mainContext
      let items = try context.fetch(FetchDescriptor<HistoryItem>())
      XCTAssertEqual(try items.filter(\.isFavorite).map { try stableIdentifier(for: $0) }, [favoriteID])
      try assertFavoriteCounts(in: context, favorites: 1, ordinary: 1)
      let favorite = try XCTUnwrap(items.first(where: \.isFavorite))
      favorite.isFavorite = false
      try context.save()
    }
    try autoreleasepool {
      let container = try openStore(at: storeURL)
      let items = try container.mainContext.fetch(FetchDescriptor<HistoryItem>())
      XCTAssertEqual(items.count, 2)
      XCTAssertTrue(items.allSatisfy { !$0.isFavorite })
      try assertFavoriteCounts(in: container.mainContext, favorites: 0, ordinary: 2)
    }
    XCTAssertEqual(try storedHistory(at: storeURL), original)
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaccyFavoritesPersistence-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func openStore(at url: URL) throws -> ModelContainer {
    try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
  }

  private func stableIdentifier(for item: HistoryItem) throws -> Data {
    // Backing NSManagedObjectID instances can compare unequal across containers for the same stored URI.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(item.persistentModelID)
  }

  private func assertFavoriteCounts(in context: ModelContext, favorites: Int, ordinary: Int) throws {
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.isFavorite == true }
    )), favorites)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.isFavorite == false }
    )), ordinary)
  }

  private struct StoredHistory: Equatable {
    let items: [Data]
    let contents: [Data]
  }

  private func storedHistory(at url: URL) throws -> StoredHistory {
    var database: OpaquePointer?
    // Only called for this test's temporary copy. A standalone backup can retain WAL mode
    // without sidecars, so allow SQLite to create them; all statements remain SELECTs.
    let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil)
    defer { sqlite3_close(database) }
    guard status == SQLITE_OK else { throw sqliteError(status) }
    return try StoredHistory(
      items: rowFingerprints(in: database, table: "ZHISTORYITEM"),
      contents: rowFingerprints(in: database, table: "ZHISTORYITEMCONTENT")
    )
  }

  private func rowFingerprints(in database: OpaquePointer?, table: String) throws -> [Data] {
    var statement: OpaquePointer?
    let status = sqlite3_prepare_v2(database, "SELECT * FROM \(table) ORDER BY Z_PK", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    guard status == SQLITE_OK else { throw sqliteError(status) }
    // Ignore Core Data bookkeeping and the intentionally changed favorite field only.
    let ignored: Set<String> = ["Z_ENT", "Z_OPT", "ZISFAVORITE"]
    let columns = (0..<sqlite3_column_count(statement)).compactMap { index -> (Int32, String)? in
      let name = String(cString: sqlite3_column_name(statement, index))
      return ignored.contains(name) ? nil : (index, name)
    }.sorted { $0.1 < $1.1 }
    var rows: [Data] = []
    var step = sqlite3_step(statement)
    while step == SQLITE_ROW {
      var hash = SHA256()
      for (index, name) in columns {
        let type = sqlite3_column_type(statement, index)
        hash.update(data: Data(name.utf8))
        hash.update(data: Data([0, UInt8(type)]))
        let value = storedValue(in: statement, column: index, type: type)
        var length = UInt64(value.count).bigEndian
        hash.update(data: withUnsafeBytes(of: &length) { Data($0) })
        hash.update(data: value)
      }
      // Hashes keep copied text and image bytes out of assertion failure logs.
      rows.append(Data(hash.finalize()))
      step = sqlite3_step(statement)
    }
    guard step == SQLITE_DONE else { throw sqliteError(step) }
    return rows
  }

  private func storedValue(in statement: OpaquePointer?, column: Int32, type: Int32) -> Data {
    if type == SQLITE_INTEGER {
      return Data(String(sqlite3_column_int64(statement, column)).utf8)
    }
    if type == SQLITE_FLOAT {
      var value = sqlite3_column_double(statement, column).bitPattern.bigEndian
      return withUnsafeBytes(of: &value) { Data($0) }
    }
    guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
  }

  private func sqliteError(_ code: Int32) -> NSError {
    NSError(domain: "FavoritesPersistenceSQLite", code: Int(code))
  }
}
