import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Default(.showHexColorSwatch) private var showHexColorSwatch
  @Default(.textPreviewLines) private var textPreviewLines
  @Environment(AppState.self) private var appState

  private var colorSwatchImage: NSImage? {
    guard showHexColorSwatch else { return nil }
    return ColorImage.from(item.title)
  }

  private func selectForInteraction(_ flags: NSEvent.ModifierFlags) {
    appState.requestKeyboardFocus(.list)
    if flags.contains(.command) && appState.multiSelectionEnabled {
      if NSApp.currentEvent?.clickCount == 1 { appState.navigator.addToSelection(item: item) }
    } else {
      appState.navigator.isManualMultiSelect = false
      appState.navigator.selectWithoutScrolling(item: item)
    }
  }

  private func activate(_ flags: NSEvent.ModifierFlags) {
    Task {
      appState.history.select(item, flags: flags)
    }
  }

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      stackImages: item.thumbnailImages,
      imageCount: item.previewImageCount,
      accessoryImage: item.thumbnailImage != nil ? nil : colorSwatchImage,
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: item.multiSelectionIndex,
      selectionAppearance: selectionAppearance,
      accessibilityLabel: item.accessibilityLabel,
      maxTextLines: min(max(textPreviewLines, 1), 20)
    ) {
      Text(verbatim: item.listText)
    }
    .accessibilityIdentifier("copy-history-item")
    .clipboardItemInteraction(onSelect: selectForInteraction, onActivate: activate)
    .onAppear {
      item.ensureThumbnailImage()
    }
    .accessibilityAction(named: Text(item.isPinned ? "history_item_unpin_action" : "history_item_pin_action")) {
      appState.history.togglePin(item)
    }
    .accessibilityAction(named: Text("history_item_delete_action")) {
      appState.history.delete(item)
    }
  }
}
