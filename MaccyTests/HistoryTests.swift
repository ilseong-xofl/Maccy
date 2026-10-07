import XCTest
import Defaults
import SwiftData
@testable import Maccy

@MainActor
class HistoryTests: XCTestCase { // swiftlint:disable:this type_body_length
  let savedSize = Defaults[.size]
  let savedSortBy = Defaults[.sortBy]
  let savedPinOrder = Defaults[.pinOrder]
  let savedPinTo = Defaults[.pinTo]
  let history = History.shared

  override func setUp() {
    super.setUp()
    history.clearAll()
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
    Defaults[.pinOrder] = PinOrder()
    Defaults[.pinTo] = .bottom
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    Defaults[.pinOrder] = savedPinOrder
    Defaults[.pinTo] = savedPinTo
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.items.toArray(), [])
  }

  func testAdding() {
    let first = history.add(historyItem("foo"))
    let second = history.add(historyItem("bar"))
    XCTAssertEqual(history.items.toArray(), [second, first])
  }

  func testAddingPersistedDuplicate() throws {
    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    history.add(first)
    first.pin = "f"

    let third = historyItem("foo")
    third.application = "Xcode.app"
    let transferredContents = first.contents
    let merged = history.add(third)

    XCTAssertEqual(history.items.toArray(), [merged])
    XCTAssertEqual(Set(merged.item.contents), Set(transferredContents))
    XCTAssertTrue(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
    XCTAssertEqual(merged.item.numberOfCopies, 2)
    XCTAssertEqual(merged.item.pin, "f")
    XCTAssertEqual(merged.item.title, "xyz")
    XCTAssertEqual(merged.item.application, "iTerm.app")
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testAddingUnsavedDuplicate() throws {
    guard #available(macOS 15.0, *) else {
      throw XCTSkip("Incoming history items are inserted before add on macOS 14")
    }

    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    history.add(first)
    first.pin = "f"

    let second = historyItem("foo", persisted: false)
    second.application = "Xcode.app"
    let transferredContents = first.contents
    let merged = history.add(second)

    XCTAssertEqual(history.items.toArray(), [merged])
    XCTAssertEqual(Set(merged.item.contents), Set(transferredContents))
    XCTAssertTrue(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
    XCTAssertEqual(merged.item.numberOfCopies, 2)
    XCTAssertEqual(merged.item.pin, "f")
    XCTAssertEqual(merged.item.title, "xyz")
    XCTAssertEqual(merged.item.application, "iTerm.app")
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testAddingItemThatIsSupersededByExisting() throws {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.rtf.rawValue,
        value: "two".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.application = "Maccy.app"
    firstItem.contents = firstContents
    firstItem.title = firstItem.generateTitle()
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.application = "Maccy.app"
    secondItem.contents = secondContents
    secondItem.title = secondItem.generateTitle()
    let second = history.add(secondItem)

    XCTAssertEqual(history.items.toArray(), [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
    try assertStorageCounts(items: 1, contents: firstContents.count)
  }

  func testAddingItemWithDifferentModifiedType() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "1".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.contents = firstContents
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "2".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.contents = secondContents
    let second = history.add(secondItem)

    XCTAssertEqual(history.items.toArray(), [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemFromMaccy() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      )
    ]
    let first = HistoryItem()
    Storage.shared.context.insert(first)
    first.application = "Xcode.app"
    first.contents = firstContents
    history.add(first)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fromMaccy.rawValue,
        value: "".data(using: .utf8)
      )
    ]
    let second = HistoryItem()
    Storage.shared.context.insert(second)
    second.application = "Maccy.app"
    second.contents = secondContents
    let secondDecorator = history.add(second)

    XCTAssertEqual(history.items.toArray(), [secondDecorator])
    XCTAssertEqual(history.items[0].item.application, "Xcode.app")
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testModifiedAfterCopying() {
    history.add(historyItem("foo"))

    let modifiedItem = historyItem("bar")
    modifiedItem.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: String(Clipboard.shared.changeCount).data(using: .utf8)
    ))
    let modifiedItemDecorator = history.add(modifiedItem)

    XCTAssertEqual(history.items.toArray(), [modifiedItemDecorator])
    XCTAssertEqual(history.items[0].text, "bar")
  }

  func testClearingUnpinned() throws {
    let pinned = history.add(historyItem("foo"))
    history.togglePin(pinned)
    history.add(historyItem("bar"))
    let orphan = HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: "orphan".data(using: .utf8)
    )
    Storage.shared.context.insert(orphan)
    try Storage.shared.context.save()

    history.clear()

    XCTAssertEqual(history.items.toArray(), [pinned])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testClearingAll() throws {
    history.add(historyItem("foo"))
    let pinned = history.add(historyItem("bar"))
    history.togglePin(pinned)
    Storage.shared.context.insert(HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: "orphan".data(using: .utf8)
    ))
    try Storage.shared.context.save()

    history.clearAll()

    XCTAssertEqual(history.items.toArray(), [])
    try assertStorageCounts(items: 0, contents: 0)
  }

  func testMaxSize() throws {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 10)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[0]))
    try assertStorageCounts(items: 10, contents: 10)
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItemDecorator] = []

    let item = history.add(historyItem("0"))
    items.append(item)
    history.togglePin(item)

    for index in 1...11 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 11)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertTrue(history.items.contains(items[0]))
    XCTAssertFalse(history.items.contains(items[1]))
  }

  func testPinAndUnpinScrollToItemAndUpdateShortcutsImmediately() throws {
    let savedNavigator = AppState.shared.navigator
    let navigator = NavigationManager(history: history, footer: Footer())
    AppState.shared.navigator = navigator
    defer { AppState.shared.navigator = savedNavigator }
    let item = history.add(historyItem("Pinned target"))
    let other = history.add(historyItem("Another item"))
    navigator.selectWithoutScrolling(item: item)
    navigator.addToSelection(item: other)
    let selection = navigator.selection.items

    history.togglePin(item)

    let pin = try XCTUnwrap(item.item.pin)
    XCTAssertEqual(navigator.scrollTarget, item.id)
    XCTAssertEqual(navigator.selection.items, selection)
    XCTAssertEqual(item.shortcuts.map(\.key), KeyShortcut.create(character: pin).map(\.key))
    XCTAssertEqual(other.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))

    navigator.scrollTarget = nil
    history.togglePin(item)

    XCTAssertNil(item.item.pin)
    XCTAssertEqual(navigator.scrollTarget, item.id)
    XCTAssertEqual(navigator.selection.items, selection)
    XCTAssertEqual(item.shortcuts.map(\.key), KeyShortcut.create(character: "2").map(\.key))
  }

  func testFirstVisibleItemRespectsTopAndBottomPinPlacement() {
    let pinned = history.add(historyItem("Pinned item"))
    history.togglePin(pinned)
    let unpinned = history.add(historyItem("Latest ordinary item"))

    Defaults[.pinTo] = .top
    XCTAssertEqual(history.firstVisibleItem, pinned)
    XCTAssertEqual(history.items.toArray(), [pinned, unpinned])
    Defaults[.pinTo] = .bottom
    XCTAssertEqual(history.firstVisibleItem, unpinned)
    XCTAssertEqual(history.items.toArray(), [unpinned, pinned])
    history.delete(unpinned)
    XCTAssertEqual(history.firstVisibleItem, pinned)
  }

  func testOrdinarySearchClearSelectsFirstVisibleItemForPinPlacement() async throws {
    let savedNavigator = AppState.shared.navigator
    let navigator = NavigationManager(history: history, footer: Footer())
    AppState.shared.navigator = navigator
    defer { AppState.shared.navigator = savedNavigator }
    let pinned = history.add(historyItem("Pinned item"))
    history.togglePin(pinned)
    let target = history.add(historyItem("Search target"))
    let latest = history.add(historyItem("Latest ordinary item"))

    for placement in [PinsPosition.top, .bottom] {
      Defaults[.pinTo] = placement
      history.searchQuery = "Search target"
      try await Task.sleep(for: .milliseconds(300))
      XCTAssertEqual(navigator.leadHistoryItem, target)

      history.searchQuery = ""
      try await Task.sleep(for: .milliseconds(300))

      let expected = placement == .top ? pinned : latest
      XCTAssertEqual(navigator.leadHistoryItem, expected)
      XCTAssertEqual(history.firstVisibleItem, expected)
    }
  }

  func testPinAndUnpinDuringSearchPreserveSelectionAndScrollAfterThrottle() async throws {
    let savedNavigator = AppState.shared.navigator
    let navigator = NavigationManager(history: history, footer: Footer())
    AppState.shared.navigator = navigator
    defer { AppState.shared.navigator = savedNavigator }
    let first = history.add(historyItem("Search target first"))
    let second = history.add(historyItem("Search target second"))
    history.add(historyItem("Most recent item outside search"))
    Defaults[.pinTo] = .top

    for wasPinned in [false, true] {
      history.searchQuery = "Search target"
      try await Task.sleep(for: .milliseconds(300))
      navigator.selectWithoutScrolling(item: first)
      navigator.addToSelection(item: second)
      let selection = navigator.selection.items
      XCTAssertEqual(first.isPinned, wasPinned)

      history.togglePin(first)
      XCTAssertEqual(navigator.scrollTarget, first.id)
      try await Task.sleep(for: .milliseconds(300))

      XCTAssertTrue(history.searchQuery.isEmpty)
      XCTAssertEqual(navigator.selection.items, selection)
      XCTAssertEqual(navigator.leadHistoryItem, second)
      // The hosted list may already have consumed the one-shot scroll target.
      XCTAssertEqual(first.isPinned, !wasPinned)
    }
  }

  func testPinChangesPersistWithoutChangingLinkSnapshotOrClipboardContents() throws {
    let source = "https://example.com/pin-preserves-preview"
    let item = history.add(historyItem(source))
    item.item.contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue,
                                               value: Data("<a href='\(source)'>Original link</a>".utf8)))
    let snapshot = try linkSnapshot(for: item.item)
    item.item.linkPreviewSnapshot = snapshot
    let originalContents = Dictionary(uniqueKeysWithValues: item.item.contents.map { ($0.type, $0.value) })
    let generation = item.item.linkPreviewGeneration

    for shouldBePinned in [true, false] {
      history.togglePin(item)

      let reader = ModelContext(Storage.shared.container)
      let saved = try XCTUnwrap(reader.model(for: item.item.persistentModelID) as? HistoryItem)
      XCTAssertEqual(saved.pin != nil, shouldBePinned)
      XCTAssertEqual(saved.linkPreviewSnapshot, snapshot)
      XCTAssertEqual(saved.text, source)
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: saved.contents.map { ($0.type, $0.value) }), originalContents)
      XCTAssertEqual(item.item.linkPreviewGeneration, generation)
    }
  }

  func testPinningUpdatesPinOrder() {
    let item = history.add(historyItem("foo"))
    history.togglePin(item)

    XCTAssertEqual(history.pinnedItems, [item])
    XCTAssertEqual(Defaults[.pinOrder].pins, [item.item.pin].compactMap { $0 })
  }

  func testPinningAfterAllShortcutsAreAssigned() async throws {
    let supportedPins = HistoryItem.supportedPins
    for index in 0..<supportedPins.count {
      let item = history.add(historyItem("keyed \(index)"))
      history.togglePin(item)
    }

    XCTAssertTrue(history.availablePins.isEmpty)
    XCTAssertEqual(Set(history.pinnedItems.compactMap(\.item.pin)), supportedPins)

    let first = history.add(historyItem("first without shortcut"))
    history.togglePin(first)
    let second = history.add(historyItem("second without shortcut"))
    history.togglePin(second)

    XCTAssertEqual(first.item.pin, "")
    XCTAssertEqual(second.item.pin, "")
    XCTAssertEqual(history.pinnedItems.suffix(2), [first, second])
    XCTAssertTrue(history.unpinnedItems.isEmpty)

    for index in 0...Defaults[.size] {
      history.add(historyItem("unpinned \(index)"))
    }

    let expectedCount = supportedPins.count + 2
    XCTAssertEqual(history.pinnedItems.count, expectedCount)
    try assertStorageCounts(
      items: expectedCount + Defaults[.size],
      contents: expectedCount + Defaults[.size]
    )

    try await history.load()
    XCTAssertEqual(history.pinnedItems.count, expectedCount)
    XCTAssertEqual(
      Set(history.pinnedItems.filter { $0.item.pin == "" }.map(\.title)),
      ["first without shortcut", "second without shortcut"]
    )
  }

  func testUnpinningUpdatesPinOrder() {
    let item = history.add(historyItem("foo"))
    history.togglePin(item)
    history.togglePin(item)

    XCTAssertEqual(history.pinnedItems, [])
    XCTAssertEqual(Defaults[.pinOrder].pins, [])
  }

  func testMovingPinsUpdatesPinOrder() {
    let first = history.add(historyItem("foo"))
    let second = history.add(historyItem("bar"))
    history.togglePin(first)
    history.togglePin(second)

    history.movePin(from: IndexSet(integer: 0), to: 2)

    XCTAssertEqual(history.pinnedItems, [second, first])
    XCTAssertEqual(Defaults[.pinOrder].pins, [second.item.pin, first.item.pin].compactMap { $0 })
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }
    Defaults[.size] = 5
    history.add(historyItem("11"))

    XCTAssertEqual(history.items.count, 5)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[5]))
  }

  func testReaddingBottomMostPinnedItemAtFullCapacity() {
    // Regression test for a crash when re-copying (invoking) the bottom-most
    // pinned item while history is at full capacity and pins are sorted to the
    // bottom. The stale insert index used to trap with an out-of-bounds insert.
    // Issue link: https://github.com/p0deje/Maccy/issues/1466
    // `pinTo` is restored to its default value(.top) in `tearDown`.
    Defaults[.pinTo] = .bottom

    // Pin an item; `history.togglePin` re-sorts `all`, so with `.bottom` the
    // pinned item ends up as the last element.
    let pinned = history.add(historyItem("pinned"))
    history.togglePin(pinned)

    // Fill unpinned history to full capacity.
    for index in 0..<Defaults[.size] {
      history.add(historyItem(String(index)))
    }

    XCTAssertEqual(history.items.last, pinned)

    // Re-copy the pinned item. It is detected as a duplicate, removed and
    // re-inserted while `limitHistorySize` trims an exceeding unpinned item.
    // Before the fix this inserted at a stale, out-of-bounds index and crashed.
    let readded = history.add(historyItem("pinned"))

    XCTAssertTrue(history.items.contains(readded))
    XCTAssertEqual(history.items.filter(\.isPinned).count, 1)
  }

  func testRemoving() throws {
    let foo = history.add(historyItem("foo"))
    let bar = history.add(historyItem("bar"))
    history.delete(foo)
    XCTAssertEqual(history.items.toArray(), [bar])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testCleaningUpOrphanedContents() throws {
    let live = history.add(historyItem("live"))
    let liveContent = live.item.contents[0]
    for value in ["orphan-1", "orphan-2"] {
      Storage.shared.context.insert(HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      ))
    }
    try Storage.shared.context.save()

    XCTAssertEqual(try Storage.shared.cleanupOrphanedContents(), 2)
    XCTAssertEqual(try Storage.shared.cleanupOrphanedContents(), 0)
    XCTAssertEqual(live.item.contents, [liveContent])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testRemovingUnpersistableContents() throws {
    let live = history.add(historyItem("live"))
    live.item.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.safariWebArchve.rawValue,
      value: Data(repeating: 0x61, count: 1024)
    ))
    try Storage.shared.context.save()

    XCTAssertEqual(try Storage.shared.removeUnpersistableContents(), 1)
    XCTAssertEqual(try Storage.shared.removeUnpersistableContents(), 0)
    XCTAssertEqual(live.item.contents.map(\.type), [NSPasteboard.PasteboardType.string.rawValue])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testDeletingLinkInvalidatesGenerationAndRemovesSnapshotOwner() throws {
    let item = history.add(historyItem("https://example.com/deleted"))
    item.item.linkPreviewSnapshot = try linkSnapshot(for: item.item)
    let generation = item.item.linkPreviewGeneration

    history.delete(item)

    XCTAssertNotEqual(item.item.linkPreviewGeneration, generation)
    XCTAssertTrue(history.items.isEmpty)
    try assertStorageCounts(items: 0, contents: 0)
  }

  func testHistorySizeEvictionInvalidatesLinkGeneration() throws {
    Defaults[.size] = 1
    let expired = history.add(historyItem("https://example.com/expired"))
    expired.item.linkPreviewSnapshot = try linkSnapshot(for: expired.item)
    let generation = expired.item.linkPreviewGeneration

    let current = history.add(historyItem("https://example.com/current"))

    XCTAssertNotEqual(expired.item.linkPreviewGeneration, generation)
    XCTAssertEqual(history.items.toArray(), [current])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testClearInvalidatesUnpinnedLinksAndKeepsPinnedSnapshot() throws {
    let pinned = history.add(historyItem("https://example.com/pinned"))
    let pinnedSnapshot = try linkSnapshot(for: pinned.item)
    pinned.item.linkPreviewSnapshot = pinnedSnapshot
    history.togglePin(pinned)
    let pinnedGeneration = pinned.item.linkPreviewGeneration
    let unpinned = history.add(historyItem("https://example.com/unpinned"))
    unpinned.item.linkPreviewSnapshot = try linkSnapshot(for: unpinned.item)
    let unpinnedGeneration = unpinned.item.linkPreviewGeneration

    history.clear()

    XCTAssertEqual(history.items.toArray(), [pinned])
    XCTAssertEqual(pinned.item.linkPreviewGeneration, pinnedGeneration)
    XCTAssertEqual(pinned.item.linkPreviewSnapshot, pinnedSnapshot)
    XCTAssertNotEqual(unpinned.item.linkPreviewGeneration, unpinnedGeneration)
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testClearAllInvalidatesPinnedAndUnpinnedLinkGenerations() throws {
    let pinned = history.add(historyItem("https://example.com/pinned"))
    pinned.item.linkPreviewSnapshot = try linkSnapshot(for: pinned.item)
    history.togglePin(pinned)
    let pinnedGeneration = pinned.item.linkPreviewGeneration
    let unpinned = history.add(historyItem("https://example.com/unpinned"))
    unpinned.item.linkPreviewSnapshot = try linkSnapshot(for: unpinned.item)
    let unpinnedGeneration = unpinned.item.linkPreviewGeneration

    history.clearAll()

    XCTAssertTrue(history.items.isEmpty)
    XCTAssertNotEqual(pinned.item.linkPreviewGeneration, pinnedGeneration)
    XCTAssertNotEqual(unpinned.item.linkPreviewGeneration, unpinnedGeneration)
    try assertStorageCounts(items: 0, contents: 0)
  }

  func testRecopyingLinkInheritsSnapshotAfterTransferringContents() throws {
    let source = "https://example.com/recopied"
    let first = history.add(historyItem(source))
    let snapshot = try linkSnapshot(for: first.item)
    first.item.linkPreviewSnapshot = snapshot
    first.item.title = "Saved project"
    let generation = first.item.linkPreviewGeneration
    let originalContents = Set(first.item.contents)

    let recopied = history.add(historyItem(source))

    XCTAssertNotEqual(first.item.linkPreviewGeneration, generation)
    XCTAssertEqual(recopied.item.linkPreviewSnapshot, snapshot)
    XCTAssertEqual(recopied.item.linkPreviewSourceURL?.absoluteString, source)
    XCTAssertEqual(recopied.item.title, "Saved project")
    XCTAssertEqual(Set(recopied.item.contents), originalContents)
    XCTAssertEqual(recopied.item.numberOfCopies, 2)

    // Read through a separate context before any test helper saves the main context.
    // The initial insert alone would leave both rows and an empty new snapshot.
    let reloadedContext = ModelContext(Storage.shared.container)
    let savedItems = try reloadedContext.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(savedItems.count, 1)
    let saved = try XCTUnwrap(savedItems.first)
    XCTAssertEqual(saved.persistentModelID, recopied.item.persistentModelID)
    XCTAssertEqual(saved.linkPreviewSnapshot, snapshot)
    XCTAssertEqual(saved.text, source)
    XCTAssertEqual(saved.title, "Saved project")
    XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<HistoryItemContent>()), 1)
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testModifiedLinkReplacementDoesNotInheritOldURLSnapshot() throws {
    let first = history.add(historyItem("https://example.com/original"))
    first.item.linkPreviewSnapshot = try linkSnapshot(for: first.item)
    let generation = first.item.linkPreviewGeneration
    let changed = historyItem("https://example.com/changed")
    changed.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: Data(String(Clipboard.shared.changeCount).utf8)
    ))

    let replacement = history.add(changed)

    XCTAssertEqual(history.items.toArray(), [replacement])
    XCTAssertNil(replacement.item.linkPreviewSnapshot)
    XCTAssertEqual(replacement.item.linkPreviewSourceURL?.absoluteString, "https://example.com/changed")
    XCTAssertNotEqual(first.item.linkPreviewGeneration, generation)
    XCTAssertEqual(replacement.item.text, "https://example.com/changed")
  }

  func testRecopyDoesNotInheritSnapshotForDifferentSourceURL() throws {
    let source = "https://example.com/recopied"
    let first = history.add(historyItem(source))
    first.item.linkPreviewSnapshot = try XCTUnwrap(LinkPreviewSnapshot.encode(
      .failure(.notFound), sourceURL: URL(string: "https://example.com/unrelated")!
    ))

    let replacement = history.add(historyItem(source))

    XCTAssertNil(replacement.item.linkPreviewSnapshot)
    XCTAssertEqual(replacement.item.text, source)
  }

  func testEditingLinkSourceClearsSnapshotAndInvalidatesGeneration() throws {
    for (index, text) in ["https://example.com/changed", "A plain text note"].enumerated() {
      let item = history.add(historyItem("https://example.com/original-\(index)"))
      item.item.linkPreviewSnapshot = try linkSnapshot(for: item.item)
      let generation = item.item.linkPreviewGeneration

      ItemEditorView.updateTextContent(of: item, to: Data(text.utf8))

      XCTAssertNil(item.item.linkPreviewSnapshot)
      XCTAssertNotEqual(item.item.linkPreviewGeneration, generation)
      XCTAssertEqual(item.item.text, text)
    }
  }

  func testEditingSameLinkOrAliasKeepsSnapshotAndGeneration() throws {
    let source = "https://example.com/unchanged"
    let item = history.add(historyItem(source))
    let snapshot = try linkSnapshot(for: item.item)
    item.item.linkPreviewSnapshot = snapshot
    let generation = item.item.linkPreviewGeneration
    item.item.title = "Personal alias"

    ItemEditorView.updateTextContent(of: item, to: Data("  \(source)\n".utf8))

    XCTAssertEqual(item.item.linkPreviewSourceURL?.absoluteString, source)
    XCTAssertEqual(item.item.linkPreviewSnapshot, snapshot)
    XCTAssertEqual(item.item.linkPreviewGeneration, generation)
    XCTAssertEqual(item.item.title, "Personal alias")
  }

  private func linkSnapshot(for item: HistoryItem) throws -> Data {
    let url = try XCTUnwrap(item.linkPreviewSourceURL)
    return try XCTUnwrap(LinkPreviewSnapshot.encode(
      .preview(ClipboardLinkPreview(url: url, title: "Saved preview", image: nil)), sourceURL: url
    ))
  }

  private func assertStorageCounts(
    items: Int,
    contents: Int,
    orphaned: Int = 0,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let context = Storage.shared.context
    context.processPendingChanges()
    try context.save()
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItem>()),
      items,
      file: file,
      line: line
    )
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItemContent>()),
      contents,
      file: file,
      line: line
    )
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItemContent>(
        predicate: #Predicate { $0.item == nil }
      )),
      orphaned,
      file: file,
      line: line
    )
  }

  private func historyItem(_ value: String, persisted: Bool = true) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    if persisted {
      Storage.shared.context.insert(item)
    }
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}
