import Sauce
import Defaults
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var keyboardFocus: ClipboardKeyboardFocus?
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { _ in
        let event = NSApp.currentEvent
        let inputContext = History.ShortcutInputContext.current(
          in: event?.window, searchFocused: keyboardFocus == .search || appState.isSearchFocused)
        guard !inputContext.isEditingItem, !inputContext.hasMarkedText, !inputContext.hasModal else {
          return .ignored
        }
        let chord = KeyChord(event)

        // Unfortunately, key presses don't allow access to
        // key code and don't properly work with multiple inputs,
        // so pressing ⌘, on non-English layout doesn't open
        // preferences. Stick to NSEvent to fix this behavior.

        switch chord {
        case .clearHistory:
          if let item = appState.footer.items.first(where: { $0.title == "clear" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearHistoryAll:
          if let item = appState.footer.items.first(where: { $0.title == "clear_all" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearSearch:
          guard keyboardFocus == .search else { return .handled }
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          guard keyboardFocus != .search else { return .ignored }
          if appState.navigator.pasteStackSelected {
            appState.removePasteStack()
          } else {
            appState.deleteSelection()
          }
          return .handled
        case .deleteOneCharFromSearch:
          return keyboardFocus == .search ? .ignored : .handled
        case .deleteLastWordFromSearch:
          return keyboardFocus == .search ? .ignored : .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          keyboardFocus = .list
          appState.navigator.highlightNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          keyboardFocus = .list
          appState.navigator.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          keyboardFocus = .list
          appState.navigator.highlightPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          keyboardFocus = .list
          appState.navigator.highlightFirst()
          return .handled
        case .extendToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToNext()
          return .handled
        case .extendToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToLast()
          return .handled
        case .extendToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToPrevious()
          return .handled
        case .extendToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          appState.togglePin()
          return .handled
        case .selectCurrentItem:
          appState.select(flags: KeyShortcut.normalizedModifiers(event?.modifierFlags ?? []))
          return .handled
        case .close:
          if appState.preview.isVisible {
            appState.preview.close(restoreListFocus: true)
          } else if keyboardFocus == .search {
            keyboardFocus = .list
          } else {
            appState.popup.close()
          }
          return .handled
        case .focusSearch:
          appState.requestKeyboardFocus(.search)
          return .handled
        case .previousPreviewImage, .nextPreviewImage:
          guard keyboardFocus != .search else { return .ignored }
          let offset = chord == .nextPreviewImage ? 1 : -1
          return appState.preview.navigateImages(by: offset) ? .handled : .ignored
        case .spacePreview:
          guard keyboardFocus != .search else { return .ignored }
          appState.preview.togglePreview()
          return .handled
        case .togglePreview:
          appState.preview.togglePreview()
          return .handled
        default:
          ()
        }

        if let shortcut = appState.history.shortcutActivation(for: event, context: inputContext) {
          appState.navigator.select(item: shortcut.item)
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.activateShortcut(shortcut)
          }
          return .handled
        }

        // Plain typing belongs only to explicitly focused search. The list never
        // redirects characters (including Backspace) into the search field.
        if keyboardFocus != .search, case .unknown = chord { return .handled }
        return .ignored
      }
  }
}
