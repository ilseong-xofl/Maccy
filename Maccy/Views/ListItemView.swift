import Defaults
import SwiftUI

enum SelectionAppearance {
  case none
  case topConnection
  case bottomConnection
  case topBottomConnection

  func rect(cornerRadius: CGFloat) -> some Shape {
    var cornerRadii = RectangleCornerRadii()
    switch self {
    case .none:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .topConnection:
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .bottomConnection:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
    case .topBottomConnection:
      break
    }
    return .rect(cornerRadii: cornerRadii)
  }
}

struct ListItemView<Title: View, ID: Hashable>: View {
  var id: ID
  var selectionId: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var selectionIndex: Int?
  var help: LocalizedStringKey?
  var selectionAppearance: SelectionAppearance = .none
  // Complete description used when the row's visual content is hidden from accessibility.
  var accessibilityLabel: String = ""
  var maxTextLines: Int = 1
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Default(.imageMaxHeight) private var imageMaxHeight
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  // Use the same selection number for the visible badge and accessibility value.
  private var displaySelectionIndex: String? {
    selectionIndex.map { "\($0 + 1)" }
  }

  var body: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          AppImageView(appImage: appIcon, size: NSSize(width: 15, height: 15))
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        Image(nsImage: accessoryImage)
          .accessibilityIdentifier("copy-history-item")
          .accessibilityHidden(true)
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      if let image {
        ListItemImageView(image: image, maximumHeight: CGFloat(min(max(imageMaxHeight, 1), 600)))
          .accessibilityIdentifier("copy-history-item")
          .accessibilityHidden(true)
          .padding(.trailing, 5)
          .padding(.vertical, 5)
          .frame(maxWidth: .infinity, alignment: .center)
          .layoutPriority(1)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, maxLines: maxTextLines, title: title)
          .accessibilityHidden(true)
          .padding(.trailing, 5)
          .padding(.vertical, maxTextLines > 1 ? 6 : 0)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Spacer()

      HStack(spacing: 5) {
        if let displaySelectionIndex {
          Text(displaySelectionIndex)
            .font(.caption)
            .frame(minWidth: 10, alignment: .center)
            .padding(3)
            .background(
              Color.secondary.opacity(isSelected ? 0.5 : 0.8),
              in: Capsule()
            )
            .foregroundStyle(Color.white)
            .accessibilityHidden(true)
        }

        if !shortcuts.isEmpty {
          ZStack(alignment: .trailing) {
            ForEach(shortcuts) { shortcut in
              let visible = shortcut.isVisible(shortcuts, modifierFlags.flags)
              KeyboardShortcutView(shortcut: shortcut)
                .opacity(visible ? 1 : 0)
                .accessibilityHidden(true)
                .frame(width: visible ? nil : 0)
            }
          }
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .padding(.trailing, 10)
    }
    .frame(minHeight: Popup.itemHeight)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) {
      if maxTextLines > 1 {
        Divider().padding(.horizontal, 10).opacity(isSelected ? 0 : 0.45)
      }
    }
    .foregroundStyle(isSelected ? Color.white : .primary)
    // macOS 26 broke hovering if no background is present.
    // The slight opcaity white background is a workaround
    .background(
      isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
      in: selectionAppearance.rect(cornerRadius: Popup.cornerRadius)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityLabel))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityValue(Text(displaySelectionIndex ?? ""))
    .hoverSelectionId(selectionId)
    .help(help ?? "")
  }
}

struct ListItemImageView: View {
  var image: NSImage
  var maximumHeight: CGFloat

  var body: some View {
    ListItemImageLayout(sourceSize: image.size, maximumHeight: maximumHeight) {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
  }
}

struct ListItemImageLayout: Layout {
  var sourceSize: CGSize
  var maximumHeight: CGFloat

  static func fittedSize(sourceSize: CGSize, availableWidth: CGFloat?, maximumHeight: CGFloat) -> CGSize {
    guard sourceSize.width.isFinite, sourceSize.height.isFinite,
          sourceSize.width > 0, sourceSize.height > 0,
          maximumHeight.isFinite, maximumHeight > 0 else {
      return .zero
    }

    let width = availableWidth.flatMap { $0.isFinite ? max($0, 0) : nil } ?? sourceSize.width
    // Never enlarge a small source image. The row height follows the actual
    // fitted image, rather than reserving the maximum height for every item.
    let scale = min(1, width / sourceSize.width, maximumHeight / sourceSize.height)
    return CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    Self.fittedSize(sourceSize: sourceSize, availableWidth: proposal.width, maximumHeight: maximumHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let size = Self.fittedSize(
      sourceSize: sourceSize,
      availableWidth: bounds.width,
      maximumHeight: min(maximumHeight, bounds.height)
    )
    subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
  }
}
