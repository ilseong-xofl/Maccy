import SwiftUI

struct SlideoutContentView: View {
  nonisolated static let horizontalPadding: CGFloat = 6
  @Environment(AppState.self) var appState
  @State private var toolbarHeight: CGFloat = 23

  var body: some View {
    VStack(spacing: 6) {
      ToolbarView()
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .readHeight($toolbarHeight)

      if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item, surroundingHeight: toolbarHeight + 6 + 6 + 3,
                        onLayout: appState.preview.contentLayoutDidChange)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .id(item.id)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, Self.horizontalPadding)
    .padding(.bottom, 6)
    .padding(.top, 3)
  }

}
