import Defaults
import SwiftUI

struct HistoryListView: View {
  @Binding var searchQuery: String
  @FocusState.Binding var keyboardFocus: ClipboardKeyboardFocus?

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.pinTo) private var pinTo
  @Default(.showFooter) private var showFooter

  private var pinnedItems: [HistoryItemDecorator] {
    appState.history.pinnedItems
  }
  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems
  }
  private var pinsVisible: Bool {
    return !pinnedItems.isEmpty
  }

  private var topPadding: CGFloat {
    return Popup.verticalSeparatorPadding
  }

  private var bottomPadding: CGFloat {
    return showFooter
      ? Popup.verticalSeparatorPadding
      : (Popup.verticalSeparatorPadding - 1)
  }

  @ViewBuilder
  private func separator() -> some View {
    Divider()
      .padding(.horizontal, Popup.horizontalSeparatorPadding)
      .padding(.vertical, Popup.verticalSeparatorPadding)
  }

  var body: some View {
    let topPinsVisible = pinTo == .top && pinsVisible
    let bottomPinsVisible = pinTo == .bottom && pinsVisible
    ScrollView {
      ScrollViewReader { proxy in
        LazyVStack(spacing: 0) {
          if appState.history.filter == .history, let stack = appState.history.pasteStack,
             !stack.items.isEmpty {
            PasteStackView(stack: stack)

            if pinsVisible || !unpinnedItems.isEmpty {
              separator()
            }
          }

          if topPinsVisible {
            PinsView(items: pinnedItems)
          }

          MultipleSelectionListView(items: unpinnedItems) { previous, item, next, index in
            HistoryItemView(item: item, previous: previous, next: next, index: index)
          }

          if bottomPinsVisible {
            PinsView(items: pinnedItems)
          }
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .task(id: appState.navigator.scrollTarget) {
          guard appState.navigator.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.navigator.scrollTarget {
            let isPinned = appState.history.firstVisibleItem(where: { $0.id == selection })?.isPinned == true
            proxy.scrollTo(selection, anchor: isPinned ? .top : nil)
            appState.navigator.scrollTarget = nil
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            keyboardFocus = .list
            appState.navigator.isKeyboardNavigating = true
            appState.navigator.select(item: appState.history.firstVisibleItem)
          } else {
            modifierFlags.flags = []
            appState.navigator.isKeyboardNavigating = true
          }
        }
        // Calculate the total height inside a scroll view.
        .background {
          GeometryReader { geo in
            Color.clear
              .task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }

                if appState.popup.needsResize {
                  appState.popup.resize(height: geo.size.height)
                }
              }
          }
        }
      }
      .contentMargins(.leading, 10, for: .scrollIndicators)
      .contentMargins(.top, topPadding, for: .scrollIndicators)
      .contentMargins(.bottom, bottomPadding, for: .scrollIndicators)
    }
    .accessibilityIdentifier("history-scroll-view")
    .overlay {
      if pinnedItems.isEmpty && unpinnedItems.isEmpty
          && (appState.history.filter == .favorites || !searchQuery.isEmpty) {
        VStack(spacing: 8) {
          Image(systemName: searchQuery.isEmpty ? "star" : "magnifyingglass")
            .font(.system(size: 24))
            .foregroundStyle(searchQuery.isEmpty ? FavoriteAppearance.color : Color.secondary)
          Text(searchQuery.isEmpty ? "favorites_empty" : "history_search_empty")
            .font(.system(size: 13, weight: .medium))
          if searchQuery.isEmpty {
            Text("favorites_empty_hint")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .allowsHitTesting(false)
      }
    }
    .onAppear {
      // Pins and the paste stack now scroll with the history; they no longer
      // contribute a fixed minimum height outside the scroll view.
      appState.popup.extraTopHeight = 0
      appState.popup.extraBottomHeight = 0
    }
  }
}
