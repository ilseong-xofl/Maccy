import XCTest
import Defaults
import SwiftUI
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

  func testImage() {
    let image = NSImage(named: "StatusBarMenuImage")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertEqual(itemDecorator.previewImage!.size, image.size)
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, image.size)
  }

  // We also need to add test for image with width bigger than max width.
  func testImageWithHeightBiggerThanMaxHeight() {
    let image = NSImage(named: "NSApplicationIcon")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, NSSize(width: 40, height: 40))
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

      XCTAssertEqual(accepted.width, AppState.shared.preview.minimumContentWidth, accuracy: 1)
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

  func testCompletedResizeSavesFinalListSizeWithoutSidecarWidth() {
    withRestoredWindowState {
      let panel = makePanel(size: NSSize(width: 820, height: 500))
      let preview = AppState.shared.preview
      preview.state = .open
      preview.contentWidth = 640
      preview.slideoutWidth = 400
      preview.contentResizeWidth = 420
      preview.slideoutResizeWidth = 400
      preview.resizingMode = .content

      panel.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))

      XCTAssertEqual(preview.contentWidth, 420, accuracy: 1)
      XCTAssertEqual(Defaults[.windowSize].width, 420, accuracy: 1)
      XCTAssertEqual(Defaults[.windowSize].height, panel.frame.height, accuracy: 1)
      XCTAssertEqual(preview.slideoutWidth, 400, accuracy: 1)
    }
  }

  private func makePanel(size: NSSize = NSSize(width: 640, height: 700)) -> FloatingPanel<AnyView> {
    FloatingPanel(contentRect: NSRect(origin: .zero, size: size), onClose: {}) {
      AnyView(Text("Fixed-width content").frame(width: 640))
    }
  }

  private func withRestoredWindowState(_ test: () -> Void) {
    let preview = AppState.shared.preview
    let popup = AppState.shared.popup
    let savedSize = Defaults[.windowSize]
    let savedPosition = Defaults[.windowPosition]
    let savedPreviewWidth = Defaults[.previewWidth]
    let savedAutoOpen = Defaults[.openPreviewAutomatically]
    let savedState = preview.state
    let savedMode = preview.resizingMode
    let savedContentWidth = preview.contentWidth
    let savedSlideoutWidth = preview.slideoutWidth
    let savedContentResizeWidth = preview.contentResizeWidth
    let savedSlideoutResizeWidth = preview.slideoutResizeWidth
    let savedHeaderHeight = popup.headerHeight
    let savedFooterHeight = popup.footerHeight
    let savedExtraTopHeight = popup.extraTopHeight
    let savedExtraBottomHeight = popup.extraBottomHeight
    defer {
      preview.state = savedState
      preview.resizingMode = savedMode
      preview.contentWidth = savedContentWidth
      preview.slideoutWidth = savedSlideoutWidth
      preview.contentResizeWidth = savedContentResizeWidth
      preview.slideoutResizeWidth = savedSlideoutResizeWidth
      popup.headerHeight = savedHeaderHeight
      popup.footerHeight = savedFooterHeight
      popup.extraTopHeight = savedExtraTopHeight
      popup.extraBottomHeight = savedExtraBottomHeight
      Defaults[.windowSize] = savedSize
      Defaults[.windowPosition] = savedPosition
      Defaults[.previewWidth] = savedPreviewWidth
      Defaults[.openPreviewAutomatically] = savedAutoOpen
    }

    Defaults[.openPreviewAutomatically] = false
    preview.state = .closed
    preview.resizingMode = .none
    popup.headerHeight = 0
    popup.footerHeight = 0
    popup.extraTopHeight = 0
    popup.extraBottomHeight = 0
    test()
  }
}
