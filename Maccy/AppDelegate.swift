import Defaults
import KeyboardShortcuts
import Sparkle
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
      if !Self.isPreviewDemo {
        SPUUpdater(hostBundle: Bundle.main,
                   applicationBundle: Bundle.main,
                   userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                   delegate: nil)
        .automaticallyChecksForUpdates = false
      }
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
    context.processPendingChanges()
    do {
      try context.save()
    } catch {
      assertionFailure("Cannot prepare preview demo: \(error.localizedDescription)")
    }
  }
  #endif

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
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
