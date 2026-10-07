import SwiftUI

struct ListHeaderView: View {
  @FocusState.Binding var keyboardFocus: ClipboardKeyboardFocus?
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    SearchFieldView(placeholder: "search_placeholder", query: $searchQuery, keyboardFocus: $keyboardFocus)
      .frame(maxWidth: .infinity)
      .onChange(of: scenePhase) {
        if scenePhase == .background && !searchQuery.isEmpty {
          searchQuery = ""
        }
      }
      // Only reliable way to disable the cursor. allowsHitTesting() does not work
      .offset(y: appState.searchVisible ? 0 : -Popup.itemHeight)
  }
}
