import AppKit
import Defaults
import SwiftUI

struct PreviewItemView: View {
  private static let largeTextThreshold = 1_000
  private static let contentSpacing: CGFloat = 10

  private struct ImageRequest: Hashable {
    let itemID: UUID
    let index: Int
    let presentationID: UUID?
  }

  private struct LoadedPage {
    let request: ImageRequest
    let page: ClipboardPreviewImage?
  }

  var item: HistoryItemDecorator
  var imageIndex: Int = 0
  var presentationID: UUID?
  var surroundingHeight: CGFloat = 0
  var onNavigate: (Int) -> Void = { _ in }
  var onLayout: (DetachedPreviewController.ContentMetrics) -> Void = { _ in }
  @State private var metadataHeight: CGFloat = 114
  @State private var loadedPage: LoadedPage?
  @State private var isImageHovered = false
  @Default(.showLinkPreviews) private var showLinkPreviews
  @State private var linkState = LinkPreviewState()

  private var linkURL: URL? { showLinkPreviews ? item.previewLinkURL : nil }
  private var linkPreview: ClipboardLinkPreview? {
    linkState.preview(for: linkURL)
  }

  private var imageRequest: ImageRequest {
    ImageRequest(itemID: item.id, index: imageIndex, presentationID: presentationID)
  }

  private var currentPage: ClipboardPreviewImage? {
    loadedPage?.request == imageRequest ? loadedPage?.page : nil
  }

  var body: some View {
    GeometryReader { geometry in
      let informationHeight = min(metadataHeight, max(0, geometry.size.height - Self.contentSpacing - 24))
      let availableHeight = max(0, geometry.size.height - informationHeight - Self.contentSpacing)
      let metrics = DetachedPreviewController.ContentMetrics(
        itemID: item.id, imageSize: currentPage?.pixelSize, imageWidth: geometry.size.width,
        nonImageHeight: metadataHeight + Self.contentSpacing + surroundingHeight,
        imageIndex: imageIndex, presentationID: presentationID)

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
        // Keep the current frame while another page loads, and never size a
        // new page using the previous image's dimensions.
        guard !item.hasImage || currentPage != nil else { return }
        // AppKit resizing happens after this SwiftUI layout pass has finished.
        DispatchQueue.main.async { onLayout(value) }
      }
    }
    .task(id: imageRequest) {
      guard item.hasImage else { return }
      let request = imageRequest
      let page = await item.asyncGetPreviewPage(at: request.index)
      guard !Task.isCancelled else { return }
      loadedPage = LoadedPage(request: request, page: page)
    }
    .task(id: LinkPreviewState.Request(itemID: item.id, url: linkURL)) {
      await linkState.load(item: item.item, url: linkURL)
    }
    .onChange(of: presentationID) { _, _ in isImageHovered = false }
    .onDisappear {
      isImageHovered = false
      linkState.clear()
    }
  }

  @ViewBuilder
  private var previewContent: some View {
    if item.hasImage {
      ZStack {
        if let page = currentPage {
          Image(nsImage: page.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(.rect(cornerRadius: 4))
            .accessibilityLabel("Image \(imageIndex + 1) of \(item.previewImageCount)")
            .accessibilityIdentifier("previewImage")
        } else if loadedPage?.request == imageRequest {
          imagePlaceholder {
            Image(systemName: "photo.badge.exclamationmark")
              .symbolRenderingMode(.multicolor)
          }
        } else {
          imagePlaceholder { ProgressView() }
        }

        if item.previewImageCount > 1 {
          carouselControls
        }
      }
      .contentShape(Rectangle())
      .onHover { isImageHovered = $0 }
    } else if let linkPreview {
      GeometryReader { geometry in
        ScrollView {
          LinkPreviewCardView(preview: linkPreview,
                              maximumImageHeight: max(40, geometry.size.height - 110), fontSize: 16)
            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
      .accessibilityIdentifier("previewLinkCard")
    } else if let url = linkURL, let failure = linkState.failure(for: url) {
      ScrollView {
        LinkPreviewFailureView(url: url, failure: failure, maxTextLines: 20)
          .padding(8)
      }
      .accessibilityIdentifier("previewLinkFailure")
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

  private var carouselControls: some View {
    ZStack(alignment: .bottom) {
      HStack {
        carouselButton("Previous image", symbol: "chevron.left", offset: -1,
                       identifier: "previewPreviousImage")
        Spacer()
        carouselButton("Next image", symbol: "chevron.right", offset: 1,
                       identifier: "previewNextImage")
      }
      .padding(.horizontal, 8)
      .frame(maxHeight: .infinity)
      .opacity(isImageHovered ? 1 : 0)
      .allowsHitTesting(isImageHovered)
      .animation(.easeInOut(duration: 0.12), value: isImageHovered)

      Text(verbatim: "\(imageIndex + 1) / \(item.previewImageCount)")
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.6), in: Capsule())
        .padding(.bottom, 8)
        .accessibilityIdentifier("previewImageCounter")
        .allowsHitTesting(false)
    }
  }

  private func carouselButton(_ label: String, symbol: String, offset: Int,
                              identifier: String) -> some View {
    Button {
      onNavigate(offset)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 34, height: 34)
        .contentShape(Circle())
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
    }
    .buttonStyle(.plain)
    .focusable(false)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
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
      if item.hasImage {
        metadataRow("Dimensions") {
          if let size = currentPage?.pixelSize {
            Text(verbatim: "\(Int(size.width)) × \(Int(size.height))")
              .monospacedDigit()
          } else {
            Text(verbatim: "—")
          }
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
        if item.hasImage {
          if let byteCount = currentPage?.sourceByteCount {
            Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
              .monospacedDigit()
          } else {
            Text(verbatim: "—")
          }
        } else {
          Text(ByteCountFormatter.string(fromByteCount: item.clippingByteCount, countStyle: .file))
            .monospacedDigit()
        }
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
