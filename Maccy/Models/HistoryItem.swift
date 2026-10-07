import AppKit
import Defaults
import Sauce
import SwiftData
import UniformTypeIdentifiers
import Vision

@Model
class HistoryItem {
  @MainActor
  static var supportedPins: Set<String> {
    // "a" reserved for select all
    // "f" reserved for explicitly focusing search
    // "q" reserved for quit
    // "v" reserved for paste
    // "w" reserved for close window
    // "z" reserved for undo/redo
    var keys = Set([
      "b", "c", "d", "e", "g", "h", "i", "j", "k", "l",
      "m", "n", "o", "p", "r", "s", "t", "u", "x", "y"
    ])

    if let deleteKey = KeyChord.deleteKey,
       let character = Sauce.shared.character(for: Int(deleteKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }

    if let pinKey = KeyChord.pinKey,
       let character = Sauce.shared.character(for: Int(pinKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }
    if let previewKey = KeyChord.previewKey,
       let character = Sauce.shared.character(for: Int(previewKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }

    return keys
  }

  @MainActor
  static var availablePins: [String] {
    History.shared.availablePins
  }

  @MainActor
  static func availablePins(in items: [HistoryItem]) -> [String] {
    let assignedPins = Set(items.compactMap(\.pin))
    return Array(supportedPins.subtracting(assignedPins))
  }

  @MainActor
  static var randomAvailablePin: String { availablePins.randomElement() ?? "" }

  private static let transientTypes: [String] = [
    NSPasteboard.PasteboardType.modified.rawValue,
    NSPasteboard.PasteboardType.fromMaccy.rawValue,
    NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
    NSPasteboard.PasteboardType.customWebKitPasteboardData.rawValue,
    NSPasteboard.PasteboardType.source.rawValue,
    NSPasteboard.PasteboardType.customChromiumWebData.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceUrl.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceToken.rawValue,
    NSPasteboard.PasteboardType.notesRichText.rawValue
  ]
  private static let imageTypes: [NSPasteboard.PasteboardType] = StorageType.images.types

  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies: Int = 1
  var pin: String?
  var isFavorite: Bool = false
  var title = ""
  // Read-only access to a copied image file; separate from the original pasteboard contents.
  var previewImageBookmark: Data?
  // SwiftData relationships are unordered. Keep file order and preview access together,
  // without replacing any of the original pasteboard representations.
  var previewImageFiles: Data?
  // Stored inline with this history row so every history deletion removes its preview too.
  var linkPreviewSnapshot: Data?

  @Transient var linkPreviewGeneration: UUID = UUID()

  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
  var contents: [HistoryItemContent] = []

  @Transient private var cachedDecodedImage: NSImage?

  init(contents: [HistoryItemContent] = []) {
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.contents = contents
    rememberFileOrder()
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    return item.contents
      .filter { content in
        !Self.transientTypes.contains(content.type)
      }
      .allSatisfy { content in
        contents.contains(where: { $0.type == content.type && $0.value == content.value })
      }
  }

  @MainActor
  func generateTitle() -> String {
    let pasteboardImageData = previewImagePages.isEmpty ? nil : contentData(Self.imageTypes)
    let universalClipboardImageURL = universalClipboardImage ? fileURLs.first : nil
    guard pasteboardImageData == nil && universalClipboardImageURL == nil else {
      Task {
        if let recognizedText = await Self.recognizeText(
          imageData: pasteboardImageData,
          fileURL: universalClipboardImageURL
        ) {
          self.title = recognizedText
        }
      }
      return ""
    }

    // 1k characters is trade-off for performance
    var title = previewableText
      .shortened(to: 1_000)
      .removingScalarsUnsafeForTitleLayout()

    if Defaults[.showSpecialSymbols] {
      if let range = title.range(of: "^ +", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      if let range = title.range(of: " +$", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      title = title
        .replacingOccurrences(of: "\n", with: "⏎")
        .replacingOccurrences(of: "\t", with: "⇥")
    } else {
      title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return title
  }

  var previewableText: String {
    if !fileURLs.isEmpty {
      fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let text = text, !text.isEmpty {
      text
    } else if let rtf = rtf, !rtf.string.isEmpty {
      rtf.string
    } else if let html = html, !html.string.isEmpty {
      html.string
    } else {
      title
    }
  }

  @MainActor
  var linkPreviewSourceURL: URL? {
    guard fileURLs.isEmpty else { return nil }
    return LinkPreviewLoader.candidateURL(from: previewableText)
  }

  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return previewFileEntries.map(\.url)
  }

  var htmlData: Data? { contentData([.html]) }
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  var imageData: Data? {
    var data: Data?
    data = contentData(Self.imageTypes)
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = try? Data(contentsOf: url)
    }

    return data
  }

  /// Sources used only for rendering. File copies must remain file copies when pasted.
  var previewImageSources: [ClipboardImageSource] {
    previewImagePages.first ?? []
  }

  /// Alternative representations belong to one page; separate image files are separate pages.
  var previewImagePages: [[ClipboardImageSource]] {
    let files = universalClipboardText ? [] : previewFileEntries
    if files.count > 1 {
      guard files.allSatisfy({ Self.isLocalImageURL($0.url) }) else { return [] }
      return files.map { [.file($0.url, bookmark: $0.bookmark)] }
    }

    var sources: [ClipboardImageSource] = Self.imageTypes.flatMap { type in
      allContentData([type]).filter { !$0.isEmpty }.map { .data($0) }
    }
    if let file = files.first, Self.isLocalImageURL(file.url) {
      sources.append(.file(file.url, bookmark: file.bookmark ?? previewImageBookmark))
    }
    return sources.isEmpty ? [] : [sources]
  }

  func rememberPreviewImageAccess(from urls: [URL]) {
    var files = previewFileEntries
    for index in files.indices {
      let copiedURL = files[index].url
      guard Self.isLocalImageURL(copiedURL),
            let url = urls.first(where: { $0.standardizedFileURL == copiedURL.standardizedFileURL }) else { continue }
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      if let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil) {
        files[index].bookmark = bookmark
      }
    }
    storePreviewFiles(files)
  }

  func inheritPreviewImageAccess(from previous: HistoryItem) {
    let oldFiles = previous.previewFileEntries
    var files = previewFileEntries
    for index in files.indices where files[index].bookmark == nil {
      files[index].bookmark = oldFiles.first(where: {
        $0.url.standardizedFileURL == files[index].url.standardizedFileURL
      })?.bookmark
    }
    if previewImageBookmark == nil { previewImageBookmark = previous.previewImageBookmark }
    storePreviewFiles(files)
  }

  func refreshPreviewImageBookmark(_ bookmark: Data, at page: Int) {
    var files = previewFileEntries
    guard files.indices.contains(page) else { return }
    files[page].bookmark = bookmark
    storePreviewFiles(files)
  }

  private struct PreviewFile: Codable {
    let url: URL
    var bookmark: Data?
  }

  private var previewFileEntries: [PreviewFile] {
    let urls = allContentData([.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
    if let data = previewImageFiles,
       let files = try? JSONDecoder().decode([PreviewFile].self, from: data),
       files.map({ $0.url.absoluteString }).sorted() == urls.map(\.absoluteString).sorted() {
      return files
    }
    return urls.map { PreviewFile(url: $0, bookmark: urls.count == 1 ? previewImageBookmark : nil) }
  }

  private func rememberFileOrder() {
    storePreviewFiles(previewFileEntries)
  }

  private func storePreviewFiles(_ files: [PreviewFile]) {
    guard !files.isEmpty else { return }
    if let data = try? JSONEncoder().encode(files), data != previewImageFiles {
      previewImageFiles = data
    }
    if files.count == 1, let bookmark = files.first?.bookmark { previewImageBookmark = bookmark }
  }

  private static func isLocalImageURL(_ url: URL) -> Bool {
    url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost") &&
      UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
  }

  var image: NSImage? {
    if let img = cachedDecodedImage {
      return img
    }
    guard let data = imageData else {
      return nil
    }

    cachedDecodedImage = NSImage(data: data)
    return cachedDecodedImage
  }

  var rtfData: Data? { contentData([.rtf]) }
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  func clearDecodedImageCache() {
    cachedDecodedImage?.recache()
    cachedDecodedImage = nil
  }

  var text: String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  var modified: Int? {
    guard let data = contentData([.modified]),
          let modified = String(data: data, encoding: .utf8) else {
      return nil
    }

    return Int(modified)
  }

  var fromMaccy: Bool { contentData([.fromMaccy]) != nil }
  var universalClipboard: Bool { contentData([.universalClipboard]) != nil }

  private var universalClipboardImage: Bool { universalClipboard && fileURLs.first?.pathExtension == "jpeg" }
  private var universalClipboardText: Bool {
    universalClipboard && contentData([.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
  }

  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    let content = contents.first(where: { content in
      return types.contains(NSPasteboard.PasteboardType(content.type))
    })

    return content?.value
  }

  private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
    return contents
      .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
      .compactMap { $0.value }
  }

  /// Runs OCR on the global concurrent executor so the main thread stays free.
  @concurrent
  nonisolated private static func recognizeText(imageData: Data?, fileURL: URL?) async -> String? {
    guard let data = imageData ?? fileURL.flatMap({ try? Data(contentsOf: $0) }) else {
      return nil
    }

    let requestHandler = VNImageRequestHandler(data: data)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast

    do {
      try requestHandler.perform([request])
    } catch {
      print("Unable to perform the request: \(error).")
      return nil
    }

    guard let observations = request.results else {
      return nil
    }

    return observations
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }
}
