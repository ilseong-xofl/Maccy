import SwiftUI
import Defaults

struct AdvancedSettingsPane: View {
  var body: some View {
    VStack(alignment: .leading) {
      Defaults.Toggle(key: .ignoreEvents) {
        Text("TurnOff", tableName: "AdvancedSettings")
      }
      Text("TurnOffDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text(shellScript("TurnOffShellScript"))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)
      Text("TurnOffViaMenuIconDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text(shellScript("TurnOffNextShellScript"))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)

      Divider()

      Defaults.Toggle(key: .clearOnQuit) {
        Text("ClearHistoryOnQuit", tableName: "AdvancedSettings")
      }.help(Text("ClearHistoryOnQuitTooltip", tableName: "AdvancedSettings"))

      Defaults.Toggle(key: .clearSystemClipboard) {
        Text("ClearSystemClipboard", tableName: "AdvancedSettings")
      }.help(Text("ClearSystemClipboardTooltip", tableName: "AdvancedSettings"))
    }
    .frame(minWidth: 350, maxWidth: 450)
    .padding()
  }

  private func shellScript(_ key: String) -> String {
    NSLocalizedString(key, tableName: "AdvancedSettings", comment: "")
      .replacingOccurrences(
        of: "org.p0deje.Maccy",
        with: Bundle.main.bundleIdentifier ?? "io.github.ilseong-xofl.MaccyPreview"
      )
  }
}

#Preview {
  AdvancedSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
