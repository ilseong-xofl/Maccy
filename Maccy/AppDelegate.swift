import Defaults
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  #if DEBUG
  nonisolated static let isPreviewDemo = CommandLine.arguments.contains("preview-demo")
  nonisolated static let isTesting = CommandLine.arguments.contains("enable-testing") || isPreviewDemo
  #else
  nonisolated static let isPreviewDemo = false
  nonisolated static let isTesting = CommandLine.arguments.contains("enable-testing")
  #endif
  var panel: FloatingPanel<ContentView>!
  private var quitAlert: NSAlert?

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  // Base accessibility label for the status item; kept separate from the optional
  // dynamic `title` (recent copy text) so VoiceOver always announces something
  // meaningful even when that preference is off or the app is disabled.
  private func updateStatusItemAccessibilityLabel() {
    var accessibilityLabel = NSLocalizedString("status_item_accessibility_label", comment: "")
    if isStatusItemDisabled {
      accessibilityLabel += " — \(NSLocalizedString("status_item_disabled_accessibility_suffix", comment: ""))"
    }
    statusItem.button?.setAccessibilityLabel(accessibilityLabel)
  }

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if Self.isTesting {
      // Start from a clean slate for the isolated testing preferences.
      UserDefaults.standard.removePersistentDomain(forName: Defaults.Keys.testingSuiteName)
    }
    if Self.isPreviewDemo {
      configurePreviewDemoPreferences()
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    if !Self.isPreviewDemo {
      Clipboard.shared.onNewCopy { History.shared.add($0) }
      Clipboard.shared.start()

      Task {
        for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
          Clipboard.shared.restart()
        }
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    updateStatusItemAccessibilityLabel()

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
        updateStatusItemAccessibilityLabel()
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
        updateStatusItemAccessibilityLabel()
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    if !Self.isPreviewDemo {
      migrateUserDefaults()
    }
    #if DEBUG
    if Self.isPreviewDemo {
      seedPreviewDemoHistory()
    }
    #endif
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    #if DEBUG
    if Self.isPreviewDemo {
      DispatchQueue.main.async { [weak self] in
        NSApp.activate(ignoringOtherApps: true)
        self?.panel.open(height: AppState.shared.popup.height, at: .center)
      }
    }
    #endif
  }

  #if DEBUG
  private func configurePreviewDemoPreferences() {
    Defaults[.textPreviewLines] = 5
    Defaults[.imageMaxHeight] = 300
    Defaults[.windowSize] = NSSize(width: 640, height: 700)
    Defaults[.popupPosition] = .center
    Defaults[.openPreviewAutomatically] = false
    Defaults[.showApplicationIcons] = true
    Defaults[.showSpecialSymbols] = false
    Defaults[.clearOnQuit] = false
    Defaults[.clearSystemClipboard] = false
    Defaults[.sortBy] = .lastCopiedAt
  }

  private func seedPreviewDemoHistory() {
    let samples: [(text: String, application: String)] = [
      ("짧은 메모는 한 줄만 표시합니다.", "com.apple.TextEdit"),
      ("첫 번째 줄: 원래 줄바꿈을 유지합니다.\n두 번째 줄: 내용만큼 높이가 늘어납니다.\n세 번째 줄: 여백을 낭비하지 않습니다.",
       "com.apple.TextEdit"),
      (String(repeating: "창을 좁히면 글이 자동으로 다음 줄로 이어지고, 넓히면 한 줄에 더 많은 내용을 보여줍니다. "
              + "긴 클립보드 항목도 설정한 최대 다섯 줄까지만 표시하므로 목록을 빠르게 훑어볼 수 있습니다. ", count: 5),
       "com.apple.TextEdit"),
      ("https://example.com/clipboard/preview/"
        + String(repeating: "a-very-long-address-without-any-spaces-", count: 7)
        + "?layout=automatic&maxLines=5", "com.apple.Safari"),
      ("""
      struct ClipboardPreview {
          let maximumLines = 5

          func display(_ text: String) {
              // Preserve indentation and line breaks.
              print(text)
          }
      }
      """, "com.apple.TextEdit")
    ]
    let context = Storage.shared.context
    let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
    for (index, sample) in samples.enumerated() {
      let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                       value: Data(sample.text.utf8))
      let item = HistoryItem(contents: [content])
      context.insert(item)
      item.application = sample.application
      item.firstCopiedAt = timestamp.addingTimeInterval(-Double(index))
      item.lastCopiedAt = item.firstCopiedAt
      item.title = item.generateTitle()
    }
    // Optional file-URL-only fixtures exercise Finder-style copies without touching the system clipboard.
    let arguments = CommandLine.arguments
    for (argument, flag) in arguments.enumerated() where flag == "--preview-image" || flag == "--preview-images" {
      let paths = arguments.dropFirst(argument + 1).prefix { !$0.hasPrefix("--") }
      let urls = (flag == "--preview-image" ? Array(paths.prefix(1)) : Array(paths)).map {
        URL(fileURLWithPath: $0)
      }
      guard !urls.isEmpty else { continue }
      let item = HistoryItem(contents: urls.map {
        HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: $0.dataRepresentation)
      })
      context.insert(item)
      item.rememberPreviewImageAccess(from: urls)
      item.application = "com.apple.finder"
      item.firstCopiedAt = timestamp.addingTimeInterval(1)
      item.lastCopiedAt = item.firstCopiedAt
      item.title = item.generateTitle()
    }
    seedPreviewDemoLinks(arguments: arguments, timestamp: timestamp)
    context.processPendingChanges()
    do {
      try context.save()
    } catch {
      assertionFailure("Cannot prepare preview demo: \(error.localizedDescription)")
    }
  }

  private func seedPreviewDemoLinks(arguments: [String], timestamp: Date) {
    for (index, argument) in arguments.enumerated() where argument == "--preview-link" {
      guard arguments.indices.contains(index + 1),
            let url = URL(string: arguments[index + 1]),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil else { continue }
      let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                       value: Data(url.absoluteString.utf8))
      let item = HistoryItem(contents: [content])
      Storage.shared.context.insert(item)
      item.application = "com.apple.Safari"
      item.firstCopiedAt = timestamp.addingTimeInterval(2 + Double(index))
      item.lastCopiedAt = item.firstCopiedAt
      item.title = item.generateTitle()
    }
  }
  #endif

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    #if DEBUG
    // UI tools can send a reopen event while focusing the demo's preview window.
    // Keep its fixtures visible instead of toggling away the window under test.
    if Self.isPreviewDemo {
      if !panel.isPresented { panel.open(height: AppState.shared.popup.height, at: .center) }
      return true
    }
    #endif
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if let quitAlert {
      quitAlert.window.makeKeyAndOrderFront(nil)
      return .terminateCancel
    }

    let state = AppState.shared
    let previousWindow = sender.keyWindow
    let alert = NSAlert()
    alert.messageText = String(localized: "quit_alert_message", defaultValue: "Quit Maccy Preview?")
    alert.informativeText = String(localized: "quit_alert_comment",
                                  defaultValue: "Clipboard history collection will stop until you reopen the app.")
    alert.alertStyle = .warning
    let cancel = alert.addButton(withTitle: String(localized: "clear_alert_cancel"))
    alert.addButton(withTitle: String(localized: "quit")).keyEquivalent = ""
    alert.window.defaultButtonCell = cancel.cell as? NSButtonCell
    alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    quitAlert = alert
    state.isConfirmingQuit = true
    // The default button owns Return; handle Escape without replacing that equivalent.
    let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53, sender.modalWindow === alert.window {
        cancel.performClick(nil)
        return nil
      }
      return event
    }
    defer {
      if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
      quitAlert = nil
      state.isConfirmingQuit = false
    }
    sender.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }

    if let previousWindow, previousWindow.isVisible {
      previousWindow.makeKeyAndOrderFront(nil)
    } else if panel?.isPresented == true {
      panel.makeKeyAndOrderFront(nil)
    }
    return .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func ensureMigration(key: String, _ action: () -> Void) {
    if Defaults[.migrations][key] != true {
      action()
      Defaults[.migrations][key] = true
    }
  }

  @MainActor
  private func migrateUserDefaults() {
    ensureMigration(key: "2024-07-01-version-2") {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")
    }

    ensureMigration(key: "2025-07-04-add-jpeg-heic") {
      var types = Defaults[.enabledPasteboardTypes]
      if !types.isDisjoint(with: StorageType.images.types) {
        types.formUnion(StorageType.images.types)
      }
      Defaults[.enabledPasteboardTypes] = types
    }

    ensureMigration(key: "2026-08-12-cleanup-orphaned-history-item-contents") {
      _ = try? Storage.shared.cleanupOrphanedContents()
    }

    ensureMigration(key: "2026-08-31-sanitize-history-item-titles") {
      _ = try? Storage.shared.sanitizeTitles()
    }

    ensureMigration(key: "2026-09-15-remove-unpersistable-contents") {
      _ = try? Storage.shared.removeUnpersistableContents()
    }

    ensureMigration(key: "2026-10-07-backspace-delete-shortcut") {
      KeyboardShortcuts.Name.migrateDeleteShortcutToBackspace()
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    let modifierFlags = (NSApp.currentEvent?.modifierFlags ?? [])
      .union(NSEvent.modifierFlags)
      .intersection(.deviceIndependentFlagsMask)

    if modifierFlags.contains(.option) {
      Defaults[.ignoreEvents].toggle()

      if modifierFlags.contains(.shift) {
        Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
      }

      return
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin, .togglePreview]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
