import XCTest
import Defaults
import SwiftUI
import Sauce
@testable import Maccy

@MainActor
class HistoryItemDecoratorTests: XCTestCase {
  let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
  let savedHighlightMatch = Defaults[.highlightMatch]
  let savedImageMaxHeight = Defaults[.imageMaxHeight]
  let savedShowSpecialSymbols = Defaults[.showSpecialSymbols]

  var firstCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:31:34")
  }

  var lastCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:41:34")
  }

  override func setUp() {
    super.setUp()
    Defaults[.highlightMatch] = .bold
    Defaults[.imageMaxHeight] = 40
    Defaults[.showSpecialSymbols] = true
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.imageMaxHeight] = savedImageMaxHeight
    Defaults[.highlightMatch] = savedHighlightMatch
    Defaults[.showSpecialSymbols] = savedShowSpecialSymbols
  }

  func testString() {
    let title = "foo"
    let itemDecorator = historyItemDecorator(title)
    XCTAssertEqual(itemDecorator.title, title)
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testRTF() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let itemDecorator = historyItemDecorator(rtf, .rtf)
    XCTAssertEqual(itemDecorator.title, "foo")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let itemDecorator = historyItemDecorator(html, .html)
    XCTAssertEqual(itemDecorator.title, "foo")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testImage() async {
    let image = NSImage(named: "StatusBarMenuImage")!
    let itemDecorator = historyItemDecorator(image)
    await itemDecorator.sizeImages()
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertEqual(itemDecorator.previewImage!.size, itemDecorator.thumbnailImage!.size)
    XCTAssertNotNil(itemDecorator.imagePixelSize)
  }

  func testImageDecodeIsIndependentOfDisplayHeight() async {
    let image = NSImage(named: "NSApplicationIcon")!
    let itemDecorator = historyItemDecorator(image)
    await itemDecorator.sizeImages()
    XCTAssertGreaterThan(itemDecorator.thumbnailImage!.size.height, 40)
    XCTAssertLessThanOrEqual(itemDecorator.thumbnailImage!.size.height, 2048)
    let decoded = itemDecorator.thumbnailImage
    Defaults[.imageMaxHeight] = 300
    await itemDecorator.sizeImages()
    XCTAssertTrue(itemDecorator.thumbnailImage === decoded)
  }

  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/foo.bar")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testItemWithoutData() {
    let itemDecorator = historyItemDecorator(nil)
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testUnpinnedByDefault() {
    let itemDecorator = historyItemDecorator("foo")
    XCTAssertNil(itemDecorator.item.pin)
    XCTAssertFalse(itemDecorator.isPinned)
  }

  func testDeallocatesWhenNoLongerReferenced() {
    weak var weakDecorator: HistoryItemDecorator?

    autoreleasepool {
      let itemDecorator = historyItemDecorator("foo")
      weakDecorator = itemDecorator
      XCTAssertNotNil(weakDecorator)
    }

    XCTAssertNil(weakDecorator)
  }

  func testHighlight() {
    let itemDecorator = historyItemDecorator("foo bar baz")
    itemDecorator.highlight("random", [
      range(from: 1, to: 2, in: itemDecorator),
      range(from: 8, to: 10, in: itemDecorator)
    ])
    var expectedTitle = AttributedString("foo bar baz")
    expectedTitle[expectedTitle.range(of: "oo")!].font = .bold(.body)()
    expectedTitle[expectedTitle.range(of: "baz")!].font = .bold(.body)()
    XCTAssertEqual(itemDecorator.attributedTitle, expectedTitle)
    itemDecorator.highlight("", [])
    XCTAssertEqual(itemDecorator.attributedTitle, nil)
  }

  func testListTextPreservesNewlinesAndOriginalClipboardData() {
    let source = "  첫 번째 줄\r\n\t두 번째 줄\r세 번째 줄\n  "
    let itemDecorator = historyItemDecorator(source)

    XCTAssertTrue(itemDecorator.title.contains("⏎"))
    XCTAssertEqual(itemDecorator.listText, "  첫 번째 줄\n\t두 번째 줄\n세 번째 줄\n  ")
    XCTAssertEqual(itemDecorator.item.text, source)
    XCTAssertEqual(itemDecorator.item.contents.first?.value, source.data(using: .utf8))
  }

  func testListTextRemovesUnsafeScalarsWithoutChangingClipboardData() {
    let source = "\u{FFFC}첫째\n\u{FFFC}\u{0301}둘째 👨‍👩‍👧‍👦"
    let itemDecorator = historyItemDecorator(source)

    XCTAssertEqual(itemDecorator.listText, "첫째\n\u{0301}둘째 👨‍👩‍👧‍👦")
    XCTAssertEqual(itemDecorator.item.text, source)
  }

  func testListTextPreservesCustomAlias() {
    let source = "Copied text\nSecond line"
    let item = historyItemDecorator(source).item
    item.title = "My saved alias"
    let itemDecorator = HistoryItemDecorator(item)

    XCTAssertEqual(itemDecorator.listText, "My saved alias")
    XCTAssertEqual(itemDecorator.item.text, source)
  }

  func testListTextSanitizesCustomAlias() {
    let item = historyItemDecorator("Copied text").item
    item.title = "My\u{FFFC} alias"

    XCTAssertEqual(HistoryItemDecorator(item).listText, "My alias")
  }

  func testEditingContentUpdatesAutomaticTitleAndMultilinePreview() {
    let itemDecorator = historyItemDecorator("first\nsecond")
    let newText = "changed\n새로운 내용"

    ItemEditorView.updateTextContent(of: itemDecorator, to: Data(newText.utf8))
    waitForPreviewUpdates()

    XCTAssertEqual(itemDecorator.item.text, newText)
    XCTAssertEqual(itemDecorator.item.title, "changed⏎새로운 내용")
    XCTAssertEqual(itemDecorator.title, itemDecorator.item.title)
    XCTAssertEqual(itemDecorator.listText, newText)
  }

  func testEditingContentPreservesCustomAlias() {
    let item = historyItemDecorator("first\nsecond").item
    item.title = "Personal alias"
    let itemDecorator = HistoryItemDecorator(item)
    let newText = "changed\n새로운 내용"

    ItemEditorView.updateTextContent(of: itemDecorator, to: Data(newText.utf8))
    waitForPreviewUpdates()

    XCTAssertEqual(itemDecorator.item.text, newText)
    XCTAssertEqual(itemDecorator.previewText.string, newText)
    XCTAssertEqual(itemDecorator.item.title, "Personal alias")
    XCTAssertEqual(itemDecorator.listText, "Personal alias")
  }

  private func waitForPreviewUpdates() {
    let updated = expectation(description: "Queued preview observers have updated")
    DispatchQueue.main.async { updated.fulfill() }
    waitForExpectations(timeout: 2)
  }

  func testListTextFallsBackToTitleWithoutClipboardContent() {
    let item = historyItemDecorator(nil).item
    item.title = "Recognized or imported text"

    XCTAssertEqual(HistoryItemDecorator(item).listText, item.title)
  }

  func testListTextTruncatesLongParagraphWithEllipsis() {
    let source = String(repeating: "a", count: 10_001)
    let itemDecorator = historyItemDecorator(source)

    XCTAssertEqual(itemDecorator.listText, String(repeating: "a", count: 10_000) + "…")
    XCTAssertEqual(itemDecorator.item.text, source)
  }

  func testListTextLimitsTotalLengthAcrossParagraphs() {
    let source = String(repeating: "🇰🇷 café\n", count: 1_600)
    let itemDecorator = historyItemDecorator(source)

    XCTAssertEqual(itemDecorator.listText, String(source.prefix(10_000)) + "…")
    XCTAssertEqual(itemDecorator.item.text, source)
  }

  func testListTextDoesNotAddEllipsisAtExactLimit() {
    let source = String(repeating: "a", count: 10_000)

    XCTAssertEqual(historyItemDecorator(source).listText, source)
  }

  func testHighlightBeyondFiveHundredCharacters() throws {
    let source = String(repeating: "a", count: 600) + "\n검색 대상"
    let itemDecorator = historyItemDecorator(source)
    let match = try XCTUnwrap(itemDecorator.listText.range(of: "검색"))
    itemDecorator.highlight("검색", [match])

    var expectedTitle = AttributedString(source)
    expectedTitle[try XCTUnwrap(expectedTitle.range(of: "검색"))].font = .bold(.body)()
    XCTAssertEqual(itemDecorator.attributedTitle, expectedTitle)
  }

  func testShortListTextDoesNotReserveMaximumLineCount() {
    let oneLine = titleSize("Short text", maxLines: 1, width: 300)
    let tenLines = titleSize("Short text", maxLines: 10, width: 300)

    XCTAssertGreaterThan(oneLine.height, 0)
    XCTAssertEqual(oneLine.height, tenLines.height, accuracy: 1)
  }

  func testListTitleUsesOneThreeAndTenLineLimits() {
    let source = Array(repeating: "Line", count: 20).joined(separator: "\n")

    for maxLines in [1, 3, 10] {
      let expected = Array(repeating: "Line", count: maxLines).joined(separator: "\n")
      let cappedSize = titleSize(source, maxLines: maxLines, width: 300)
      let expectedSize = titleSize(expected, maxLines: 10, width: 300)
      XCTAssertEqual(cappedSize.height, expectedSize.height, accuracy: 1, "Limit: \(maxLines)")
    }
  }

  func testListTitleReflowsAtDifferentWidths() {
    let source = String(repeating: "자동 줄바꿈을 확인합니다. ", count: 8)
    let narrow = titleSize(source, maxLines: 10, width: 180)
    let wide = titleSize(source, maxLines: 10, width: 600)

    XCTAssertGreaterThan(narrow.height, wide.height)
    XCTAssertEqual(narrow.width, 180, accuracy: 1)
    XCTAssertEqual(wide.width, 600, accuracy: 1)
  }

  func testLongURLWrapsWithinAvailableWidth() {
    let source = "https://example.com/" + String(repeating: "abcdefghij", count: 30)
    let singleLine = titleSize(source, maxLines: 1, width: 180)
    let multipleLines = titleSize(source, maxLines: 10, width: 180)

    XCTAssertGreaterThan(multipleLines.height, singleLine.height)
    XCTAssertEqual(multipleLines.width, 180, accuracy: 1)
  }

  private func titleSize(_ text: String, maxLines: Int, width: CGFloat) -> NSSize {
    let view = NSHostingView(rootView:
      ListItemTitleView(attributedTitle: nil, maxLines: maxLines) {
        Text(verbatim: text)
      }
      .font(.system(size: 13))
      .frame(width: width, alignment: .leading)
    )
    view.layoutSubtreeIfNeeded()
    return view.fittingSize
  }

  private func historyItemDecorator(
    _ value: String?,
    application: String? = "com.apple.finder"
  ) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value?.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt

    return HistoryItemDecorator(item)
  }

  private func historyItemDecorator(
    _ value: Data?,
    _ type: NSPasteboard.PasteboardType
  ) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: type.rawValue,
        value: value
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    return HistoryItemDecorator(item)
  }

  private func historyItemDecorator(_ value: NSImage) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.tiff.rawValue,
        value: value.tiffRepresentation!
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    return HistoryItemDecorator(item)
  }

  private func historyItemDecorator(_ value: URL) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue,
        value: value.dataRepresentation
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.lastPathComponent.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    return HistoryItemDecorator(item)
  }

  // swiftlint:disable:next identifier_name
  private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
    let startIndex = item.listText.startIndex
    let lowerBound = item.listText.index(startIndex, offsetBy: from)
    let upperBound = item.listText.index(startIndex, offsetBy: to + 1)

    return lowerBound..<upperBound
  }
}

@MainActor
class ClipboardImagePreviewTests: XCTestCase {
  private var files: [URL] = []

  override func tearDown() {
    for file in files { try? FileManager.default.removeItem(at: file) }
    files = []
    super.tearDown()
  }

  private func imageData(width: Int = 800, height: Int = 400,
                         format: NSBitmapImageRep.FileType = .png) throws -> Data {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0))
    return try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
  }

  private func imageFile(extension suffix: String = "png", data: Data? = nil) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("미리 보기-\(UUID()).\(suffix)")
    try (data ?? imageData()).write(to: url)
    files.append(url)
    return url
  }

  private func decorator(_ values: [(NSPasteboard.PasteboardType, Data?)]) -> HistoryItemDecorator {
    let item = HistoryItem(contents: values.map { HistoryItemContent(type: $0.0.rawValue, value: $0.1) })
    Storage.shared.context.insert(item)
    item.title = item.generateTitle()
    return HistoryItemDecorator(item)
  }

  func testFileURLOnlyPNGShowsImageWithoutChangingClipboardPayload() async throws {
    let originalData = try imageData()
    let url = try imageFile(data: originalData)
    let value = url.dataRepresentation
    let item = decorator([(.fileURL, value)])
    await item.sizeImages()

    XCTAssertEqual(item.imagePixelSize, NSSize(width: 800, height: 400))
    XCTAssertNotNil(item.thumbnailImage)
    XCTAssertEqual(item.clippingByteCount, Int64(originalData.count))
    XCTAssertEqual(item.item.contents.count, 1)
    XCTAssertEqual(item.item.contents.first?.type, NSPasteboard.PasteboardType.fileURL.rawValue)
    XCTAssertEqual(item.item.contents.first?.value, value)
    XCTAssertEqual(item.item.fileURLs, [url])
    XCTAssertTrue(item.listText.contains(url.lastPathComponent))
  }

  func testJPEGFileWithUppercaseExtensionShowsImage() async throws {
    let url = try imageFile(extension: "JPG", data: imageData(format: .jpeg))
    let item = decorator([(.fileURL, url.dataRepresentation)])
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
  }

  func testRawImageWinsOverFileURL() async throws {
    let url = try imageFile()
    let originalData = try imageData(width: 120, height: 80)
    let item = decorator([(.fileURL, url.dataRepresentation), (.png, originalData)])
    await item.sizeImages()
    XCTAssertEqual(item.imagePixelSize, NSSize(width: 120, height: 80))
    XCTAssertEqual(item.clippingByteCount, Int64(originalData.count))
  }

  func testInvalidFirstRepresentationDoesNotHideValidImage() async throws {
    let validData = try imageData(format: .tiff)
    let item = decorator([(.png, Data("invalid".utf8)), (.tiff, validData)])
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
    XCTAssertEqual(item.clippingByteCount, Int64(validData.count))
  }

  func testNilFirstRepresentationDoesNotHideValidImage() async throws {
    let item = decorator([(.png, nil), (.tiff, try imageData(format: .tiff))])
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
  }

  func testInvalidImageFallsBackToPath() async throws {
    let url = try imageFile(data: Data("not an image".utf8))
    let item = decorator([(.fileURL, url.dataRepresentation)])
    await item.sizeImages()
    XCTAssertNil(item.thumbnailImage)
    XCTAssertTrue(item.listText.contains(url.lastPathComponent))
  }

  func testDeletedImageFallsBackToPath() async throws {
    let url = try imageFile()
    try FileManager.default.removeItem(at: url)
    let item = decorator([(.fileURL, url.dataRepresentation)])
    await item.sizeImages()
    XCTAssertNil(item.thumbnailImage)
    XCTAssertTrue(item.listText.contains(url.lastPathComponent))
  }

  func testMultipleFilesKeepCompleteFileList() async throws {
    let first = try imageFile()
    let second = try imageFile()
    let item = decorator([(.fileURL, first.dataRepresentation), (.fileURL, second.dataRepresentation)])
    await item.sizeImages()
    XCTAssertNil(item.thumbnailImage)
    XCTAssertTrue(item.listText.contains(first.lastPathComponent))
    XCTAssertTrue(item.listText.contains(second.lastPathComponent))
  }

  func testTextPathAndRemoteURLRemainText() async throws {
    let url = try imageFile()
    for text in [url.path, url.absoluteString, "https://example.com/image.png"] {
      let item = decorator([(.string, Data(text.utf8))])
      XCTAssertTrue(item.item.previewImageSources.isEmpty)
      await item.sizeImages()
      XCTAssertNil(item.thumbnailImage)
    }
    let remote = decorator([(.fileURL, Data("https://example.com/image.png".utf8))])
    XCTAssertTrue(remote.item.previewImageSources.isEmpty)
  }

  func testLargeImageIsDownsampledAndReportsOriginalDimensions() async throws {
    let originalData = try imageData(width: 4096, height: 1024)
    let item = decorator([(.png, originalData)])
    await item.sizeImages()
    XCTAssertEqual(item.imagePixelSize, NSSize(width: 4096, height: 1024))
    let thumbnail = try XCTUnwrap(item.thumbnailImage)
    XCTAssertEqual(thumbnail.size, NSSize(width: 2048, height: 512))
    XCTAssertEqual(item.clippingByteCount, Int64(originalData.count))
  }

  func testNonImageClippingSizeIncludesStoredRepresentations() {
    let text = Data("클립보드".utf8)
    let html = Data("<b>클립보드</b>".utf8)
    let item = decorator([(.string, text), (.html, html), (.rtf, nil)])
    XCTAssertEqual(item.clippingByteCount, Int64(text.count + html.count))
  }

  func testCleanupAllowsThumbnailRegeneration() async throws {
    let item = decorator([(.png, try imageData())])
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
    item.cleanupImages()
    XCTAssertNil(item.thumbnailImage)
    XCTAssertNil(item.thumbnailImageGenerationTask)
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
  }

  func testCancelledLoadCanRestart() async throws {
    let item = decorator([(.png, try imageData())])
    item.ensureThumbnailImage()
    item.cleanupImages()
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
  }

  func testReadOnlyBookmarkRestoresImageWithoutChangingFileContents() async throws {
    let url = try imageFile()
    let item = decorator([(.fileURL, url.dataRepresentation)])
    item.item.rememberPreviewImageAccess(from: [url])
    XCTAssertNotNil(item.item.previewImageBookmark)
    let restored = HistoryItemDecorator(item.item)
    await restored.sizeImages()
    XCTAssertNotNil(restored.thumbnailImage)
    XCTAssertEqual(item.item.contents.count, 1)
    XCTAssertEqual(item.item.contents.first?.value, url.dataRepresentation)
  }

  func testUnrelatedFileCannotSupplyPreviewBookmark() throws {
    let first = try imageFile()
    let second = try imageFile()
    let item = decorator([(.fileURL, first.dataRepresentation)])
    item.item.rememberPreviewImageAccess(from: [second])
    XCTAssertNil(item.item.previewImageBookmark)
  }

  func testBrokenBookmarkFallsBackToAccessibleOriginalURL() async throws {
    let url = try imageFile()
    let item = decorator([(.fileURL, url.dataRepresentation)])
    item.item.previewImageBookmark = Data("invalid bookmark".utf8)
    await item.sizeImages()
    XCTAssertNotNil(item.thumbnailImage)
    XCTAssertEqual(item.item.previewImageBookmark, Data("invalid bookmark".utf8))
  }
}

@MainActor
class FloatingPanelSizingTests: XCTestCase {
  func testResizeDelegateAllowsNarrowerWindowWithFixedWidthContent() {
    withRestoredWindowState {
      let panel = makePanel()
      panel.contentView?.layoutSubtreeIfNeeded()

      let proposed = NSSize(width: 420, height: 500)
      let accepted = panel.windowWillResize(panel, to: proposed)

      XCTAssertEqual(panel.frame.width, 640, accuracy: 1)
      XCTAssertLessThan(panel.contentMinSize.width, 640)
      XCTAssertEqual(accepted.width, 420, accuracy: 1)
    }
  }

  func testResizeDelegateEnforcesMinimumListWidth() {
    withRestoredWindowState {
      let panel = makePanel()
      let accepted = panel.windowWillResize(panel, to: NSSize(width: 80, height: 500))

      XCTAssertEqual(accepted.width, FloatingPanel<AnyView>.minimumListWidth, accuracy: 1)
    }
  }

  func testPreferredHeightUsesSavedHeightRegardlessOfContentHeight() {
    withRestoredWindowState {
      Defaults[.windowSize] = NSSize(width: 640, height: 500)
      let popup = AppState.shared.popup
      let screen = AppState.shared.appDelegate?.panel.screen ?? NSScreen.forPopup
      let expected = min(CGFloat(500), screen?.visibleFrame.height ?? .infinity)

      XCTAssertEqual(popup.preferredHeight(for: 20), expected, accuracy: 1)
      XCTAssertEqual(popup.preferredHeight(for: 10_000), expected, accuracy: 1)
    }
  }

  func testCompletedResizeSavesOnlyListWindowSize() {
    withRestoredWindowState {
      let panel = makePanel(size: NSSize(width: 420, height: 500))
      let previewSize = Defaults[.previewWindowSize]
      panel.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
      XCTAssertEqual(Defaults[.windowSize].width, 420, accuracy: 1)
      XCTAssertEqual(Defaults[.windowSize].height, panel.frame.height, accuracy: 1)
      XCTAssertEqual(Defaults[.previewWindowSize], previewSize)
    }
  }

  private func makePanel(size: NSSize = NSSize(width: 640, height: 700)) -> FloatingPanel<AnyView> {
    FloatingPanel(contentRect: NSRect(origin: .zero, size: size), onClose: {}) {
      AnyView(Text("Fixed-width content").frame(width: 640))
    }
  }

  private func withRestoredWindowState(_ test: () -> Void) {
    let popup = AppState.shared.popup
    let savedSize = Defaults[.windowSize]
    let savedPosition = Defaults[.windowPosition]
    let savedHeaderHeight = popup.headerHeight
    let savedFooterHeight = popup.footerHeight
    let savedExtraTopHeight = popup.extraTopHeight
    let savedExtraBottomHeight = popup.extraBottomHeight
    defer {
      popup.headerHeight = savedHeaderHeight
      popup.footerHeight = savedFooterHeight
      popup.extraTopHeight = savedExtraTopHeight
      popup.extraBottomHeight = savedExtraBottomHeight
      Defaults[.windowSize] = savedSize
      Defaults[.windowPosition] = savedPosition
    }
    popup.headerHeight = 0
    popup.footerHeight = 0
    popup.extraTopHeight = 0
    popup.extraBottomHeight = 0
    test()
  }

}

@MainActor
class ImageRowLayoutTests: XCTestCase {
  func testWideImageFitsAvailableWidthWithoutCropping() {
    let size = renderedSize(sourceSize: CGSize(width: 2_000, height: 1_000), width: 500, maximumHeight: 300)

    XCTAssertEqual(size.width, 500, accuracy: 1)
    XCTAssertEqual(size.height, 250, accuracy: 1)
  }

  func testPortraitImageStopsAtMaximumHeight() {
    let sourceSize = CGSize(width: 1_000, height: 2_000)
    let fitted = ListItemImageLayout.fittedSize(sourceSize: sourceSize, availableWidth: 500, maximumHeight: 300)
    let rendered = renderedSize(sourceSize: sourceSize, width: 500, maximumHeight: 300)

    XCTAssertEqual(fitted, CGSize(width: 150, height: 300))
    XCTAssertEqual(rendered.width, 500, accuracy: 1)
    XCTAssertEqual(rendered.height, 300, accuracy: 1)
  }

  func testWindowWidthChangeRecalculatesImageRowHeight() {
    let sourceSize = CGSize(width: 1_200, height: 800)
    let wide = renderedSize(sourceSize: sourceSize, width: 600, maximumHeight: 600)
    let narrow = renderedSize(sourceSize: sourceSize, width: 240, maximumHeight: 600)

    XCTAssertEqual(wide.width, 600, accuracy: 1)
    XCTAssertEqual(wide.height, 400, accuracy: 1)
    XCTAssertEqual(narrow.width, 240, accuracy: 1)
    XCTAssertEqual(narrow.height, 160, accuracy: 1)
    XCTAssertLessThan(narrow.height, wide.height)
  }

  func testMaximumHeightSettingChangesRenderedHeight() {
    let sourceSize = CGSize(width: 1_000, height: 2_000)
    let compact = renderedSize(sourceSize: sourceSize, width: 500, maximumHeight: 100)
    let large = renderedSize(sourceSize: sourceSize, width: 500, maximumHeight: 300)

    XCTAssertEqual(compact.height, 100, accuracy: 1)
    XCTAssertEqual(large.height, 300, accuracy: 1)
  }

  func testSmallImageKeepsItsNaturalHeightInWideRow() {
    let sourceSize = CGSize(width: 96, height: 64)
    let fitted = ListItemImageLayout.fittedSize(sourceSize: sourceSize, availableWidth: 500, maximumHeight: 300)
    let rendered = renderedSize(sourceSize: sourceSize, width: 500, maximumHeight: 300)

    XCTAssertEqual(fitted, sourceSize)
    XCTAssertEqual(rendered.width, 500, accuracy: 1)
    XCTAssertEqual(rendered.height, 64, accuracy: 1)
  }

  func testUnboundedWidthStillHonorsMaximumHeightWithoutUpscaling() {
    let sourceSize = CGSize(width: 800, height: 400)
    for width in [nil, CGFloat.infinity] as [CGFloat?] {
      let fitted = ListItemImageLayout.fittedSize(
        sourceSize: sourceSize,
        availableWidth: width,
        maximumHeight: 300
      )
      XCTAssertEqual(fitted, CGSize(width: 600, height: 300))
    }
  }

  func testZeroOrInvalidSourceAndAvailableSpaceHaveNoImageSize() {
    for sourceSize in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 100), CGSize(width: 100, height: -1)] {
      XCTAssertEqual(
        ListItemImageLayout.fittedSize(sourceSize: sourceSize, availableWidth: 500, maximumHeight: 300),
        .zero
      )
    }
    for width: CGFloat in [0, -100] {
      XCTAssertEqual(
        ListItemImageLayout.fittedSize(
          sourceSize: CGSize(width: 200, height: 100),
          availableWidth: width,
          maximumHeight: 300
        ),
        .zero
      )
    }
  }

  private func renderedSize(sourceSize: CGSize, width: CGFloat, maximumHeight: CGFloat) -> CGSize {
    let image = NSImage(size: sourceSize, flipped: false) { bounds in
      NSColor.systemBlue.setFill()
      NSBezierPath(rect: bounds).fill()
      return true
    }
    let view = NSHostingView(rootView:
      ListItemImageView(image: image, maximumHeight: maximumHeight)
        .frame(width: width, alignment: .leading)
    )
    view.layoutSubtreeIfNeeded()
    return view.fittingSize
  }
}

@MainActor
class DetachedPreviewPlacementTests: XCTestCase {
  private let desktop = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
  private let requestedSize = NSSize(width: 520, height: 600)

  func testRightPlacementLeavesGapAndAlignsTopEdges() {
    let anchor = NSRect(x: 400, y: 300, width: 400, height: 600)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: desktop,
                                                    requestedSize: requestedSize, direction: .right)
    XCTAssertEqual(frame, NSRect(x: 808, y: 300, width: 520, height: 600))
  }

  func testLeftPreferenceIsHonoredWhenBothSidesFit() {
    let anchor = NSRect(x: 700, y: 300, width: 400, height: 600)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: desktop,
                                                    requestedSize: requestedSize, direction: .left)
    XCTAssertEqual(frame, NSRect(x: 172, y: 300, width: 520, height: 600))
  }

  func testRightEdgeFallsBackToLeftWithoutShrinking() {
    let anchor = NSRect(x: 1_400, y: 300, width: 400, height: 600)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: desktop,
                                                    requestedSize: requestedSize, direction: .right)
    XCTAssertEqual(frame.maxX, anchor.minX - 8)
    XCTAssertEqual(frame.size, requestedSize)
  }

  func testLeftEdgeFallsBackToRightWithoutShrinking() {
    let anchor = NSRect(x: 40, y: 300, width: 400, height: 600)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: desktop,
                                                    requestedSize: requestedSize, direction: .left)
    XCTAssertEqual(frame.minX, anchor.maxX + 8)
    XCTAssertEqual(frame.size, requestedSize)
  }

  func testNeitherSideFitsKeepsWidthAndOverlapsListOnRoomierSide() {
    let screen = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    let anchor = NSRect(x: 350, y: 100, width: 400, height: 700)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: screen,
                                                    requestedSize: NSSize(width: 800, height: 600), direction: .left)
    XCTAssertEqual(frame.minX, 600)
    XCTAssertEqual(frame.width, 800)
    XCTAssertLessThan(frame.minX, anchor.maxX)
    XCTAssertEqual(frame.height, 600)
    XCTAssertTrue(screen.contains(frame))
  }

  func testSecondaryScreenWithNegativeOriginKeepsPreviewOnThatScreen() {
    let screen = NSRect(x: -1_920, y: -900, width: 1_920, height: 900)
    let anchor = NSRect(x: -1_700, y: -700, width: 400, height: 500)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: screen,
                                                    requestedSize: requestedSize, direction: .right)
    XCTAssertEqual(frame.minX, -1_292)
    XCTAssertEqual(frame.maxY, anchor.maxY)
    XCTAssertTrue(screen.contains(frame))
  }

  func testScreenSmallerThanMinimumUsesVisibleBounds() {
    let screen = NSRect(x: -220, y: 40, width: 220, height: 180)
    let anchor = NSRect(x: -190, y: 70, width: 140, height: 120)
    let frame = DetachedPreviewController.placement(anchorFrame: anchor, visibleFrame: screen,
                                                    requestedSize: requestedSize, direction: .right)
    XCTAssertEqual(frame, screen)
  }

  func testVerticalPlacementClampsToVisibleFrameAboveAndBelow() {
    let screen = NSRect(x: 0, y: 40, width: 1_600, height: 900)
    let below = DetachedPreviewController.placement(
      anchorFrame: NSRect(x: 100, y: -100, width: 300, height: 100), visibleFrame: screen,
      requestedSize: requestedSize, direction: .right)
    let above = DetachedPreviewController.placement(
      anchorFrame: NSRect(x: 100, y: 850, width: 300, height: 200), visibleFrame: screen,
      requestedSize: requestedSize, direction: .right)
    XCTAssertEqual(below.minY, screen.minY)
    XCTAssertEqual(above.maxY, screen.maxY)
    XCTAssertTrue(screen.contains(below))
    XCTAssertTrue(screen.contains(above))
  }

  func testAdjacentSpaceDoesNotChangeRequestedSizeOrPersistNewSize() {
    let savedSize = Defaults[.previewWindowSize]
    defer { Defaults[.previewWindowSize] = savedSize }
    let requested = NSSize(width: 800, height: 700)
    Defaults[.previewWindowSize] = requested
    let anchor = NSRect(x: 300, y: 100, width: 400, height: 700)
    let constrained = DetachedPreviewController.placement(
      anchorFrame: anchor, visibleFrame: NSRect(x: 0, y: 0, width: 1_100, height: 900),
      requestedSize: Defaults[.previewWindowSize], direction: .right)
    let unconstrained = DetachedPreviewController.placement(
      anchorFrame: anchor, visibleFrame: NSRect(x: 0, y: 0, width: 2_400, height: 1_200),
      requestedSize: Defaults[.previewWindowSize], direction: .right)
    XCTAssertEqual(constrained.size, requested)
    XCTAssertEqual(Defaults[.previewWindowSize], requested)
    XCTAssertEqual(unconstrained.size, requested)
  }
}

@MainActor
class DetachedPreviewAutomaticSizingTests: XCTestCase {
  private let maximumSize = NSSize(width: 520, height: 600)
  private let imageWidth: CGFloat = 508
  private let nonImageHeight: CGFloat = 180

  func testFactoryDefaultSizeProvidesAnAutomaticHeightCeiling() {
    XCTAssertEqual(DetachedPreviewController.defaultSize, maximumSize)
    let size = automaticSize(for: NSSize(width: 2_000, height: 2_000))
    XCTAssertEqual(size, maximumSize)
  }

  func testWideImageShrinksOnlyHeightToItsDisplayedAspectRatio() {
    let size = automaticSize(for: NSSize(width: 2_000, height: 1_000))
    XCTAssertEqual(size, NSSize(width: 520, height: 434))
  }

  func testSmallImageUpscalesToTheSameWidthAsLargerImageWithSameAspectRatio() {
    let small = automaticSize(for: NSSize(width: 32, height: 18))
    let large = automaticSize(for: NSSize(width: 3_200, height: 1_800))
    XCTAssertEqual(small, NSSize(width: 520, height: 466))
    XCTAssertEqual(small, large)
    XCTAssertGreaterThan(small.height - nonImageHeight, 18)
  }

  func testPortraitImageStaysWithinDefaultSize() {
    let size = automaticSize(for: NSSize(width: 1_000, height: 3_000))
    XCTAssertEqual(size, maximumSize)
  }

  func testExtremePanoramaHonorsMinimumWindowHeight() {
    let size = automaticSize(for: NSSize(width: 10_000, height: 10))
    XCTAssertEqual(size.width, maximumSize.width)
    XCTAssertEqual(size.height, DetachedPreviewController.minimumSize.height)
  }

  func testMissingOrInvalidImageDimensionsKeepDefaultSize() {
    let invalidSizes: [NSSize?] = [
      nil,
      NSSize(width: 0, height: 100),
      NSSize(width: 100, height: 0),
      NSSize(width: -1, height: 100),
      NSSize(width: 100, height: -1),
      NSSize(width: CGFloat.nan, height: 100),
      NSSize(width: 100, height: CGFloat.infinity)
    ]
    for imageSize in invalidSizes {
      XCTAssertEqual(automaticSize(for: imageSize), maximumSize)
    }
  }

  func testMissingOrInvalidMeasuredImageWidthKeepsDefaultSize() {
    for width: CGFloat in [0, -1, CGFloat.nan, CGFloat.infinity] {
      let size = DetachedPreviewController.automaticSize(
        imageSize: NSSize(width: 2_000, height: 1_000), maximumSize: maximumSize,
        imageWidth: width, nonImageHeight: nonImageHeight)
      XCTAssertEqual(size, maximumSize)
    }
  }

  func testInvalidMeasuredChromeHeightKeepsDefaultSize() {
    for height: CGFloat in [-1, CGFloat.nan, CGFloat.infinity] {
      let size = DetachedPreviewController.automaticSize(
        imageSize: NSSize(width: 2_000, height: 1_000), maximumSize: maximumSize,
        imageWidth: imageWidth, nonImageHeight: height)
      XCTAssertEqual(size, maximumSize)
    }
  }

  func testWrappingMetadataAddsItsMeasuredHeightWithoutChangingWidth() {
    let imageSize = NSSize(width: 2_000, height: 1_000)
    let singleLine = automaticSize(for: imageSize)
    let wrapped = DetachedPreviewController.automaticSize(
      imageSize: imageSize, maximumSize: maximumSize,
      imageWidth: imageWidth, nonImageHeight: nonImageHeight + 20)
    XCTAssertEqual(wrapped.width, singleLine.width)
    XCTAssertEqual(wrapped.height, singleLine.height + 20)
  }

  func testAutomaticSizingRetainsProvidedMaximumWidthWhileShortImagesFitHeight() {
    let providedMaximum = NSSize(width: 900, height: 800)
    let size = DetachedPreviewController.automaticSize(
      imageSize: NSSize(width: 200, height: 100), maximumSize: providedMaximum,
      imageWidth: 888, nonImageHeight: nonImageHeight)
    XCTAssertEqual(size, NSSize(width: 900, height: 624))
  }

  func testScreenConstrainedMaximumStillCapsHeightAndPreservesItsWidth() {
    let constrainedMaximum = NSSize(width: 480, height: 500)
    let wide = DetachedPreviewController.automaticSize(
      imageSize: NSSize(width: 2_000, height: 1_000), maximumSize: constrainedMaximum,
      imageWidth: 468, nonImageHeight: nonImageHeight)
    let tall = DetachedPreviewController.automaticSize(
      imageSize: NSSize(width: 1_000, height: 2_000), maximumSize: constrainedMaximum,
      imageWidth: 468, nonImageHeight: nonImageHeight)
    XCTAssertEqual(wide, NSSize(width: 480, height: 414))
    XCTAssertEqual(tall, constrainedMaximum)
  }

  func testPlacementOnlyShrinksWidthWhenScreenItselfIsNarrower() {
    let anchor = NSRect(x: 300, y: 100, width: 400, height: 700)
    let requested = NSSize(width: 800, height: 600)
    let roomyScreen = NSRect(x: 0, y: 0, width: 1_100, height: 900)
    let narrowScreen = NSRect(x: 0, y: 0, width: 700, height: 900)
    let roomyFrame = DetachedPreviewController.placement(
      anchorFrame: anchor, visibleFrame: roomyScreen, requestedSize: requested, direction: .right)
    let narrowFrame = DetachedPreviewController.placement(
      anchorFrame: anchor, visibleFrame: narrowScreen, requestedSize: requested, direction: .right)
    XCTAssertEqual(roomyFrame.width, requested.width)
    XCTAssertEqual(narrowFrame.width, narrowScreen.width)
    XCTAssertTrue(roomyScreen.contains(roomyFrame))
    XCTAssertTrue(narrowScreen.contains(narrowFrame))
  }

  private func automaticSize(for imageSize: NSSize?) -> NSSize {
    DetachedPreviewController.automaticSize(
      imageSize: imageSize, maximumSize: maximumSize,
      imageWidth: imageWidth, nonImageHeight: nonImageHeight)
  }
}

@MainActor
class DetachedPreviewSessionSizingTests: XCTestCase {
  func testOpeningIgnoresLegacyRememberedWindowSize() throws {
    try withPreviewSession { controller, anchor in
      let legacySize = NSSize(width: 900, height: 800)
      Defaults[.previewWindowSize] = legacySize

      controller.togglePreview()

      let window = try XCTUnwrap(controller.window)
      XCTAssertTrue(controller.isVisible)
      XCTAssertEqual(controller.sessionSize, DetachedPreviewController.defaultSize)
      XCTAssertEqual(window.frame, try defaultFrame(nextTo: anchor))
      XCTAssertEqual(Defaults[.previewWindowSize], legacySize)
    }
  }

  func testManualResizeAppliesUntilCloseAndReopeningRestoresDefaultSize() throws {
    try withPreviewSession { controller, anchor in
      let legacySize = NSSize(width: 900, height: 800)
      Defaults[.previewWindowSize] = legacySize
      controller.togglePreview()
      let window = try XCTUnwrap(controller.window)
      let manualSize = NSSize(width: 420, height: 400)

      controller.windowWillStartLiveResize(
        Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
      window.setFrame(NSRect(origin: window.frame.origin, size: manualSize), display: false)
      controller.windowDidEndLiveResize(
        Notification(name: NSWindow.didEndLiveResizeNotification, object: window))

      XCTAssertEqual(controller.sessionSize, manualSize)
      XCTAssertEqual(window.frame.size, manualSize)
      controller.reposition()
      XCTAssertEqual(window.frame.size, manualSize)
      XCTAssertEqual(Defaults[.previewWindowSize], legacySize)

      // Escape and Space route through these same close/open operations.
      controller.close(restoreListFocus: true)
      XCTAssertFalse(controller.isVisible)
      controller.togglePreview()

      XCTAssertTrue(controller.isVisible)
      XCTAssertTrue(controller.window === window)
      XCTAssertEqual(controller.sessionSize, DetachedPreviewController.defaultSize)
      XCTAssertEqual(window.frame, try defaultFrame(nextTo: anchor))
      XCTAssertEqual(Defaults[.previewWindowSize], legacySize)
    }
  }

  private func defaultFrame(nextTo anchor: NSWindow) throws -> NSRect {
    let screen = try XCTUnwrap(anchor.screen ?? NSScreen.main)
    return DetachedPreviewController.placement(
      anchorFrame: anchor.frame, visibleFrame: screen.visibleFrame,
      requestedSize: DetachedPreviewController.defaultSize, direction: Defaults[.previewDirection])
  }

  private func withPreviewSession(
    _ test: (DetachedPreviewController, NSWindow) throws -> Void
  ) throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let appState = AppState.shared
    let savedDelegate = appState.appDelegate
    let savedNavigator = appState.navigator
    let savedPreview = appState.preview
    let savedFocus = appState.requestedKeyboardFocus
    let savedSearchFocused = appState.isSearchFocused
    let savedEditing = appState.isEditingItem
    let savedSize = Defaults[.previewWindowSize]
    let controller = DetachedPreviewController()
    let delegate = AppDelegate()
    delegate.panel = FloatingPanel(
      contentRect: NSRect(x: screen.visibleFrame.midX - 160, y: screen.visibleFrame.midY - 200,
                          width: 320, height: 400), onClose: {}) { ContentView() }
    // The anchor needs native window geometry, not the history-list view or its observers.
    delegate.panel.contentView = NSView()
    appState.appDelegate = delegate
    appState.preview = controller
    appState.navigator = NavigationManager(history: appState.history, footer: Footer())
    appState.isEditingItem = false
    defer {
      controller.close()
      controller.window?.contentView = nil
      delegate.panel.orderOut(nil)
      appState.appDelegate = savedDelegate
      appState.navigator = savedNavigator
      appState.preview = savedPreview
      appState.requestKeyboardFocus(savedFocus)
      appState.isSearchFocused = savedSearchFocused
      appState.isEditingItem = savedEditing
      Defaults[.previewWindowSize] = savedSize
    }
    let item = HistoryItem(contents: [HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue, value: Data("Preview sizing fixture".utf8))])
    appState.navigator.selectWithoutScrolling(item: HistoryItemDecorator(item))
    delegate.panel.orderFront(nil)
    try test(controller, delegate.panel)
  }
}

@MainActor
class ExplicitSearchKeyboardTests: XCTestCase {
  func testRepeatedExplicitFocusRequestsAreDelivered() {
    let appState = AppState.shared
    let savedFocus = appState.requestedKeyboardFocus
    let savedSearchFocused = appState.isSearchFocused
    defer {
      appState.requestKeyboardFocus(savedFocus)
      appState.isSearchFocused = savedSearchFocused
    }
    appState.requestKeyboardFocus(.search)
    let firstRequest = appState.keyboardFocusRequestID
    appState.requestKeyboardFocus(.search)
    XCTAssertNotEqual(appState.keyboardFocusRequestID, firstRequest)
    XCTAssertEqual(appState.requestedKeyboardFocus, .search)
    XCTAssertTrue(appState.isSearchFocused)
    appState.requestKeyboardFocus(.list)
    XCTAssertEqual(appState.requestedKeyboardFocus, .list)
    XCTAssertFalse(appState.isSearchFocused)
  }

  func testSpacePreviewsAndCommandFFocusesSearch() {
    XCTAssertEqual(KeyChord(.space, []), .spacePreview)
    XCTAssertEqual(KeyChord(.f, [.command]), .focusSearch)
    XCTAssertEqual(KeyChord(.f, []), .unknown)
    XCTAssertEqual(KeyChord(.delete, []), .unknown)
    XCTAssertEqual(KeyChord(.escape, []), .close)
  }

  func testExistingFPinDoesNotStealCommandF() {
    let shortcuts = KeyShortcut.create(character: "f")
    XCTAssertFalse(shortcuts.contains { $0.modifierFlags == [.command] })
    XCTAssertTrue(shortcuts.contains { $0.modifierFlags == [.option] })
    XCTAssertFalse(HistoryItem.supportedPins.contains("f"))
  }

  func testExplicitFocusRevealsSearchEvenWhenHidden() {
    let appState = AppState.shared
    let savedShowSearch = Defaults[.showSearch]
    let savedVisibility = Defaults[.searchVisibility]
    let savedFocus = appState.isSearchFocused
    let savedQuery = appState.history.searchQuery
    defer {
      Defaults[.showSearch] = savedShowSearch
      Defaults[.searchVisibility] = savedVisibility
      appState.isSearchFocused = savedFocus
      appState.history.searchQuery = savedQuery
    }
    appState.history.searchQuery = ""
    Defaults[.showSearch] = false
    appState.isSearchFocused = false
    XCTAssertFalse(appState.searchVisible)
    appState.isSearchFocused = true
    XCTAssertTrue(appState.searchVisible)
    Defaults[.showSearch] = true
    Defaults[.searchVisibility] = .duringSearch
    XCTAssertTrue(appState.searchVisible)
    appState.isSearchFocused = false
    XCTAssertFalse(appState.searchVisible)
  }
}
