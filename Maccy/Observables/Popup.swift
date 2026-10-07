import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

enum PopupState {
  // After releasing the modifiers, the next shortcut hides the popup.
  case toggle
  // While holding the opening shortcut's modifiers, repeat its main key to switch filters.
  case holdingModifiers

  mutating func action(for event: NSEvent, shortcut: KeyboardShortcuts.Shortcut?) -> PopupShortcutAction? {
    if event.type == .flagsChanged {
      if KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty {
        self = .toggle
      }
      return nil
    }

    guard event.type == .keyDown, let shortcut,
          shortcut.key?.rawValue == Int(event.keyCode),
          KeyShortcut.normalizedModifiers(event.modifierFlags) ==
            KeyShortcut.normalizedModifiers(shortcut.modifiers) else { return nil }
    // One filter change per physical key press, not the system's held-key repeat.
    guard !event.isARepeat else { return .consume }
    return self == .holdingModifiers ? .cycleFilter : .close
  }
}

enum PopupShortcutAction: Equatable {
  case close
  case cycleFilter
  case consume
}

@Observable
class Popup {
  static let verticalSeparatorPadding = 6.0
  static let horizontalSeparatorPadding = 6.0
  static let verticalPadding: CGFloat = 5
  static let horizontalPadding: CGFloat = 5
  static let minimumPreviewHeight: CGFloat = 150

  // Radius used for items inset by the padding. Ensures they visually have the same curvature
  // as the menu.
  static let cornerRadius: CGFloat = if #available(macOS 26.0, *) {
    7
  } else {
    4
  }

  static let itemHeight: CGFloat = if #available(macOS 26.0, *) {
    24
  } else {
    22
  }

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var extraTopHeight: CGFloat = 0
  var extraBottomHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  var minimumHeight: CGFloat {
    // Reserve space for 3 items and keep enough height for a preview without
    // changing the user's window height when the preview opens.
    return max(Self.minimumPreviewHeight, suitableHeight(for: 3 * Popup.itemHeight))
  }

  private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleFirstKeyDown)
    initEventsMonitor()
  }

  isolated deinit {
      deinitEventsMonitor()
  }

  func initEventsMonitor() {
    guard eventsMonitor == nil else { return }

    self.eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: handleEvent
    )
  }

  func deinitEventsMonitor() {
    guard let eventsMonitor else { return }

    NSEvent.removeMonitor(eventsMonitor)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func reset() {
    state = .toggle
    KeyboardShortcuts.enable(.popup)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func preferredHeight(for _: CGFloat) -> CGFloat {
    let height = max(Defaults[.windowSize].height, minimumHeight)
    let screen = AppState.shared.appDelegate?.panel.screen ?? NSScreen.forPopup
    return min(height, screen?.visibleFrame.height ?? .infinity)
  }

  private func suitableHeight(for historyListHeight: CGFloat) -> CGFloat {
    return historyListHeight + headerHeight + extraTopHeight + extraBottomHeight + footerHeight
  }

  func resize(height: CGFloat) {
    self.height = suitableHeight(for: height)
    needsResize = false
  }

  private func handleFirstKeyDown() {
    guard !AppState.shared.isEditingItem, !AppState.shared.isConfirmingQuit else { return }

    if isClosed() {
      open(height: height)
      state = KeyShortcut.normalizedModifiers(KeyboardShortcuts.Name.popup.shortcut?.modifiers ?? []).isEmpty
        ? .toggle : .holdingModifiers
      KeyboardShortcuts.disable(.popup)  // Handle events via eventsMonitor. Re-enable on popup close
      return
    }

    // Maccy was not opened via shortcut. We assume toggle mode and close it
    close()
  }

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    let appState = AppState.shared
    guard !isClosed() else { return event }
    // Always finish the held-modifier session, even when search or a sheet has focus.
    if event.type == .flagsChanged {
      _ = state.action(for: event, shortcut: KeyboardShortcuts.Name.popup.shortcut)
      return event
    }
    guard let eventWindow = event.window ?? NSApp.keyWindow,
          eventWindow === appState.appDelegate?.panel || appState.preview.owns(eventWindow) else { return event }
    // The preview keeps native modified text shortcuts; only the actual popup hotkey
    // participates in filter switching.
    if appState.preview.owns(eventWindow), event.type == .keyDown,
       !KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty,
       !(isHotKeyCode(Int(event.keyCode)) && isHotKeyModifiers(event.modifierFlags)) { return event }
    let inputContext = History.ShortcutInputContext.current(
      in: eventWindow, searchFocused: eventWindow === appState.appDelegate?.panel && appState.isSearchFocused)
    guard !inputContext.isEditingItem, !inputContext.hasMarkedText, !inputContext.hasModal else { return event }
    // Handle the configured shortcut even when the search field has focus.
    if isHotKeyModifiers(event.modifierFlags),
       !KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty,
       let action = state.action(for: event, shortcut: KeyboardShortcuts.Name.popup.shortcut) {
      perform(action)
      return nil
    }
    if event.type == .keyDown, isHotKeyCode(Int(event.keyCode)),
       let shortcut = appState.history.shortcutActivation(for: event, context: inputContext) {
      appState.navigator.select(item: shortcut.item)
      Task { @MainActor in appState.history.activateShortcut(shortcut) }
      return nil
    }
    guard inputContext.acceptsRowShortcuts else { return event }

    if event.type == .keyDown, isHotKeyCode(Int(event.keyCode)) {
      // A plain digit with no matching row must remain a row shortcut.
      if KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty,
         let character = event.characters, KeyShortcut.isCopyDigit(character) { return event }
      if let action = state.action(for: event, shortcut: KeyboardShortcuts.Name.popup.shortcut) {
        perform(action)
        return nil
      }
    }

    return event
  }

  func perform(_ action: PopupShortcutAction) {
    switch action {
    case .close:
      close()
    case .cycleFilter:
      let history = AppState.shared.history
      history.filter = history.filter == .history ? .favorites : .history
    case .consume:
      break
    }
  }

  private func isHotKeyCode(_ keyCode: Int) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
      return false
    }

    return shortcut.key?.rawValue == keyCode
  }

  private func isHotKeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
      return false
    }

    return KeyShortcut.normalizedModifiers(modifiers) == KeyShortcut.normalizedModifiers(shortcut.modifiers)
  }
}
