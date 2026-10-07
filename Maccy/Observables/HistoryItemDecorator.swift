import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  private static let previewMaxParagraphSize = 10_000

  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }

  let id = UUID()

  var title: String = ""
  private(set) var listText: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }

  var hasImage: Bool { thumbnailImage != nil || previewImageCount > 0 }
  var previewImageCount: Int { item.previewImagePages.count }
  var hasFileURLs: Bool { !item.fileURLs.isEmpty }
  var hasPlainText: Bool { item.text != nil }
  var hasRichText: Bool { item.rtf != nil || item.html != nil }

  var previewLinkURL: URL? {
    guard !hasImage, !hasFileURLs else { return nil }
    let original = previewText.string.trimmingCharacters(in: .whitespacesAndNewlines)
    // An explicit alias continues to replace the row's content, including a URL.
    guard listText.trimmingCharacters(in: .whitespacesAndNewlines) == original else { return nil }
    return LinkPreviewLoader.candidateURL(from: original)
  }

  var thumbnailImageGenerationTask: Task<Void, Never>?
  private var imageGenerationID = UUID()
  private var previewPageCache: [Int: ClipboardPreviewImage] = [:]
  private var previewPageCacheOrder: [Int] = []
  private var previewPageLoads: [Int: (id: UUID, task: Task<ClipboardImageSource.Preview?, Never>)] = [:]
  private var previewPageLoadOrder: [Int] = []
  var previewImage: NSImage?
  private(set) var imagePixelSize: NSSize?
  private var imageSourceByteCount: Int64?
  private(set) var previewText = SizedString("")
  var thumbnailImage: NSImage?
  private(set) var thumbnailImages: [NSImage] = []
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { previewText.string.shortened(to: 10_000) }

  /// Report the source image's bytes, never the size of its generated thumbnail.
  var clippingByteCount: Int64 {
    imageSourceByteCount ?? item.contents.reduce(Int64(0)) { $0 + Int64($1.value?.count ?? 0) }
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    // We need to hash title and attributedTitle, so SwiftUI knows it needs to update the view if they chage
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(listText)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  var multiSelectionIndex: Int? {
    guard selectionIndex >= 0, AppState.shared.navigator.isMultiSelectInProgress else {
      return nil
    }
    return selectionIndex
  }

  // Describe the complete item independently of its potentially truncated visual content.
  var accessibilityLabel: String {
    var parts: [String] = []
    if previewImageCount > 1 {
      parts.append(String(format: NSLocalizedString("history_item_image_count_accessibility_label",
                                                    value: "%ld images", comment: ""), previewImageCount))
    }
    if let size = imagePixelSize {
      parts.append(
        String(
          format: NSLocalizedString("history_item_image_accessibility_label_no_app", comment: ""),
          Int(size.width),
          Int(size.height)
        )
      )
    } else {
      parts.append(listText)
    }
    if let application = application {
      parts.append(application)
    }
    if isPinned {
      parts.append(NSLocalizedString("history_item_pinned_accessibility_value", comment: ""))
    }
    if let index = multiSelectionIndex {
      parts.append(
        String(
          format: NSLocalizedString("history_item_selected_accessibility_value", comment: ""),
          index + 1,
          AppState.shared.navigator.selection.count
        )
      )
    }
    return parts.joined(separator: ", ")
  }

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = item.pin == nil ? shortcuts : []
    self.title = item.title
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
    synchronizeItemText()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard thumbnailImage == nil, thumbnailImageGenerationTask == nil else { return }
    let pages = item.previewImagePages
    guard !pages.isEmpty else { return }
    let generationID = imageGenerationID
    thumbnailImageGenerationTask = Task { [weak self] in
      for (index, sources) in pages.prefix(3).enumerated() {
        let result = await ClipboardImageSource.loadFirst(sources, maxPixelSize: pages.count == 1 ? 2048 : 1024)
        guard !Task.isCancelled, let self, self.imageGenerationID == generationID else { return }
        guard let result else { continue }
        let page = Self.previewPage(result)
        self.thumbnailImages.append(page.image)
        self.thumbnailImage = self.thumbnailImages.first
        if index == 0 {
          self.imagePixelSize = page.pixelSize
          self.imageSourceByteCount = page.sourceByteCount
          self.previewImage = page.image
          if pages.count == 1 { self.cachePreviewPage(page, at: 0) }
        }
        if let bookmark = result.refreshedBookmark { self.item.refreshPreviewImageBookmark(bookmark, at: index) }
      }
      guard let self, self.imageGenerationID == generationID else { return }
      self.thumbnailImageGenerationTask = nil
    }
  }

  @MainActor
  func ensurePreviewImage() {
    ensureThumbnailImage()
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    await asyncGetPreviewPage(at: 0)?.image
  }

  @MainActor
  func asyncGetPreviewPage(at index: Int) async -> ClipboardPreviewImage? {
    let pages = item.previewImagePages
    guard pages.indices.contains(index), !Task.isCancelled else { return nil }
    if let cached = previewPageCache[index] {
      cachePreviewPage(cached, at: index)
      return cached
    }

    let generationID = imageGenerationID
    let load: (id: UUID, task: Task<ClipboardImageSource.Preview?, Never>)
    if let pending = previewPageLoads[index] {
      load = pending
    } else {
      let sources = pages[index]
      load = (UUID(), Task { await ClipboardImageSource.loadFirst(sources) })
      previewPageLoads[index] = load
      previewPageLoadOrder.append(index)
      // Bound simultaneous work as well as retained pages when keys are pressed rapidly.
      while previewPageLoadOrder.count > 2 {
        let oldest = previewPageLoadOrder.removeFirst()
        previewPageLoads.removeValue(forKey: oldest)?.task.cancel()
      }
    }

    let result = await load.task.value
    guard !Task.isCancelled, imageGenerationID == generationID else { return nil }
    // Another waiter for this page may have already promoted this same load into the cache.
    if let cached = previewPageCache[index] { return cached }
    guard previewPageLoads[index]?.id == load.id else { return nil }
    previewPageLoads[index] = nil
    previewPageLoadOrder.removeAll { $0 == index }
    guard let result else { return nil }
    let page = Self.previewPage(result)
    cachePreviewPage(page, at: index)
    if index == 0 {
      previewImage = page.image
      imagePixelSize = page.pixelSize
      imageSourceByteCount = page.sourceByteCount
    }
    if let bookmark = result.refreshedBookmark { item.refreshPreviewImageBookmark(bookmark, at: index) }
    return page
  }

  private static func previewPage(_ result: ClipboardImageSource.Preview) -> ClipboardPreviewImage {
    ClipboardPreviewImage(
      image: NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height)),
      pixelSize: result.pixelSize,
      sourceByteCount: result.sourceByteCount
    )
  }

  private func cachePreviewPage(_ page: ClipboardPreviewImage, at index: Int) {
    previewPageCache[index] = page
    previewPageCacheOrder.removeAll { $0 == index }
    previewPageCacheOrder.append(index)
    while previewPageCacheOrder.count > 2 {
      previewPageCache.removeValue(forKey: previewPageCacheOrder.removeFirst())
    }
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    previewPageLoads.values.forEach { $0.task.cancel() }
    previewPageLoads = [:]
    previewPageLoadOrder = []
    previewPageCache = [:]
    previewPageCacheOrder = []
    imageGenerationID = UUID()
    thumbnailImages.forEach { $0.recache() }
    thumbnailImages = []
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
    imagePixelSize = nil
    imageSourceByteCount = nil
    item.clearDecodedImageCache()
  }

  @MainActor
  func sizeImages() async {
    ensureThumbnailImage()
    await thumbnailImageGenerationTask?.value
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !listText.isEmpty else {
      attributedTitle = nil
      return
    }

    // Search and rendering must use the same text, including real line breaks.
    var attributedString = AttributedString(listText)
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  private func synchronizeItemPin() {
    _ = withObservationTracking {
      item.pin
    } onChange: { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        if self.isPinned {
          self.shortcuts = []
        }
        // History assigns numeric shortcuts when unpinning. Preserve them when
        // this observation callback runs after the history has been updated.
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        self.title = self.item.title
        self.synchronizeListText()
        self.synchronizeItemTitle()
      }
    }
  }

  private func synchronizeItemText() {
    previewText = withObservationTracking {
      SizedString(item.previewableText, maxParagraphBytes: Self.previewMaxParagraphSize)
    } onChange: { [weak self] in
      DispatchQueue.main.async { [weak self] in
        self?.cleanupImages()
        self?.synchronizeItemText()
        self?.ensureThumbnailImage()
      }
    }
    synchronizeListText()
  }

  private func synchronizeListText() {
    let source: String
    if item.contents.contains(where: { StorageType.images.types.contains(NSPasteboard.PasteboardType($0.type)) }) ||
        (!title.isEmpty && title != item.generateTitle()) {
      // Keep user-authored aliases and image OCR titles intact.
      source = title
    } else {
      source = previewText.string
    }

    let prefix = source.shortened(to: 10_000)
    let truncated = prefix.utf8.count < source.utf8.count || (source == previewText.string && previewText.isTruncated)
    let newText = prefix
      .removingScalarsUnsafeForTitleLayout()
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n") + (truncated ? "…" : "")
    if listText != newText {
      listText = newText
      attributedTitle = nil
    }
  }
}
