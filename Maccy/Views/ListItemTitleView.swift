import SwiftUI

struct ListItemTitleView<Title: View>: View {
  var attributedTitle: AttributedString?
  var maxLines: Int = 1
  @ViewBuilder var title: () -> Title

  var body: some View {
    if let attributedTitle {
      Text(attributedTitle)
        .accessibilityIdentifier("copy-history-item")
        .lineLimit(maxLines)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      title()
        .accessibilityIdentifier("copy-history-item")
        .lineLimit(maxLines)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        // Workaround for macOS 26 to avoid flipped text
        // https://github.com/p0deje/Maccy/issues/1113
        .drawingGroup()
    }
  }
}
