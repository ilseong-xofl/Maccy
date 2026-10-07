import SwiftUI

extension LinkPreviewFailure {
  var message: String {
    switch self {
    case .notFound:
      String(localized: "link_preview_not_found", defaultValue: "Page not found")
    case .unavailable:
      String(localized: "link_preview_unavailable", defaultValue: "Preview unavailable")
    case .connectionFailure:
      String(localized: "link_preview_connection_failure", defaultValue: "Connection failed")
    }
  }
}

@MainActor
@Observable
final class LinkPreviewState {
  struct Request: Equatable {
    let itemID: UUID
    let url: URL?
  }

  private(set) var url: URL?
  private(set) var result: LinkPreviewResult?
  private var loadID = UUID()

  func preview(for url: URL?) -> ClipboardLinkPreview? {
    guard self.url == url, case .preview(let preview) = result else { return nil }
    return preview
  }

  func failure(for url: URL?) -> LinkPreviewFailure? {
    guard self.url == url, case .failure(let failure) = result else { return nil }
    return failure
  }

  func load(item: HistoryItem, url: URL?) async {
    let loadID = UUID()
    self.loadID = loadID
    // Keep saved artwork visible while an older YouTube card gets its one-time title correction.
    result = url.flatMap { url in
      item.linkPreviewSnapshot.flatMap { LinkPreviewSnapshot.decode($0, sourceURL: url) }
    }
    self.url = url
    guard let url else { clear(); return }
    let result = await LinkPreviewLoader.shared.result(for: item, url: url)
    guard !Task.isCancelled, self.loadID == loadID else { return }
    self.result = result
  }

  func clear() {
    loadID = UUID()
    url = nil
    result = nil
  }
}

struct LinkPreviewFailureView: View {
  let url: URL
  let failure: LinkPreviewFailure
  var maxTextLines = 5
  var isListRow = false

  var body: some View {
    VStack(alignment: .leading, spacing: isListRow ? 4 : 5) {
      Text(verbatim: url.absoluteString)
        .lineLimit(maxTextLines)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
      Group {
        if isListRow {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.circle")
            Text(verbatim: failure.message)
          }
        } else {
          Label(failure.message, systemImage: "exclamationmark.circle")
        }
      }
      .font(.system(size: 11))
      .lineLimit(2)
      .foregroundStyle(.secondary)
    }
  }
}

/// A passive card: selecting, dragging and copying still belong to the clipboard row.
struct LinkPreviewCardView: View {
  let preview: ClipboardLinkPreview
  var maximumImageHeight: CGFloat = 300
  var fontSize: CGFloat = 14

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let image = preview.image {
        ListItemImageView(image: image, maximumHeight: maximumImageHeight)
          .frame(maxWidth: .infinity)
          .clipShape(.rect(cornerRadius: 6))
      }

      Text(verbatim: preview.title)
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 5) {
        Image(systemName: "link")
          .font(.system(size: fontSize - 5, weight: .medium))
        Text(verbatim: preview.url.absoluteString)
          .font(.system(size: fontSize - 2))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .foregroundStyle(.secondary)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.035),
                in: .rect(cornerRadius: 9))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: preview.title + ", " + preview.url.absoluteString))
  }
}
