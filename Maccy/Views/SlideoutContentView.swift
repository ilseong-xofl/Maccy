import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack(spacing: 6) {
      ToolbarView()
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
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
    .padding(.horizontal, 6)
    .padding(.bottom, 6)
    .padding(.top, 3)
  }

}
