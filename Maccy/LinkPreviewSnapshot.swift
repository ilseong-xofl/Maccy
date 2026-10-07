import AppKit
import ImageIO

/// A bounded, self-contained record owned by its clipboard history item.
/// These bytes never become a pasteboard representation or an external cache file.
@MainActor
enum LinkPreviewSnapshot {
  static let maximumRecordBytes = 300 * 1_024
  static let maximumThumbnailBytes = 256 * 1_024
  static let maximumImageDimension = 1_200
  static let maximumTitleCharacters = 2_048

  private struct Record: Codable {
    let version: Int
    let sourceURL: String
    let previewURL: String?
    let title: String?
    var thumbnail: Data?
    let failure: String?
  }

  static func encode(_ result: LinkPreviewResult, sourceURL: URL) -> Data? {
    let record: Record
    switch result {
    case .preview(let preview):
      record = Record(
        version: 1,
        sourceURL: sourceURL.absoluteString,
        previewURL: preview.url.absoluteString,
        title: boundedTitle(preview.title),
        thumbnail: preview.image.flatMap(encodeThumbnail),
        failure: nil
      )
    case .failure(let failure):
      let status: String
      switch failure {
      case .notFound: status = "notFound"
      case .unavailable: status = "unavailable"
      case .connectionFailure: status = "connectionFailure"
      }
      record = Record(
        version: 1, sourceURL: sourceURL.absoluteString,
        previewURL: nil, title: nil, thumbnail: nil, failure: status
      )
    }

    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    if let data = try? encoder.encode(record), data.count <= maximumRecordBytes { return data }
    var textOnly = record
    textOnly.thumbnail = nil
    guard let data = try? encoder.encode(textOnly), data.count <= maximumRecordBytes else { return nil }
    return data
  }

  static func decode(_ data: Data, sourceURL: URL) -> LinkPreviewResult? {
    guard let record = readRecord(data), record.sourceURL == sourceURL.absoluteString else { return nil }
    if let failure = record.failure {
      guard record.title == nil, record.previewURL == nil, record.thumbnail == nil else { return nil }
      switch failure {
      case "notFound": return .failure(.notFound)
      case "unavailable": return .failure(.unavailable)
      case "connectionFailure": return .failure(.connectionFailure)
      default: return nil
      }
    }

    guard let title = record.title, title.count <= maximumTitleCharacters,
          let value = record.previewURL, let url = URL(string: value),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          url.host != nil else { return nil }
    let image: NSImage?
    if let thumbnail = record.thumbnail {
      guard let decoded = decodeThumbnail(thumbnail) else { return nil }
      image = decoded
    } else {
      image = nil
    }
    return .preview(ClipboardLinkPreview(url: url, title: title, image: image))
  }

  static func sourceURL(in data: Data) -> URL? {
    guard let record = readRecord(data) else { return nil }
    return URL(string: record.sourceURL)
  }

  private static func readRecord(_ data: Data) -> Record? {
    guard data.count <= maximumRecordBytes,
          let record = try? PropertyListDecoder().decode(Record.self, from: data),
          record.version == 1 else { return nil }
    return record
  }

  private static func boundedTitle(_ title: String) -> String {
    var value = String(title.prefix(maximumTitleCharacters))
    // A single grapheme may contain many combining characters; bound bytes as well as characters.
    while value.utf8.count > 16 * 1_024 { value = String(value.prefix(value.count / 2)) }
    return value
  }

  private static func encodeThumbnail(_ image: NSImage) -> Data? {
    guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          source.width > 0, source.height > 0 else { return nil }
    let ratio = min(1, Double(maximumImageDimension) / Double(max(source.width, source.height)))
    var width = max(1, Int(Double(source.width) * ratio))
    var height = max(1, Int(Double(source.height) * ratio))
    while true {
      guard let bitmap = resizedBitmap(source, width: width, height: height) else { return nil }
      for quality in [0.85, 0.65, 0.45, 0.25] {
        if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]),
           data.count <= maximumThumbnailBytes { return data }
      }
      guard max(width, height) > 64 else { return nil }
      width = max(1, Int(Double(width) * 0.75))
      height = max(1, Int(Double(height) * 0.75))
    }
  }

  private static func resizedBitmap(_ image: CGImage, width: Int, height: Int) -> NSBitmapImageRep? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    // JPEG has no alpha channel, so transparent page artwork receives a predictable white background.
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(bounds)
    context.interpolationQuality = .high
    context.draw(image, in: bounds)
    guard let rendered = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: rendered)
  }

  private static func decodeThumbnail(_ data: Data) -> NSImage? {
    guard data.count <= maximumThumbnailBytes,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0,
          width <= maximumImageDimension, height <= maximumImageDimension,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
  }
}
