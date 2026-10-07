import AppKit
import SwiftUI

struct PreviewItemView: View {
  private static let largeTextThreshold = 1_000
  private static let contentSpacing: CGFloat = 10

  var item: HistoryItemDecorator
  var surroundingHeight: CGFloat = 0
  var onLayout: (DetachedPreviewController.ContentMetrics) -> Void = { _ in }
  @State private var metadataHeight: CGFloat = 114

  var body: some View {
    GeometryReader { geometry in
      let informationHeight = min(metadataHeight, max(0, geometry.size.height - Self.contentSpacing - 24))
      let availableHeight = max(0, geometry.size.height - informationHeight - Self.contentSpacing)
      let metrics = DetachedPreviewController.ContentMetrics(
        itemID: item.id, imageSize: item.imagePixelSize, imageWidth: geometry.size.width,
        nonImageHeight: metadataHeight + Self.contentSpacing + surroundingHeight)

      VStack(spacing: Self.contentSpacing) {
        previewContent
          .frame(maxWidth: .infinity)
          .frame(height: availableHeight)
          .clipped()

        ScrollView {
          metadata
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .readHeight($metadataHeight)
        }
        .frame(height: informationHeight)
        .scrollBounceBehavior(.basedOnSize)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 8))
        .id("metadata-\(item.id)")
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      .onChange(of: metrics, initial: true) { _, value in
        // AppKit resizing happens after this SwiftUI layout pass has finished.
        DispatchQueue.main.async { onLayout(value) }
      }
    }
  }

  @ViewBuilder
  private var previewContent: some View {
    if item.hasImage {
      AsyncView<NSImage?, _, _>(id: item.id) {
        await item.asyncGetPreviewImage()
      } content: { image in
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(.rect(cornerRadius: 4))
        } else {
          imagePlaceholder {
            Image(systemName: "photo.badge.exclamationmark")
              .symbolRenderingMode(.multicolor)
          }
        }
      } placeholder: {
        imagePlaceholder { ProgressView() }
      }
    } else if item.previewText.byteCount >= Self.largeTextThreshold {
      LargeTextView(text: item.previewText.string)
        .padding(8)
        .id("textpreview-\(item.id)")
    } else {
      ScrollView {
        Text(item.previewText.string)
          .font(.system(size: 14))
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .padding(8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id("textpreview-\(item.id)")
    }
  }

  private func imagePlaceholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
      Color.primary.opacity(0.04)
      content()
    }
    .clipShape(.rect(cornerRadius: 4))
  }

  private var metadata: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
      if let size = item.imagePixelSize {
        metadataRow("Dimensions") {
          Text(verbatim: "\(Int(size.width)) × \(Int(size.height))")
            .monospacedDigit()
        }
      }

      metadataRow("Copied") {
        Text(item.item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened))
          .monospacedDigit()
      }

      if let application = item.application {
        metadataRow("From App") {
          HStack(spacing: 6) {
            AppImageView(appImage: item.applicationImage, size: NSSize(width: 16, height: 16))
            Text(application)
          }
        }
      }

      metadataRow("Clipping Size") {
        Text(ByteCountFormatter.string(fromByteCount: item.clippingByteCount, countStyle: .file))
          .monospacedDigit()
      }
    }
    .font(.system(size: 14))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metadataRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    GridRow(alignment: .firstTextBaseline) {
      Text(verbatim: label)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .frame(width: 96, alignment: .trailing)

      content()
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
