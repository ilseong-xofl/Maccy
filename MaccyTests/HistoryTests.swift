import XCTest
import Defaults
import SwiftData
import Sauce
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

    XCTAssertNotNil(item.item.pin)
    XCTAssertEqual(navigator.scrollTarget, item.id)
    XCTAssertEqual(navigator.selection.items, selection)
    XCTAssertTrue(item.shortcuts.isEmpty)
    XCTAssertEqual(other.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))

    navigator.scrollTarget = nil
    history.togglePin(item)

    XCTAssertNil(item.item.pin)
    XCTAssertEqual(navigator.scrollTarget, item.id)
    XCTAssertEqual(navigator.selection.items, selection)
    XCTAssertEqual(item.shortcuts.map(\.key), KeyShortcut.create(character: "2").map(\.key))
  }

  func testPinnedShortcutRemovalSurvivesObservationReloadAndRecopyThenUnpinRestoresNumbers() async throws {
    let item = history.add(historyItem("Pinned shortcut lifecycle"))
    history.togglePin(item)
    let pin = try XCTUnwrap(item.item.pin)
    let pinOrder = Defaults[.pinOrder]
    XCTAssertTrue(item.shortcuts.isEmpty)
    await drainPinObservation()
    XCTAssertTrue(item.shortcuts.isEmpty)

    try await history.load()
    let reloaded = try XCTUnwrap(history.firstPinnedItem)
    XCTAssertEqual(reloaded.item.pin, pin)
    XCTAssertEqual(Defaults[.pinOrder], pinOrder)
    XCTAssertTrue(reloaded.shortcuts.isEmpty)

    let replacement = history.add(historyItem("Pinned shortcut lifecycle"))
    XCTAssertEqual(replacement.item.pin, pin)
    XCTAssertEqual(Defaults[.pinOrder], pinOrder)
    XCTAssertEqual(history.pinnedItems, [replacement])
    XCTAssertTrue(replacement.shortcuts.isEmpty)
    await drainPinObservation()
    XCTAssertTrue(replacement.shortcuts.isEmpty)

    history.togglePin(replacement)
    XCTAssertNil(replacement.item.pin)
    XCTAssertEqual(replacement.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))
    await drainPinObservation()
    XCTAssertEqual(replacement.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))
  }

  func testAddingAlreadyPinnedItemDoesNotAssignLetterShortcuts() {
    let item = historyItem("Stored pinned item")
    item.pin = "b"
    let added = history.add(item)
    XCTAssertEqual(added.item.pin, "b")
    XCTAssertTrue(added.shortcuts.isEmpty)
    XCTAssertEqual(Defaults[.pinOrder].pins, ["b"])
  }

  private func drainPinObservation() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
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


@MainActor
final class NumericClipboardShortcutTests: XCTestCase {
  func testNumericLabelHasOnePlainDefaultWhileModifiedNumericShortcutsRemain() throws {
    let shortcuts = KeyShortcut.create(character: "1")
    let visible = shortcuts.filter { $0.isVisible(shortcuts, [.capsLock, .numericPad]) }
    XCTAssertEqual(visible.count, 1)
    XCTAssertEqual(visible.first?.modifierFlags, [])
    XCTAssertFalse(try XCTUnwrap(visible.first).description.contains("⌘"))
    for flags: NSEvent.ModifierFlags in [[.command], [.option]] {
      let modified = shortcuts.filter { $0.isVisible(shortcuts, flags) }
      XCTAssertEqual(modified.count, 1)
      XCTAssertEqual(modified.first?.modifierFlags, flags)
    }
  }

  func testPlainDigitsAlwaysCopyOriginalFormatsForEveryDefaultCombination() async throws {
    try await withHistory { history in
      for paste in [false, true] {
        for removeFormatting in [false, true] {
          Defaults[.pasteByDefault] = paste
          Defaults[.removeFormattingByDefault] = removeFormatting
          let expected = try XCTUnwrap(history.firstUnpinnedItem)
          let originalContents = expected.item.contents.map { ($0.type, $0.value) }
          let activation = try XCTUnwrap(history.shortcutActivation(for: keyEvent("1"), context: .init()))
          XCTAssertEqual(activation.item.id, expected.id)
          XCTAssertEqual(activation.action, .copy)
          XCTAssertFalse(activation.pastes)
          XCTAssertFalse(activation.removesFormatting)
          XCTAssertEqual(expected.item.contents.map(\.type), originalContents.map(\.0))
          XCTAssertEqual(expected.item.contents.map(\.value), originalContents.map(\.1))
          XCTAssertEqual(Set(expected.item.contents.map(\.type)), Set([
            NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.html.rawValue
          ]))
        }
      }
    }
  }

  func testDigitsOneThroughNineResolveUnpinnedRowsEvenWhenPinIsFirst() async throws {
    try await withHistory { history in
      XCTAssertTrue(try XCTUnwrap(history.firstVisibleItem).isPinned)
      for digit in 1...9 {
        let activation = try XCTUnwrap(history.shortcutActivation(for: keyEvent(String(digit)), context: .init()))
        XCTAssertEqual(activation.item.id, history.unpinnedItems[digit - 1].id)
      }
      XCTAssertTrue(history.unpinnedItems[9].shortcuts.isEmpty)
      XCTAssertNil(history.shortcutActivation(for: keyEvent("0"), context: .init()))
      history.unpinnedItems[0].isVisible = false
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1"), context: .init()))
    }
  }

  func testKeypadAndCapsLockCopyTheSameRow() async throws {
    try await withHistory { history in
      let event = keyEvent("1", flags: [.numericPad, .capsLock, .function], keyCode: 83)
      let activation = try XCTUnwrap(history.shortcutActivation(for: event, context: .init()))
      XCTAssertEqual(activation.item.id, history.firstUnpinnedItem?.id)
      XCTAssertEqual(activation.action, .copy)
      let modified = try XCTUnwrap(history.shortcutActivation(
        for: keyEvent("1", flags: [.command, .numericPad, .capsLock], keyCode: 83), context: .init()))
      XCTAssertEqual(modified.item.id, activation.item.id)
      XCTAssertEqual(modified.action, HistoryItemAction(.command))
    }
  }

  func testTypingContextsDoNotActivatePlainNumericShortcuts() async throws {
    try await withHistory { history in
      let contexts: [History.ShortcutInputContext] = [
        .init(isSearchFocused: true), .init(isEditingItem: true), .init(isEditableText: true),
        .init(hasMarkedText: true), .init(hasModal: true),
        .init(isSearchFocused: true, isEditableText: true, hasMarkedText: true)
      ]
      for context in contexts {
        XCTAssertNil(history.shortcutActivation(for: keyEvent("1"), context: context))
      }
      // Modifier-independent input modes must also reject the older shortcuts.
      for context in contexts.dropFirst() {
        XCTAssertNil(history.shortcutActivation(for: keyEvent("1", flags: [.command]), context: context))
      }
    }
  }

  func testSearchAllowsLegacyModifiedShortcutsWhileKeepingTypedNumbers() async throws {
    try await withHistory { history in
      let context = History.ShortcutInputContext(isSearchFocused: true, isEditableText: true)
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1"), context: context))
      for flags: NSEvent.ModifierFlags in [[.command], [.option], [.option, .shift]] {
        let activation = try XCTUnwrap(history.shortcutActivation(for: keyEvent("1", flags: flags), context: context))
        XCTAssertEqual(activation.item.id, history.firstUnpinnedItem?.id)
        XCTAssertEqual(activation.action, HistoryItemAction(flags))
      }
    }
  }

  func testPinnedRowsRejectLegacyLetterShortcutsEvenWithStaleBindingsAndSearchFocus() async throws {
    try await withHistory { history in
      let pinned = try XCTUnwrap(history.firstPinnedItem)
      XCTAssertEqual(pinned.item.pin, "b")
      XCTAssertTrue(pinned.shortcuts.isEmpty)
      pinned.shortcuts = KeyShortcut.create(character: "b")
      for context: History.ShortcutInputContext in [.init(), .init(isSearchFocused: true, isEditableText: true)] {
        for flags: NSEvent.ModifierFlags in [[], [.command], [.option], [.option, .shift]] {
          XCTAssertNil(history.shortcutActivation(for: keyEvent("b", flags: flags), context: context))
        }
      }
      // Stale numbered bindings cannot make a pinned row steal the first ordinary row either.
      pinned.shortcuts = KeyShortcut.create(character: "1")
      for flags: NSEvent.ModifierFlags in [[], [.command], [.option]] {
        XCTAssertEqual(history.shortcutActivation(for: keyEvent("1", flags: flags), context: .init())?.item.id,
                       history.firstUnpinnedItem?.id)
      }
    }
  }

  func testResolvedActionDoesNotChangeAfterModifiersOrDefaultsChange() async throws {
    try await withHistory { history in
      let copy = try XCTUnwrap(history.shortcutActivation(for: keyEvent("1", flags: [.command]), context: .init()))
      let paste = try XCTUnwrap(history.shortcutActivation(for: keyEvent("1", flags: [.option]), context: .init()))
      Defaults[.pasteByDefault] = true
      Defaults[.removeFormattingByDefault] = true
      XCTAssertEqual(copy.action, .copy)
      XCTAssertFalse(copy.pastes)
      XCTAssertFalse(copy.removesFormatting)
      XCTAssertEqual(paste.action, .paste)
      XCTAssertTrue(paste.pastes)
      XCTAssertFalse(paste.removesFormatting)
    }
  }

  func testNonDigitsAndUnsupportedModifiersNeverBecomePlainNumberCopy() async throws {
    try await withHistory { history in
      XCTAssertNil(history.shortcutActivation(for: nil, context: .init()))
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1", type: .keyUp), context: .init()))
      XCTAssertNil(history.shortcutActivation(for: keyEvent("!", keyCode: 18), context: .init()))
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1", flags: [.shift]), context: .init()))
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1", flags: [.control]), context: .init()))
      XCTAssertNil(history.shortcutActivation(for: keyEvent("1", flags: [.command, .option]), context: .init()))
    }
  }

  private func withHistory(_ verify: (History) throws -> Void) async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let savedContainer = Storage.shared.container
    let savedSize = Defaults[.size]
    let savedSortBy = Defaults[.sortBy]
    let savedPinTo = Defaults[.pinTo]
    let savedPinOrder = Defaults[.pinOrder]
    let savedPaste = Defaults[.pasteByDefault]
    let savedFormatting = Defaults[.removeFormattingByDefault]
    let savedNeedsResize = AppState.shared.popup.needsResize
    defer {
      Storage.shared.container = savedContainer
      Defaults[.size] = savedSize
      Defaults[.sortBy] = savedSortBy
      Defaults[.pinTo] = savedPinTo
      Defaults[.pinOrder] = savedPinOrder
      Defaults[.pasteByDefault] = savedPaste
      Defaults[.removeFormattingByDefault] = savedFormatting
      AppState.shared.popup.needsResize = savedNeedsResize
    }
    Storage.shared.container = container
    Defaults[.size] = 20
    Defaults[.sortBy] = .lastCopiedAt
    Defaults[.pinTo] = .top
    Defaults[.pinOrder] = PinOrder(pins: ["b"])
    Defaults[.pasteByDefault] = false
    Defaults[.removeFormattingByDefault] = false
    for index in 0...10 {
      let item = HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("Row \(index)".utf8)),
        HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: Data("<b>Row \(index)</b>".utf8))
      ])
      container.mainContext.insert(item)
      item.title = "Row \(index)"
      item.lastCopiedAt = Date(timeIntervalSince1970: Double(100 - index))
      if index == 10 { item.pin = "b" }
    }
    try container.mainContext.save()
    let history = History()
    try await history.load()
    await Task.yield()
    try verify(history)
  }

  private func keyEvent(
    _ character: String,
    flags: NSEvent.ModifierFlags = [],
    keyCode: UInt16? = nil,
    type: NSEvent.EventType = .keyDown
  ) -> NSEvent {
    let key = Key(character: character, virtualKeyCode: nil)
    return NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: character, charactersIgnoringModifiers: character, isARepeat: false,
      keyCode: keyCode ?? UInt16(key.map { Sauce.shared.keyCode(for: $0) } ?? 18)
    )!
  }
}


@MainActor
final class FavoriteHistoryTests: XCTestCase {
  // The hosted SwiftUI app can retain outgoing animated rows after a fixture returns.
  // Keep their in-memory stores alive until the test process exits.
  private static var retainedContainers: [ModelContainer] = []

  func testFavoritePersistsIndependentlyOfPinAndSessionFilter() async throws {
    try await withHistory { history in
      let item = try XCTUnwrap(history.firstUnpinnedItem)
      let modelID = item.item.id
      XCTAssertEqual(history.filter, .history)
      XCTAssertFalse(item.isFavorite)
      history.toggleFavorite(item)
      history.togglePin(item)
      XCTAssertTrue(item.isFavorite)
      XCTAssertTrue(item.isPinned)
      let freshContext = ModelContext(Storage.shared.container)
      let saved = try XCTUnwrap(freshContext.fetch(FetchDescriptor<HistoryItem>())
        .first { $0.id == modelID })
      XCTAssertTrue(saved.isFavorite)
      XCTAssertNotNil(saved.pin)
      history.filter = .favorites
      let reloaded = History()
      try await reloaded.load()
      XCTAssertEqual(reloaded.filter, .history)
      XCTAssertTrue(try XCTUnwrap(reloaded.items.first { $0.item.id == modelID }).isFavorite)
      history.togglePin(item)
      XCTAssertTrue(item.isFavorite)
      XCTAssertFalse(item.isPinned)
    }
  }

  func testFavoritesIntersectSearchAndReassignOnlyVisibleUnpinnedNumbers() async throws {
    try await withHistory { history in
      let originalItems = history.items.toArray()
      let alpha = try XCTUnwrap(originalItems.first { $0.title == "Alpha favorite" })
      let beta = try XCTUnwrap(originalItems.first { $0.title == "Beta favorite" })
      let ordinary = try XCTUnwrap(originalItems.first { $0.title == "Alpha ordinary" })
      let pinned = try XCTUnwrap(originalItems.first { $0.title == "Alpha pinned" })
      history.toggleFavorite(alpha)
      history.toggleFavorite(beta)
      history.togglePin(pinned)
      history.filter = .favorites
      XCTAssertEqual(Set(history.items.map(\.id)), Set([alpha.id, beta.id]))
      XCTAssertTrue(ordinary.shortcuts.isEmpty)
      XCTAssertTrue(pinned.shortcuts.isEmpty)
      XCTAssertEqual(alpha.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))
      XCTAssertEqual(beta.shortcuts.map(\.key), KeyShortcut.create(character: "2").map(\.key))

      history.toggleFavorite(pinned)
      history.searchQuery = "Alpha"
      try await Task.sleep(for: .milliseconds(250))
      XCTAssertEqual(Set(history.items.map(\.id)), Set([alpha.id, pinned.id]))
      XCTAssertTrue(beta.shortcuts.isEmpty)
      XCTAssertTrue(pinned.shortcuts.isEmpty)
      XCTAssertEqual(alpha.shortcuts.map(\.key), KeyShortcut.create(character: "1").map(\.key))
      history.filter = .history
      XCTAssertEqual(Set(history.items.map(\.id)), Set([alpha.id, ordinary.id, pinned.id]))
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), originalItems.count)
    }
  }

  func testFilterChangeRejectsCapturedShortcutAndPreservesUnfilteredLatestItem() async throws {
    try await withHistory { history in
      let latest = try XCTUnwrap(history.firstUnpinnedItem)
      let favorite = history.unpinnedItems[1]
      history.toggleFavorite(favorite)
      let event = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18))
      let captured = try XCTUnwrap(history.shortcutActivation(for: event, context: .init()))
      XCTAssertTrue(history.canActivateShortcut(captured))
      history.filter = .favorites
      XCTAssertFalse(history.canActivateShortcut(captured))
      XCTAssertEqual(history.firstUnfilteredUnpinnedItem?.id, latest.id)
      let filtered = try XCTUnwrap(history.shortcutActivation(for: event, context: .init()))
      XCTAssertEqual(filtered.item.id, favorite.id)
      XCTAssertTrue(history.canActivateShortcut(filtered))
      history.toggleFavorite(favorite)
      XCTAssertFalse(history.canActivateShortcut(filtered))
      XCTAssertNil(history.shortcutActivation(for: event, context: .init()))
    }
  }

  func testFilterAndUnfavoriteRemoveHiddenSelectionsAndEmptyLead() async throws {
    try await withHistory { history in
      let favorite = try XCTUnwrap(history.firstUnpinnedItem)
      let ordinary = history.unpinnedItems[1]
      history.toggleFavorite(favorite)
      let navigator = AppState.shared.navigator
      navigator.select(item: ordinary)
      history.filter = .favorites
      XCTAssertEqual(navigator.leadHistoryItem?.id, favorite.id)
      XCTAssertEqual(navigator.selection.items.map(\.id), [favorite.id])
      XCTAssertFalse(ordinary.isSelected)
      history.toggleFavorite(favorite)
      XCTAssertTrue(history.items.isEmpty)
      XCTAssertTrue(navigator.selection.isEmpty)
      XCTAssertNil(navigator.leadHistoryItem)
      XCTAssertFalse(AppState.shared.preview.isVisible)
      XCTAssertTrue(favorite.shortcuts.isEmpty)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 4)
    }
  }

  func testAutomaticLimitAndOrdinaryClearProtectFavoritesAndPins() async throws {
    try await withHistory { history in
      let favorite = try XCTUnwrap(history.items.first { $0.title == "Beta favorite" })
      let pinned = try XCTUnwrap(history.items.first { $0.title == "Alpha pinned" })
      history.toggleFavorite(favorite)
      history.togglePin(pinned)
      Defaults[.size] = 1
      try await history.load()
      XCTAssertEqual(history.items.count, 3)
      XCTAssertEqual(history.items.filter(\.isFavorite).count, 1)
      XCTAssertEqual(history.pinnedItems.count, 1)
      Storage.shared.context.insert(HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue, value: Data("Orphan".utf8)))
      try Storage.shared.context.save()
      history.filter = .favorites
      history.clear()
      history.filter = .history
      XCTAssertEqual(history.items.count, 2)
      XCTAssertEqual(history.items.filter(\.isFavorite).count, 1)
      XCTAssertEqual(history.pinnedItems.count, 1)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 2)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>()), 2)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>(
        predicate: #Predicate { $0.item == nil })), 0)
    }
  }

  func testDirectDeleteAndClearAllRemoveFavorites() async throws {
    try await withHistory { history in
      let first = try XCTUnwrap(history.firstUnpinnedItem)
      let second = history.unpinnedItems[1]
      history.toggleFavorite(first)
      history.toggleFavorite(second)
      history.togglePin(second)
      history.filter = .favorites
      history.delete(first)
      XCTAssertEqual(history.items.map(\.id), [second.id])
      history.clearAll()
      XCTAssertTrue(history.items.isEmpty)
      XCTAssertTrue(AppState.shared.navigator.selection.isEmpty)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 0)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>()), 0)
    }
  }

  func testRecopyInFavoritesPreservesSavedFavoritePinAndRawContents() async throws {
    try await withHistory { history in
      let item = try XCTUnwrap(history.firstUnpinnedItem)
      history.toggleFavorite(item)
      history.togglePin(item)
      let pin = item.item.pin
      let pinOrder = Defaults[.pinOrder]
      let raw = item.item.contents.compactMap(\.value)
      Defaults[.size] = 3
      history.filter = .favorites
      let incoming = HistoryItem(contents: [HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue, value: raw.first)])
      Storage.shared.context.insert(incoming)
      incoming.title = item.title
      let replacement = history.add(incoming)
      XCTAssertTrue(replacement.isFavorite)
      XCTAssertEqual(replacement.item.pin, pin)
      XCTAssertEqual(Defaults[.pinOrder], pinOrder)
      XCTAssertEqual(replacement.item.contents.compactMap(\.value), raw)
      XCTAssertEqual(history.items.map(\.id), [replacement.id])
      let freshContext = ModelContext(Storage.shared.container)
      let stored = try XCTUnwrap(freshContext.fetch(FetchDescriptor<HistoryItem>())
        .first { $0.id == replacement.item.id })
      XCTAssertTrue(stored.isFavorite)
      XCTAssertEqual(stored.pin, pin)
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 4)
    }
  }

  func testRemovingProtectionAppliesOrdinaryHistoryQuota() async throws {
    try await withHistory { history in
      let oldest = try XCTUnwrap(history.lastVisibleItem)
      history.toggleFavorite(oldest)
      history.togglePin(oldest)
      Defaults[.size] = 1
      try await history.load()
      let protected = try XCTUnwrap(history.firstPinnedItem)
      history.togglePin(protected)
      XCTAssertTrue(protected.isFavorite)
      XCTAssertEqual(history.items.count, 2)
      history.toggleFavorite(protected)
      XCTAssertEqual(history.items.count, 1)
      XCTAssertFalse(history.items.contains(protected))
      XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 1)
    }
  }

  private func withHistory(_ verify: (History) async throws -> Void) async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    Self.retainedContainers.append(container)
    let appState = AppState.shared
    let savedContainer = Storage.shared.container
    let savedHistory = appState.history
    let savedNavigator = appState.navigator
    let savedPreview = appState.preview
    let savedNeedsResize = appState.popup.needsResize
    let savedSize = Defaults[.size]
    let savedSortBy = Defaults[.sortBy]
    let savedPinTo = Defaults[.pinTo]
    let savedPinOrder = Defaults[.pinOrder]
    let savedSearchMode = Defaults[.searchMode]
    let savedClearSystemClipboard = Defaults[.clearSystemClipboard]
    defer {
      Storage.shared.container = savedContainer
      appState.history = savedHistory
      appState.navigator = savedNavigator
      appState.preview = savedPreview
      appState.popup.needsResize = savedNeedsResize
      Defaults[.size] = savedSize
      Defaults[.sortBy] = savedSortBy
      Defaults[.pinTo] = savedPinTo
      Defaults[.pinOrder] = savedPinOrder
      Defaults[.searchMode] = savedSearchMode
      Defaults[.clearSystemClipboard] = savedClearSystemClipboard
    }
    Storage.shared.container = container
    Defaults[.size] = 10
    Defaults[.sortBy] = .lastCopiedAt
    Defaults[.pinTo] = .top
    Defaults[.pinOrder] = PinOrder()
    Defaults[.searchMode] = .exact
    Defaults[.clearSystemClipboard] = false
    for (index, text) in ["Alpha favorite", "Beta favorite", "Alpha ordinary", "Alpha pinned"].enumerated() {
      let item = HistoryItem(contents: [HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue, value: Data(text.utf8))])
      container.mainContext.insert(item)
      item.title = text
      item.lastCopiedAt = Date(timeIntervalSince1970: Double(100 - index))
    }
    try container.mainContext.save()
    let history = History()
    appState.history = history
    appState.navigator = NavigationManager(history: history, footer: appState.footer)
    appState.preview = DetachedPreviewController()
    try await history.load()
    await Task.yield()
    try await verify(history)
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}
