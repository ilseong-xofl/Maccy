import SwiftUI

struct HeaderView: View {
  @State private var appState = AppState.shared

  @FocusState.Binding var keyboardFocus: ClipboardKeyboardFocus?

  var body: some View {
    HStack(spacing: 6) {
      PopupIconButton(symbol: "xmark.circle.fill", label: "quit") {
        appState.quit()
      }
      .help(Text("quit_tooltip"))
      .accessibilityIdentifier("popup-quit")

      ListHeaderView(
        keyboardFocus: $keyboardFocus,
        searchQuery: $appState.history.searchQuery
      )
      .opacity(appState.searchVisible ? 1 : 0)
      .allowsHitTesting(appState.searchVisible)
      .accessibilityHidden(!appState.searchVisible)
      .layoutPriority(1)

      ToolbarView(compact: true)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 8)
    .readHeight(appState, into: \.popup.headerHeight)
  }
}

struct PopupIconButton: View {
  let symbol: String
  let label: LocalizedStringKey
  let action: @MainActor () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .excludeFromWindowMovableByBackground()
    .accessibilityLabel(Text(label))
  }
}
