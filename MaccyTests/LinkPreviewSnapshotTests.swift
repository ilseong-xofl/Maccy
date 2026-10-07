import AppKit
import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class LinkPreviewSnapshotTests: XCTestCase {
  private let sourceURL = URL(string: "https://example.com/copied")!

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
