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
          HStack(spacing: 6) {
            filterBadge(.history, title: "history_filter_history", symbol: "clock")
            filterBadge(.favorites, title: "history_filter_favorites", symbol: "star.fill")
          }
          .padding(.leading, 6)
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

  private func filterBadge(_ filter: HistoryFilter, title: LocalizedStringKey, symbol: String) -> some View {
    let isSelected = appState.history.filter == filter
    let tint: Color = filter == .favorites ? FavoriteAppearance.color : .secondary
    return Button {
      appState.requestKeyboardFocus(.list)
      appState.history.filter = filter
    } label: {
      Label {
        Text(title).foregroundStyle(Color.primary.opacity(0.85))
      } icon: {
        if filter == .favorites {
          FavoriteStarIcon(isFilled: true)
            .foregroundStyle(tint)
            .frame(width: 12, height: 12)
        } else {
          Image(systemName: symbol).foregroundStyle(tint)
        }
      }
        .labelStyle(FilterBadgeLabelStyle())
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(tint.opacity(isSelected ? 0.23 : 0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(isSelected ? 0.6 : 0.2), lineWidth: 1))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .excludeFromWindowMovableByBackground()
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier(filter == .favorites ? "filter-favorites" : "filter-history")
  }
}

private struct FilterBadgeLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon
      configuration.title
    }
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
