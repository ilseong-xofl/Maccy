import AppKit.NSImage
import ImageIO

/// A single decoded carousel page, with metadata from its original source.
struct ClipboardPreviewImage {
  let image: NSImage
  let pixelSize: NSSize
  let sourceByteCount: Int64?
}

/// Display-only sources. Never add a rendered thumbnail to the clipboard payload.
enum ClipboardImageSource: Sendable {
  case data(Data)
  case file(URL, bookmark: Data? = nil)

  struct Preview: Sendable {
    let image: CGImage
    let pixelSize: CGSize
    let sourceByteCount: Int64?
    let refreshedBookmark: Data?
  }

  @concurrent
  nonisolated static func loadFirst(_ sources: [Self], maxPixelSize: Int = 2048) async -> Preview? {
    for source in sources {
      guard !Task.isCancelled else { return nil }
      if let preview = source.load(maxPixelSize: maxPixelSize) {
        return Task.isCancelled ? nil : preview
      }
    }
    return nil
  }

  nonisolated private func load(maxPixelSize: Int) -> Preview? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    let source: CGImageSource?
    let sourceByteCount: Int64?
    var scopedURL: URL?
    var refreshedBookmark: Data?
    defer { scopedURL?.stopAccessingSecurityScopedResource() }

    switch self {
    case .data(let data):
      source = CGImageSourceCreateWithData(data as CFData, options)
      sourceByteCount = Int64(data.count)
    case .file(let originalURL, let bookmark):
      var url = originalURL
      var stale = false
      if let bookmark {
        if let resolved = try? URL(resolvingBookmarkData: bookmark,
                                   options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale) {
          url = resolved
        }
      }
      // Only local, regular files. Never load remote URLs or download cloud placeholders.
      guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
      if url.startAccessingSecurityScopedResource() { scopedURL = url }
      if stale {
        refreshedBookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                  includingResourceValuesForKeys: nil, relativeTo: nil)
      }
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey,
                                                          .ubiquitousItemDownloadingStatusKey]),
            values.isRegularFile == true,
            values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus == .current else { return nil }
      source = CGImageSourceCreateWithURL(url as CFURL, options)
      // Read the original file size while its security scope is still open.
      sourceByteCount = values.fileSize.map(Int64.init)
    }

    guard let source,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }

    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let size = CGSize(width: width.doubleValue, height: height.doubleValue)
    let orientedSize = (5...8).contains(orientation) ? CGSize(width: size.height, height: size.width) : size
    return Preview(image: image, pixelSize: orientedSize, sourceByteCount: sourceByteCount,
                   refreshedBookmark: refreshedBookmark)
  }
}

// Based on https://stackoverflow.com/questions/73062803/resizing-nsimage-keeping-aspect-ratio-reducing-the-image-size-while-trying-to-sc.
extension NSImage {
  /// Returns the pixel dimensions of the image.
  /// On Retina displays, this differs from `size` which returns logical points.
  var pixelSize: NSSize {
    if let bitmapRep = representations.first(where: { $0 is NSBitmapImageRep }) as? NSBitmapImageRep {
      return NSSize(width: CGFloat(bitmapRep.pixelsWide), height: CGFloat(bitmapRep.pixelsHigh))
    }
    // Fallback to logical size if no bitmap representation is available
    return size
  }
  func resized(to newSize: NSSize) -> NSImage {
    let ratioX = newSize.width / size.width
    let ratioY = newSize.height / size.height
    let ratio = ratioX < ratioY ? ratioX : ratioY
    let newHeight = size.height * ratio
    let newWidth = size.width * ratio
    let newSize = NSSize(width: newWidth, height: newHeight)

    // Don't attempt to size up.
    if newSize.height >= size.height {
      return self
    }

    return NSImage(size: newSize, flipped: false) { destRect in
      if let context = NSGraphicsContext.current {
        context.imageInterpolation = .high
        self.draw(in: destRect, from: NSRect.zero, operation: .copy, fraction: 1)
      }

      return true
    }
  }
}
