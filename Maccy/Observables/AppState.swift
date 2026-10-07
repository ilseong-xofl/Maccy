import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager
  var preview: DetachedPreviewController
  var isSearchFocused = false
  private(set) var keyboardFocusRequestID = UUID()
  private(set) var requestedKeyboardFocus = ClipboardKeyboardFocus.list

  func requestKeyboardFocus(_ focus: ClipboardKeyboardFocus) {
    requestedKeyboardFocus = focus
    isSearchFocused = focus == .search
    keyboardFocusRequestID = UUID()
  }

  @MainActor
  func reconcileHistoryVisibility(in history: History) {
    guard self.history === history else { return }
    let visibleItems = history.items.filter(\.isVisible)
    let remainingSelection = navigator.selection.items.filter { visibleItems.contains($0) }
    let currentLead = navigator.leadHistoryItem
    if remainingSelection.count != navigator.selection.count
        || currentLead == nil || !visibleItems.contains(where: { $0 == currentLead }) {
      let next = remainingSelection.first ?? visibleItems.first
      navigator.isManualMultiSelect = false
      navigator.select(item: next)
    }
    if visibleItems.isEmpty {
      navigator.select(item: nil)
      preview.close()
    } else {
      preview.selectionDidChange()
    }
  }

  var isEditingItem: Bool = false
  var isConfirmingQuit = false
  var suppressPopupAutoClose: Bool {
    return navigator.isDragAndDropInProgress || isEditingItem || isConfirmingQuit
  }

  var searchVisible: Bool {
    if isSearchFocused { return true }
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.firstUnfilteredUnpinnedItem?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = DetachedPreviewController()
  }

  @MainActor
  func select(flags modifierFlags: NSEvent.ModifierFlags) {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection, flags: modifierFlags)
      } else {
        history.select(navigator.selection.first, flags: modifierFlags)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      guard !history.searchQuery.isEmpty else { return }
      Clipboard.shared.copyInMaccy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.nearestVisible(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      let generalTitle = NSLocalizedString("Title", tableName: "GeneralSettings", comment: "")
      let storageTitle = NSLocalizedString("Title", tableName: "StorageSettings", comment: "")
      let appearanceTitle = NSLocalizedString("Title", tableName: "AppearanceSettings", comment: "")
      let ignoreTitle = NSLocalizedString("Title", tableName: "IgnoreSettings", comment: "")
      let advancedTitle = NSLocalizedString("Title", tableName: "AdvancedSettings", comment: "")
      let toolbarTitles = [generalTitle, storageTitle, appearanceTitle, ignoreTitle, advancedTitle]
      let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
      let titleWidth = toolbarTitles.reduce(CGFloat.zero) {
        $0 + ($1 as NSString).size(withAttributes: titleAttributes).width
      }
      let toolbarItemSpacing: CGFloat = 24
      let toolbarEdgeSpacing: CGFloat = 40
      let toolbarWidth = titleWidth + CGFloat(toolbarTitles.count) * toolbarItemSpacing + toolbarEdgeSpacing
      let minimumWidth = max(500, ceil(toolbarWidth))
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: generalTitle,
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: storageTitle,
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: appearanceTitle,
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: ignoreTitle,
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: advancedTitle,
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
              .frame(minWidth: minimumWidth)
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
