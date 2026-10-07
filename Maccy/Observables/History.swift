// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

enum HistoryFilter: String, CaseIterable, Identifiable {
  case history
  case favorites

  var id: Self { self }
}

@Observable
class History: ItemsContainer { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var pasteStack: PasteStack?

  // A temporary view choice, reset to history when the popup opens again.
  var filter: HistoryFilter = .history {
    didSet {
      guard filter != oldValue else { return }
      updateSearchResults()
      AppState.shared.reconcileHistoryVisibility(in: self)
      AppState.shared.popup.needsResize = true
    }
  }

  var items: ConcatenatedCollection<HistoryItemDecorator> {
    switch Defaults[.pinTo] {
    case .top:
      ConcatenatedCollection(pinnedItems, unpinnedItems)
    case .bottom:
      ConcatenatedCollection(unpinnedItems, pinnedItems)
    }
  }
  var pinnedItems: [HistoryItemDecorator] {
    matchingFilter(searchQuery.isEmpty ? allPinnedItems : filteredPinnedItems)
  }
  var unpinnedItems: [HistoryItemDecorator] {
    matchingFilter(searchQuery.isEmpty ? allUnpinnedItems : filteredUnpinnedItems)
  }
  var availablePins: [String] { pinManager.availablePins }

  var firstPinnedItem: HistoryItemDecorator? { pinnedItems.first }
  var firstUnpinnedItem: HistoryItemDecorator? { unpinnedItems.first }
  var firstUnfilteredUnpinnedItem: HistoryItemDecorator? { allUnpinnedItems.first }

  var searchQuery: String = "" {
    didSet(previousSearchQuery) {
      guard searchQuery != previousSearchQuery else { return }
      let shouldPreserveSelection = preserveSelectionOnSearchClear && searchQuery.isEmpty
      throttler.throttle { [self] in
        updateSearchResults()

        if !shouldPreserveSelection {
          if searchQuery.isEmpty {
            AppState.shared.navigator.select(item: firstVisibleItem)
          } else {
            AppState.shared.navigator.highlightFirst()
          }
        }

        AppState.shared.popup.needsResize = true
      }
    }
  }

  struct ShortcutInputContext {
    var isSearchFocused = false
    var isEditingItem = false
    var isEditableText = false
    var hasMarkedText = false
    var hasModal = false

    var acceptsRowShortcuts: Bool { allowsRowShortcuts(modifiers: []) }

    func allowsRowShortcuts(modifiers: NSEvent.ModifierFlags) -> Bool {
      guard !isEditingItem, !hasMarkedText, !hasModal else { return false }
      // Search accepts typed digits but retains its existing modified result shortcuts.
      if isSearchFocused { return !modifiers.isEmpty }
      return !isEditableText
    }

    @MainActor
    static func current(in window: NSWindow?, searchFocused: Bool = false) -> Self {
      let appState = AppState.shared
      let responder = window?.firstResponder
      let editable = (responder as? NSTextView)?.isEditable == true
        || (responder as? NSTextField)?.isEditable == true
      return Self(
        isSearchFocused: searchFocused,
        isEditingItem: appState.isEditingItem,
        isEditableText: editable,
        hasMarkedText: (responder as? NSTextInputClient)?.hasMarkedText() == true,
        hasModal: appState.isConfirmingQuit || NSApp.modalWindow != nil || window?.attachedSheet != nil
          || appState.appDelegate?.panel.attachedSheet != nil
          || appState.footer.items.contains { $0.showConfirmation }
      )
    }
  }

  struct ShortcutActivation {
    let item: HistoryItemDecorator
    let action: HistoryItemAction

    var removesFormatting: Bool { action == .pasteWithoutFormatting }
    var pastes: Bool { action == .paste || action == .pasteWithoutFormatting }
  }

  /// Resolve the event while its key, modifiers and focus still describe the key press.
  @MainActor
  func shortcutActivation(for event: NSEvent?, context: ShortcutInputContext) -> ShortcutActivation? {
    guard let event, event.type == .keyDown else { return nil }
    let flags = KeyShortcut.normalizedModifiers(event.modifierFlags)
    guard context.allowsRowShortcuts(modifiers: flags) else { return nil }
    let key: Key?
    let action: HistoryItemAction
    if flags.isEmpty {
      guard let character = event.characters, KeyShortcut.isCopyDigit(character) else { return nil }
      // Keypad keys have separate virtual key codes but copy the same numbered row.
      key = Key(character: character, virtualKeyCode: nil)
      action = .copy
    } else {
      action = HistoryItemAction(flags)
      guard action != .unknown else { return nil }
      if event.modifierFlags.contains(.numericPad),
         let character = event.charactersIgnoringModifiers, KeyShortcut.isCopyDigit(character) {
        key = Key(character: character, virtualKeyCode: nil)
      } else if KeyboardLayout.current.commandSwitchesToQWERTY && flags.contains(.command) {
        key = Key(QWERTYKeyCode: Int(event.keyCode))
      } else {
        key = Sauce.shared.key(for: Int(event.keyCode))
      }
    }
    guard let key, let item = items.first(where: { item in
      item.isVisible && item.isUnpinned
        && item.shortcuts.contains { $0.key == key && $0.modifierFlags == flags }
    }) else { return nil }
    return ShortcutActivation(item: item, action: action)
  }

  func canActivateShortcut(_ shortcut: ShortcutActivation) -> Bool {
    shortcut.item.isUnpinned && shortcut.item.isVisible && items.contains(shortcut.item)
      && shortcut.action != .unknown
  }

  @MainActor
  func activateShortcut(_ shortcut: ShortcutActivation) {
    guard canActivateShortcut(shortcut) else { return }
    AppState.shared.popup.close()
    Clipboard.shared.copy(shortcut.item.item, removeFormatting: shortcut.removesFormatting)
    if shortcut.pastes { Clipboard.shared.paste() }
    Task { searchQuery = "" }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)
  private let pinManager = PinManager()
  private var allPinnedItems: [HistoryItemDecorator] { pinManager.pinnedItems }
  private var allUnpinnedItems: [HistoryItemDecorator] = []
  private var filteredPinnedItems: [HistoryItemDecorator] = []
  private var filteredUnpinnedItems: [HistoryItemDecorator] = []

  @ObservationIgnored
  private var preserveSelectionOnSearchClear = false

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

#if DEBUG
  static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#endif

  init() {
    #if DEBUG
    guard !Self.isRunningUnitTests else { return }
    #endif

    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.sortBy, initial: false) {
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in allPinnedItems + allUnpinnedItems {
          await updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    // Image height is a live layout constraint. Keep the decoded thumbnail when it changes.
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    let decorators = sorter.sort(results).map { HistoryItemDecorator($0) }
    pinManager.load(from: decorators)
    allUnpinnedItems = decorators.filter(\.isUnpinned)
    filteredPinnedItems = allPinnedItems
    filteredUnpinnedItems = allUnpinnedItems

    limitHistorySize(to: Defaults[.size])

    updateSearchResults()
    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    // Favorites, like pins, are kept outside the automatic history quota.
    let ordinaryItems = allUnpinnedItems.filter { !$0.isFavorite }
    ordinaryItems.dropFirst(max(0, maxSize)).forEach(delete)
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting item with id '\(item.title)'")
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    if #available(macOS 15.0, *) {
      try? History.shared.insertIntoStorage(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    var replacedPinnedItem: HistoryItemDecorator?
    if let existingHistoryItem = findSimilarItem(item) {
      // Contents move to the new item below, so capture the source and metadata first.
      let previousLinkURL = existingHistoryItem.linkPreviewSourceURL
      let previousLinkSnapshot = existingHistoryItem.linkPreviewSnapshot
      if isModified(item) == nil {
        transferContents(from: existingHistoryItem, to: item)
      } else {
        item.inheritPreviewImageAccess(from: existingHistoryItem)
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.isFavorite = item.isFavorite || existingHistoryItem.isFavorite
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      if let snapshot = previousLinkSnapshot,
         let sourceURL = item.linkPreviewSourceURL,
         LinkPreviewSnapshot.sourceURL(in: snapshot) == sourceURL {
        item.linkPreviewSnapshot = snapshot
      } else {
        item.linkPreviewSnapshot = nil
      }
      logger.info("Removing duplicate item '\(item.title)'")
      if let existingDecorator = firstStoredItem(where: { $0.item == existingHistoryItem }) {
        cleanup(existingDecorator)
        allUnpinnedItems.removeAll { $0 == existingDecorator }
        if existingDecorator.isPinned {
          replacedPinnedItem = existingDecorator
        }
      }
      deleteFromStorage(existingHistoryItem, originalLinkURL: previousLinkURL)
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    let reservesHistorySlot = item.pin == nil && !item.isFavorite
    limitHistorySize(to: Defaults[.size] - (reservesHistorySlot ? 1 : 0))

    sessionLog[Clipboard.shared.changeCount] = item

    let itemDecorator: HistoryItemDecorator
    if item.pin != nil {
      itemDecorator = HistoryItemDecorator(item)
      if let replacedPinnedItem {
        pinManager.replace(replacedPinnedItem, with: itemDecorator)
      } else {
        pinManager.add(itemDecorator)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)
      insertUnpinned(itemDecorator)
    }

    if searchQuery.isEmpty {
      updateUnpinnedShortcuts()
    } else {
      updateSearchResults()
    }
    AppState.shared.popup.needsResize = true
    if item.linkPreviewSnapshot != nil || item.isFavorite {
      // Commit protected state and the duplicate handoff before add returns.
      let context = Storage.shared.context
      context.processPendingChanges()
      do {
        try context.save()
      } catch {
        logger.error("Failed to save inherited clipboard item state.")
      }
    }
    return itemDecorator
  }

  @MainActor
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
    func dataCounts() -> String {
      let historyItemCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
      let historyContentCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
      return "HistoryItem=\(historyItemCount ?? 0) HistoryItemContent=\(historyContentCount ?? 0)"
    }

    logger.info("\(msg) Before: \(dataCounts())")
    try? block()
    logger.info("\(msg) After: \(dataCounts())")
  }

  @MainActor
  func clear() {
    withLogging("Clearing history") {
      allUnpinnedItems.filter { !$0.isFavorite }.forEach { item in
        Self.invalidateLinkPreview(of: item.item, sourceURL: item.item.linkPreviewSourceURL)
        cleanup(item)
      }
      allUnpinnedItems.removeAll { !$0.isFavorite }
      filteredUnpinnedItems.removeAll { !$0.isFavorite }
      sessionLog.removeValues { $0.pin == nil && !$0.isFavorite }

      try? Storage.shared.context.transaction {
        // SQL comparisons through a nil relationship do not match orphaned contents.
        try? Storage.shared.context.delete(
          model: HistoryItemContent.self,
          where: #Predicate { $0.item == nil }
        )
        try? Storage.shared.context.delete(
          model: HistoryItem.self,
          where: #Predicate { $0.pin == nil && !$0.isFavorite }
        )
        try? Storage.shared.context.delete(
          model: HistoryItemContent.self,
          where: #Predicate { $0.item?.pin == nil && $0.item?.isFavorite == false }
        )
      }
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    updateSearchResults()
    AppState.shared.reconcileHistoryVisibility(in: self)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    withLogging("Clearing all history") {
      allPinnedItems.forEach { item in
        Self.invalidateLinkPreview(of: item.item, sourceURL: item.item.linkPreviewSourceURL)
        cleanup(item)
      }
      allUnpinnedItems.forEach { item in
        Self.invalidateLinkPreview(of: item.item, sourceURL: item.item.linkPreviewSourceURL)
        cleanup(item)
      }
      allUnpinnedItems.removeAll()
      filteredPinnedItems.removeAll()
      filteredUnpinnedItems.removeAll()
      pinManager.removeAll()
      sessionLog.removeAll()

      do {
        let context = Storage.shared.context
        try context.transaction {
          // Bulk deletion cannot remove children with live inverse relationships.
          try context.delete(
            model: HistoryItemContent.self,
            where: #Predicate { $0.item == nil }
          )
          try context.delete(model: HistoryItem.self)
          try context.delete(model: HistoryItemContent.self)
        }
      } catch {
        logger.error("Failed to clear storage: \(String(reflecting: error))")
      }
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    AppState.shared.reconcileHistoryVisibility(in: self)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    cleanup(item)
    withLogging("Removing history item") {
      deleteFromStorage(item.item, originalLinkURL: item.item.linkPreviewSourceURL)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    pinManager.remove(item)
    allUnpinnedItems.removeAll { $0 == item }
    filteredPinnedItems.removeAll { $0 == item }
    filteredUnpinnedItems.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    AppState.shared.reconcileHistoryVisibility(in: self)
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func transferContents(from existingItem: HistoryItem, to newItem: HistoryItem) {
    deleteContents(of: newItem)
    newItem.contents = existingItem.contents
    newItem.inheritPreviewImageAccess(from: existingItem)
    existingItem.contents = []
  }

  @MainActor
  private func deleteFromStorage(_ item: HistoryItem, originalLinkURL: URL?) {
    Self.invalidateLinkPreview(of: item, sourceURL: originalLinkURL)
    deleteContents(of: item)
    Storage.shared.context.delete(item)
  }

  @MainActor
  static func invalidateLinkPreview(of item: HistoryItem, sourceURL: URL?) {
    let snapshotURL = item.linkPreviewSnapshot.flatMap { LinkPreviewSnapshot.sourceURL(in: $0) }
    item.linkPreviewGeneration = UUID()
    item.linkPreviewSnapshot = nil
    for url in Set([sourceURL, snapshotURL].compactMap({ $0 })) {
      LinkPreviewLoader.shared.invalidateCachedResult(for: url)
    }
  }

  @MainActor
  private func deleteContents(of item: HistoryItem) {
    item.contents.forEach(Storage.shared.context.delete)
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?, flags modifierFlags: NSEvent.ModifierFlags) {
    guard let item else {
      return
    }

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>, flags modifierFlags: NSEvent.ModifierFlags) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying \(item.item.title) from PasteStack")

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard let pasted = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack pasted \(pasted.item.title)")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying \(item.item.title) from PasteStack. \(stack.items.count) items remaining in stack.")

    Task {
      if stack.modifierFlags.isEmpty {
        await Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy:
          await Clipboard.shared.copy(item.item)
        case .paste:
          await Clipboard.shared.copy(item.item)
        case .pasteWithoutFormatting:
          await Clipboard.shared.copy(item.item, removeFormatting: true)
        case .unknown:
          return
        }
      }
    }
  }

  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let wasPinned = item.isPinned
    pinManager.toggle(item)
    guard item.isPinned != wasPinned else { return }

    if wasPinned {
      insertUnpinned(item)
    } else {
      allUnpinnedItems.removeAll { $0 == item }
    }

    limitHistorySize(to: Defaults[.size])
    clearSearchPreservingSelection()
    updateShortcuts()
    AppState.shared.reconcileHistoryVisibility(in: self)
    if items.contains(item) { AppState.shared.navigator.scrollTarget = item.id }
    do {
      try item.item.modelContext?.save()
    } catch {
      logger.error("Failed to save clipboard item pin state.")
    }
  }

  @MainActor
  func toggleFavorite(_ item: HistoryItemDecorator?) {
    guard let item, firstStoredItem(where: { $0.id == item.id }) != nil else { return }
    item.item.isFavorite.toggle()
    do {
      try item.item.modelContext?.save()
    } catch {
      logger.error("Failed to save clipboard item favorite state.")
    }
    limitHistorySize(to: Defaults[.size])
    updateSearchResults()
    AppState.shared.reconcileHistoryVisibility(in: self)
    AppState.shared.popup.needsResize = true
  }

  private func clearSearchPreservingSelection() {
    preserveSelectionOnSearchClear = true
    defer { preserveSelectionOnSearchClear = false }
    searchQuery = ""
  }

  @MainActor
  func movePin(from source: IndexSet, to destination: Int) {
    guard filter == .history, searchQuery.isEmpty else { return }
    pinManager.move(from: source, to: destination)
  }

  @MainActor
  func updatePin(_ item: HistoryItem, to pin: String) {
    guard let itemDecorator = firstStoredItem(where: { $0.item.id == item.id }) else { return }

    let wasPinned = itemDecorator.isPinned
    pinManager.updatePin(of: itemDecorator, to: pin)
    if !wasPinned && itemDecorator.isPinned {
      allUnpinnedItems.removeAll { $0 == itemDecorator }
    }
    updateShortcuts()
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    if let duplicate = firstStoredItem(where: { $0.item != item && $0.item.supersedes(item) }) {
      return duplicate.item
    }

    return isModified(item)
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func matchingFilter(_ candidates: [HistoryItemDecorator]) -> [HistoryItemDecorator] {
    filter == .favorites ? candidates.filter(\.isFavorite) : candidates
  }

  private func updateSearchResults() {
    filteredPinnedItems = filteredItems(
      from: search.search(string: searchQuery, within: allPinnedItems)
    )
    filteredUnpinnedItems = filteredItems(
      from: search.search(string: searchQuery, within: allUnpinnedItems)
    )

    updateUnpinnedShortcuts()
  }

  private func filteredItems(from results: [Search.SearchResult]) -> [HistoryItemDecorator] {
    results.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }
  }

  private func firstStoredItem(
    where predicate: (HistoryItemDecorator) -> Bool
  ) -> HistoryItemDecorator? {
    allPinnedItems.first(where: predicate) ?? allUnpinnedItems.first(where: predicate)
  }

  private func insertUnpinned(_ item: HistoryItemDecorator) {
    let sortedItems = sorter.sort(allUnpinnedItems.map(\.item) + [item.item])
    guard let index = sortedItems.firstIndex(of: item.item) else { return }
    allUnpinnedItems.insert(item, at: index)
  }

  private func updateShortcuts() {
    for item in pinManager.pinnedItems {
      item.shortcuts = []
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  private func updateUnpinnedShortcuts() {
    let shortcutItems = unpinnedItems.filter(\.isVisible)
    // Hidden search/filter results must not retain an earlier numeric binding.
    for item in allUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in shortcutItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
