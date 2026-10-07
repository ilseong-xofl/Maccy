import AppKit
import SwiftUI
import Defaults
import Settings

struct AppearanceSettingsPane: View {
  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.textPreviewLines) private var textPreviewLines
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.previewDirection) private var previewDirection
  @Default(.highlightMatch) private var highlightMatch
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.showFooter) private var showFooter
  @Default(.windowPosition) private var windowPosition
  @Default(.showApplicationIcons) private var showApplicationIcons

  @State private var screens = NSScreen.screens

  private let textPreviewLinesFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 20
    formatter.allowsFloats = false
    return formatter
  }()

  private let imageHeightFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 600
    formatter.allowsFloats = false
    return formatter
  }()

  private let numberOfItemsFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 100
    return formatter
  }()

  private let titleLengthFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 30
    formatter.maximum = 200
    return formatter
  }()

  private var textPreviewLinesLabel: Text {
    Text(String(
      localized: "TextPreviewLines",
      defaultValue: "Maximum text lines:",
      table: "AppearanceSettings"
    ))
  }

  private var textPreviewLinesHelp: Text {
    Text(String(
      localized: "TextPreviewLinesTooltip",
      defaultValue: """
      Maximum visible lines per text item after wrapping to the window width. \
      Short items use only the space they need.
      Range: 1–20. Default: 5.
      """,
      table: "AppearanceSettings"
    ))
  }

  private var previewDirectionLabel: Text {
    Text(String(
      localized: "PreviewDirection",
      defaultValue: "Preview window side:",
      table: "AppearanceSettings"
    ))
  }

  private var previewDirectionHelp: Text {
    Text(String(
      localized: "PreviewDirectionTooltip",
      defaultValue: """
      Open the preview on this side of the clipboard window. \
      Use the opposite side when there is not enough space.
      Default: Right.
      """,
      table: "AppearanceSettings"
    ))
  }

  var body: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(label: { Text("PopupAt", tableName: "AppearanceSettings") }) {
        HStack {
          Picker("", selection: $popupAt) {
            ForEach(PopupPosition.allCases) { position in
              if position == .center || position == .lastPosition, screens.count > 1 {
                screenPicker(for: position)
              } else {
                Text(position.description)
              }
            }
          }
          .labelsHidden()
          .frame(width: 141, alignment: .leading)
          .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))
          .accessibilityLabel(Text("PopupAt", tableName: "AppearanceSettings"))

          if popupAt == .lastPosition {
            Button {
              _windowPosition.reset()
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help(Text("PopupAtLastLocationReset", tableName: "AppearanceSettings"))
            .disabled(windowPosition == _windowPosition.defaultValue)
          }
        }
      }

      Settings.Section(label: { Text("PinTo", tableName: "AppearanceSettings") }) {
        Picker("", selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("PinToTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("PinTo", tableName: "AppearanceSettings"))
      }

      Settings.Section(label: { textPreviewLinesLabel }) {
        HStack {
          TextField("", value: $textPreviewLines, formatter: textPreviewLinesFormatter)
            .frame(width: 120)
            .help(textPreviewLinesHelp)
            .accessibilityLabel(textPreviewLinesLabel)
          Stepper("", value: $textPreviewLines, in: 1...20)
            .labelsHidden()
            .accessibilityLabel(textPreviewLinesLabel)
        }
      }

      Settings.Section(label: { Text("ImageHeight", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $imageHeight, formatter: imageHeightFormatter)
            .frame(width: 120)
            .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
          Stepper("", value: $imageHeight, in: 1...600)
            .labelsHidden()
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
        }
      }

      Settings.Section(label: { previewDirectionLabel }) {
        Picker("", selection: $previewDirection) {
          Text(String(localized: "PreviewDirectionRight", defaultValue: "Right", table: "AppearanceSettings"))
            .tag(PreviewDirection.right)
          Text(String(localized: "PreviewDirectionLeft", defaultValue: "Left", table: "AppearanceSettings"))
            .tag(PreviewDirection.left)
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(previewDirectionHelp)
        .accessibilityLabel(previewDirectionLabel)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("HighlightMatches", tableName: "AppearanceSettings") }
      ) {
        Picker("", selection: $highlightMatch) {
          ForEach(HighlightMatch.allCases) { match in
            Text(match.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("HighlightMatches", tableName: "AppearanceSettings"))
      }

      Settings.Section(title: "") {
        Defaults.Toggle(key: .showSpecialSymbols) {
          Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))

        HStack {
          Defaults.Toggle(key: .showInStatusBar) {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }

          Picker("", selection: $menuIcon) {
            ForEach(MenuIcon.allCases) { icon in
              Image(nsImage: icon.image)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showInStatusBar)
          .controlSize(.small)
          .accessibilityLabel(Text("ShowMenuIcon", tableName: "AppearanceSettings"))
        }

        Defaults.Toggle(key: .showRecentCopyInMenuBar) {
          Text("ShowRecentCopyInMenuBar", tableName: "AppearanceSettings")
        }
        HStack {
          Defaults.Toggle(key: .showSearch) {
            Text("ShowSearchField", tableName: "AppearanceSettings")
          }

          Picker("", selection: $searchVisibility) {
            ForEach(SearchVisibility.allCases) { type in
              Text(type.description)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showSearch)
          .controlSize(.small)
          .accessibilityLabel(Text("ShowSearchField", tableName: "AppearanceSettings"))
        }
        Defaults.Toggle(key: .showApplicationIcons) {
          Text("ShowApplicationIcons", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showLinkPreviews) {
          Text("ShowLinkPreviews", tableName: "AppearanceSettings")
        }
        .help(Text("ShowLinkPreviewsTooltip", tableName: "AppearanceSettings"))

        Defaults.Toggle(key: .showHexColorSwatch) {
          Text("ShowHexColorSwatch", tableName: "AppearanceSettings")
        }
        .help(Text("ShowHexColorSwatchTooltip", tableName: "AppearanceSettings"))

        Defaults.Toggle(key: .showFooter) {
          Text("ShowFooter", tableName: "AppearanceSettings")
        }
        Text("OpenPreferencesWarning", tableName: "AppearanceSettings")
          .fixedSize(horizontal: false, vertical: true)
          .opacity(showFooter ? 0 : 1)
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  @ViewBuilder
  private func screenPicker(for position: PopupPosition) -> some View {
    let screenBinding: Binding<Int> = Binding {
      return popupScreen
    } set: {
      popupScreen = $0
      popupAt = position
    }

    Picker(selection: screenBinding) {
      Text(labelForScreen(index: 0))
        .tag(0)

      ForEach(screens.indices, id: \.self) { index in
        Text(labelForScreen(index: index + 1))
          .tag(index + 1)
      }
    } label: {
      if popupAt == position {
        Text("\(position.description) (\(labelForScreen(index: popupScreen)))")
      } else {
        Text(position.description)
      }
    }
  }

  private func labelForScreen(index screenIndex: Int) -> String {
    switch screenIndex {
    case 0:
      return String(localized: "ActiveScreen", table: "AppearanceSettings")
    case _:
      return screens[screenIndex - 1].localizedName
    }
  }
}

#Preview {
  AppearanceSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
