import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

enum PopupState {
  // Default; shortcut will toggle the popup
  case toggle
  // In this mode, every additional press of the main key
  // will cycle to the next item in the paste history list.
  // Releasing the modifier keys will accept selection and close the popup
  case cycle
  // Transition state when the shortcut is first pressed and
  // we don't know whether we are in "toggle" or "cycle" mode.
  case opening
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
      state = .opening
      KeyboardShortcuts.disable(.popup)  // Handle events via eventsMonitor. Re-enable on popup close
      return
    }

    // Maccy was not opened via shortcut. We assume toggle mode and close it
    close()
  }

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    let appState = AppState.shared
    guard !isClosed(), let eventWindow = event.window ?? NSApp.keyWindow,
          eventWindow === appState.appDelegate?.panel || appState.preview.owns(eventWindow) else { return event }
    // The preview keeps native modified text shortcuts; only its actual popup hotkey
    // participates in the legacy cycle state machine.
    if appState.preview.owns(eventWindow), event.type == .keyDown,
       !KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty,
       !(isHotKeyCode(Int(event.keyCode)) && isHotKeyModifiers(event.modifierFlags)) { return event }
    let inputContext = History.ShortcutInputContext.current(
      in: eventWindow, searchFocused: eventWindow === appState.appDelegate?.panel && appState.isSearchFocused)
    if event.type == .keyDown, isHotKeyCode(Int(event.keyCode)),
       let shortcut = appState.history.shortcutActivation(for: event, context: inputContext) {
      appState.navigator.select(item: shortcut.item)
      Task { @MainActor in appState.history.activateShortcut(shortcut) }
      return nil
    }
    guard inputContext.acceptsRowShortcuts else { return event }

    switch event.type {
    case .keyDown:
      return handleKeyDown(event)
    case .flagsChanged:
      return handleFlagsChanged(event)
    default:
      return event
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if isHotKeyCode(Int(event.keyCode)) {
      // A plain digit with no matching row must not enter the popup hotkey's cycle mode.
      if KeyShortcut.normalizedModifiers(event.modifierFlags).isEmpty,
         let character = event.characters, KeyShortcut.isCopyDigit(character) { return event }

      if state == .opening {
        state = .cycle
        // Next 'if' will highlight next item and then return nil
      }

      if state == .cycle {
        AppState.shared.navigator.highlightNext(allowCycle: true)
        return nil
      }

      if state == .toggle && isHotKeyModifiers(event.modifierFlags) {
        close()
        return nil
      }
    }

    return event
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      let modifierFlags = KeyShortcut.normalizedModifiers(event.modifierFlags)
      DispatchQueue.main.async {
        AppState.shared.select(flags: modifierFlags)
      }
      return nil
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allModifiersReleased(event) {
      state = .toggle
      return event
    }

    return event
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

    return modifiers.intersection(.deviceIndependentFlagsMask) ==
      shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    return event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
  }
}
