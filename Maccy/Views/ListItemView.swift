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
  var linkPreview: ClipboardLinkPreview?
  var linkFailure: LinkPreviewFailure?
  var linkURL: URL?
  var stackImages: [NSImage] = []
  var imageCount: Int = 1
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var isPinned: Bool = false
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
        Group {
          if imageCount > 1 {
            ListItemImageStackView(images: stackImages.isEmpty ? [image] : stackImages,
                                   count: imageCount,
                                   maximumHeight: CGFloat(min(max(imageMaxHeight, 1), 600)))
          } else {
            ListItemImageView(image: image, maximumHeight: CGFloat(min(max(imageMaxHeight, 1), 600)))
          }
        }
          .accessibilityIdentifier("copy-history-item")
          .accessibilityHidden(true)
          .padding(.trailing, 5)
          .padding(.vertical, 5)
          .frame(maxWidth: .infinity, alignment: .center)
          .layoutPriority(1)
      } else if let linkPreview {
        LinkPreviewCardView(preview: linkPreview, isSelected: isSelected,
                            maximumImageHeight: CGFloat(min(max(imageMaxHeight, 1), 600)))
          .padding(.trailing, 5)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1)
          .accessibilityHidden(true)
      } else if let linkFailure, let linkURL {
        LinkPreviewFailureView(url: linkURL, failure: linkFailure,
                               isSelected: isSelected,
                               maxTextLines: maxTextLines, isListRow: true)
          .padding(.trailing, 5)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
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
    // Reserve a narrow corner for the pin without covering short text or app icons.
    .padding(.leading, isPinned ? 14 : 0)
    .frame(minHeight: Popup.itemHeight)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) {
      if maxTextLines > 1 {
        Divider().padding(.horizontal, 10).opacity(isSelected ? 0 : 0.45)
      }
    }
    .foregroundStyle(isSelected ? Color.white : .primary)
    .background(
      isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
      in: selectionAppearance.rect(cornerRadius: Popup.cornerRadius)
    )
    .overlay(alignment: .topLeading) {
      if isPinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.red)
          .padding(.leading, 4)
          .padding(.top, 6)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityLabel))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityValue(Text(displaySelectionIndex ?? ""))
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

struct ListItemImageStackView: View {
  var images: [NSImage]
  var count: Int
  var maximumHeight: CGFloat

  var body: some View {
    let cards = Array(images.prefix(3))
    ListItemImageStackLayout(sourceSizes: cards.map(\.size), maximumHeight: maximumHeight) {
      ForEach(cards.indices, id: \.self) { index in
        Image(nsImage: cards[index])
          .resizable()
          .aspectRatio(contentMode: .fit)
          .background(.background, in: .rect(cornerRadius: 3))
          .clipShape(.rect(cornerRadius: 3))
          .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.5), lineWidth: 1))
          .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
          .rotationEffect(.degrees(ListItemImageStackLayout.angle(at: index)))
          .zIndex(Double(cards.count - index))
      }
    }
    .overlay(alignment: .bottomTrailing) {
      Text("\(count)")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.65), in: Capsule())
        .padding(5)
    }
  }
}

/// Account for each card's rotation so the entire stack stays inside its row.
struct ListItemImageStackLayout: Layout {
  var sourceSizes: [CGSize]
  var maximumHeight: CGFloat

  struct Card {
    var size: CGSize
    var center: CGPoint
  }

  static func angle(at index: Int) -> Double { [3.0, -7.0, 7.0][min(index, 2)] }

  static func arrangement(sourceSizes: [CGSize], availableWidth: CGFloat?, maximumHeight: CGFloat)
    -> (size: CGSize, cards: [Card]) {
    guard let first = sourceSizes.first else { return (.zero, []) }
    let front = ListItemImageLayout.fittedSize(sourceSize: first, availableWidth: availableWidth,
                                              maximumHeight: maximumHeight)
    guard front.width > 0, front.height > 0 else { return (.zero, []) }
    let gap = min(12, min(front.width, front.height) * 0.06)
    let offsets = [CGPoint(x: gap, y: gap), CGPoint(x: -gap, y: -gap / 2), CGPoint(x: 0, y: -gap)]
    var bounds = CGRect.null
    var cards: [Card] = []
    for (index, source) in sourceSizes.prefix(3).enumerated() {
      let size = ListItemImageLayout.fittedSize(sourceSize: source, availableWidth: front.width,
                                               maximumHeight: front.height)
      let radians = angle(at: index) * .pi / 180
      let width = abs(size.width * cos(radians)) + abs(size.height * sin(radians))
      let height = abs(size.width * sin(radians)) + abs(size.height * cos(radians))
      let center = offsets[index]
      bounds = bounds.union(CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                   width: width, height: height))
      cards.append(Card(size: size, center: center))
    }
    let width = availableWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? bounds.width
    let scale = min(1, width / bounds.width, maximumHeight / bounds.height)
    return (CGSize(width: bounds.width * scale, height: bounds.height * scale), cards.map {
      Card(size: CGSize(width: $0.size.width * scale, height: $0.size.height * scale),
           center: CGPoint(x: ($0.center.x - bounds.minX) * scale, y: ($0.center.y - bounds.minY) * scale))
    })
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    Self.arrangement(sourceSizes: sourceSizes, availableWidth: proposal.width, maximumHeight: maximumHeight).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let layout = Self.arrangement(sourceSizes: sourceSizes, availableWidth: bounds.width,
                                  maximumHeight: min(maximumHeight, bounds.height))
    let origin = CGPoint(x: bounds.midX - layout.size.width / 2, y: bounds.midY - layout.size.height / 2)
    for (index, card) in layout.cards.enumerated() where index < subviews.count {
      subviews[index].place(at: CGPoint(x: origin.x + card.center.x, y: origin.y + card.center.y),
                            anchor: .center, proposal: ProposedViewSize(card.size))
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
