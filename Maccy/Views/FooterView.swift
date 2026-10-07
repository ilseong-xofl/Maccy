import Defaults
import SwiftUI

struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Default(.showFooter) private var showFooter

  var body: some View {
    VStack(spacing: 0) {
      if showFooter {
        Divider()
          .padding(.horizontal, Popup.horizontalSeparatorPadding)

        HStack(spacing: 0) {
          Spacer()
          PopupIconButton(symbol: "gearshape", label: "preferences") {
            appState.openPreferences()
          }
          .help(Text("preferences"))
          .accessibilityIdentifier("popup-settings")
          .contextMenu {
            ForEach(footer.items) { item in
              if item.title == "preferences" || item.title == "quit" { Divider() }
              Button(LocalizedStringKey(item.title)) {
                if item.confirmation != nil && item.suppressConfirmation?.wrappedValue != true {
                  item.showConfirmation = true
                } else {
                  item.action()
                }
              }
            }
          }
          // Leave room beside Settings for the resize indicator at the window edge.
          Color.clear.frame(width: 17, height: 26)
        }
        .padding(.vertical, 2)
      }
    }
    .background {
      // Keep shortcut-triggered confirmation dialogs mounted even with the bar hidden.
      ForEach(footer.items.filter { $0.confirmation != nil }) { item in
        ConfirmationView(item: item) { Color.clear.frame(width: 1, height: 1) }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .readHeight(appState, into: \.popup.footerHeight)
  }
}

struct WindowResizeIndicator: View {
  var body: some View {
    Path { path in
      for inset in stride(from: CGFloat(0), through: 8, by: 4) {
        path.move(to: CGPoint(x: 2 + inset, y: 13))
        path.addLine(to: CGPoint(x: 13, y: 2 + inset))
      }
    }
    .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    .frame(width: 16, height: 16)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
