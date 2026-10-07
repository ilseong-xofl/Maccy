import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack(spacing: 8) {
      ToolbarView()
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)

      if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }

}
