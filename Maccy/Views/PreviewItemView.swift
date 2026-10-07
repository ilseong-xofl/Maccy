import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  private static let largeTextThreshold = 1_000

  var item: HistoryItemDecorator

  @ViewBuilder
  func previewImage(content: () -> some View) -> some View {
    content()
      .aspectRatio(contentMode: .fit)
      .clipShape(.rect(cornerRadius: 5))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var body: some View {
    GeometryReader { geometry in
      let metadataHeight = min(140, max(0, geometry.size.height) * 0.45)
      let previewHeight = max(0, geometry.size.height - metadataHeight - 17)

      VStack(alignment: .leading, spacing: 8) {
        previewContent
          .frame(maxWidth: .infinity)
          .frame(height: previewHeight)
          .clipped()

        Divider()

        // Metadata remains reachable at the preview window's minimum size and in long locales.
        ScrollView {
          metadata
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: metadataHeight)
        .id("metadata-\(item.id)")
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }
    .controlSize(.small)
  }

  @ViewBuilder
  private var previewContent: some View {
    if item.hasImage {
      AsyncView<NSImage?, _, _>(id: item.id) {
        return await item.asyncGetPreviewImage()
      } content: { image in
        if let image {
          previewImage {
            Image(nsImage: image)
              .resizable()
          }
        } else {
          previewImage {
            ZStack {
              Color.gray.opacity(0.3)
              Image(systemName: "photo.badge.exclamationmark")
                .symbolRenderingMode(.multicolor)
            }
          }
        }
      } placeholder: {
        previewImage {
          ZStack {
            Color.gray.opacity(0.3)
            ProgressView()
          }
        }
      }
    } else if item.previewText.byteCount >= Self.largeTextThreshold {
      LargeTextView(text: item.previewText.string)
        .id("textpreview-\(item.id)")
    } else {
      ScrollView {
        Text(item.previewText.string)
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id("textpreview-\(item.id)")
    }
  }

  private var metadata: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let application = item.application {
        metadataRow("Application") {
          HStack(spacing: 3) {
            AppImageView(appImage: item.applicationImage, size: NSSize(width: 11, height: 11))
            Text(application)
          }
        }
      }

      if let size = item.imagePixelSize {
        metadataRow("Dimensions") {
          Text("\(Int(size.width))×\(Int(size.height))")
        }
      }

      metadataRow("FirstCopyTime") {
        Text("\(item.item.firstCopiedAt, style: .date) \(item.item.firstCopiedAt, style: .time)")
      }
      metadataRow("LastCopyTime") {
        Text("\(item.item.lastCopiedAt, style: .date) \(item.item.lastCopiedAt, style: .time)")
      }
      metadataRow("NumberOfCopies") {
        Text(String(item.item.numberOfCopies))
      }
    }
  }

  private func metadataRow<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(LocalizedStringKey(key), tableName: "PreviewItemView")
        content()
      }
      .fixedSize(horizontal: true, vertical: false)

      VStack(alignment: .leading, spacing: 2) {
        Text(LocalizedStringKey(key), tableName: "PreviewItemView")
          .foregroundStyle(.secondary)
        content()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
