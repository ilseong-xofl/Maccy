import AppKit
import Darwin
import LinkPresentation
import Logging
import Observation
import SwiftData
import UniformTypeIdentifiers

@MainActor
struct ClipboardLinkPreview {
  let url: URL
  let title: String
  let image: NSImage?
}

enum LinkPreviewFailure: Equatable, Sendable {
  case notFound
  case unavailable
  case connectionFailure
}

@MainActor
enum LinkPreviewResult {
  case preview(ClipboardLinkPreview)
  case failure(LinkPreviewFailure)
}

enum LinkPreviewProbeResult: Sendable {
  case status(Int)
  case connectionFailure
  case unavailable
}

/// Loads visible links only, sharing requests between the list and detached preview.
@MainActor
@Observable
final class LinkPreviewLoader {
  static let shared = LinkPreviewLoader()

  typealias Fetch = @MainActor (URL) async -> LinkPreviewResult?
  typealias Probe = @MainActor (URL) async -> LinkPreviewProbeResult?
  typealias YouTubeTitle = @MainActor (URL) async -> String?

  private struct RequestKey: Hashable {
    enum Kind { case preview, youtubeTitleRepair }
    let url: URL
    var kind: Kind = .preview
  }

  private struct CacheEntry {
    let result: LinkPreviewResult
    let expiresAt: Date
  }

  private final class Request {
    let id = UUID()
    var waiters: [UUID: CheckedContinuation<LinkPreviewResult?, Never>] = [:]
    var task: Task<Void, Never>?
    var shouldCache = true
  }

  private let logger = Logger(label: "io.github.ilseong-xofl.MaccyPreview.LinkPreview")
  private let capacity: Int
  private let concurrentLimit: Int
  private let failureLifetime: TimeInterval
  private let successLifetime: TimeInterval
  private let now: @MainActor () -> Date
  private let fetch: Fetch
  private let probe: Probe
  private let youtubeTitle: YouTubeTitle
  private var cache: [RequestKey: CacheEntry] = [:]
  private var cacheOrder: [RequestKey] = []
  private var requests: [RequestKey: Request] = [:]
  private var queue: [RequestKey] = []
  private var activeCount = 0

  init(
    capacity: Int = 32,
    concurrentLimit: Int = 3,
    failureLifetime: TimeInterval = 5 * 60,
    successLifetime: TimeInterval = 60 * 60,
    now: @escaping @MainActor () -> Date = { Date() },
    fetch: @escaping Fetch = LinkPreviewLoader.fetchMetadata,
    probe: @escaping Probe = LinkPreviewLoader.probeURL,
    youtubeTitle: @escaping YouTubeTitle = YouTubeLinkMetadata.title
  ) {
    self.capacity = max(1, capacity)
    self.concurrentLimit = max(1, concurrentLimit)
    self.failureLifetime = failureLifetime
    self.successLifetime = successLifetime
    self.now = now
    self.fetch = fetch
    self.probe = probe
    self.youtubeTitle = youtubeTitle
  }

  /// Accept a complete web URL, never an address embedded in ordinary clipboard text.
  /// Local hosts and private IP literals are excluded from automatic network requests.
  nonisolated static func candidateURL(from text: String) -> URL? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= 16 * 1_024,
          value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
          let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
          components.user == nil, components.password == nil,
          let url = components.url, url.absoluteString.utf8.count <= 16 * 1_024,
          let host = url.host?.lowercased(), !host.isEmpty,
          components.port.map({ (1...65535).contains($0) }) ?? true,
          isPublicHost(host) else { return nil }
    return url
  }

  /// Observed by both windows so completed loads stay in sync.
  func cachedResult(for url: URL) -> LinkPreviewResult? {
    guard let entry = cache[RequestKey(url: url)], entry.expiresAt > now() else { return nil }
    return entry.result
  }

  /// Discard completed values without interrupting other consumers of a shared request.
  func invalidateCachedResult(for url: URL) {
    for kind in [RequestKey.Kind.preview, .youtubeTitleRepair] {
      let key = RequestKey(url: url, kind: kind)
      cache[key] = nil
      cacheOrder.removeAll { $0 == key }
      requests[key]?.shouldCache = false
    }
  }

  /// A clipboard entry keeps its first completed preview, including failures, across app launches.
  func result(for item: HistoryItem, url: URL) async -> LinkPreviewResult? {
    guard !Task.isCancelled, let context = item.modelContext, !item.isDeleted,
          item.linkPreviewSourceURL == url else { return nil }
    if let snapshot = item.linkPreviewSnapshot {
      guard LinkPreviewSnapshot.needsYouTubeTitleRepair(snapshot, sourceURL: url) else {
        return LinkPreviewSnapshot.decode(snapshot, sourceURL: url) ?? .failure(.unavailable)
      }
      return await repairYouTubeTitle(for: item, url: url, snapshot: snapshot, context: context)
    }

    let generation = item.linkPreviewGeneration
    guard let result = await result(for: url), !Task.isCancelled,
          item.modelContext === context, !item.isDeleted,
          item.linkPreviewGeneration == generation, item.linkPreviewSourceURL == url else { return nil }
    // Another window may already have stored this same shared load.
    if let snapshot = item.linkPreviewSnapshot {
      return LinkPreviewSnapshot.decode(snapshot, sourceURL: url) ?? .failure(.unavailable)
    }
    let snapshot = LinkPreviewSnapshot.encode(result, sourceURL: url)
      ?? LinkPreviewSnapshot.encode(.failure(.unavailable), sourceURL: url)
    guard let snapshot else { return .failure(.unavailable) }
    save(snapshot, for: item, in: context)
    return LinkPreviewSnapshot.decode(snapshot, sourceURL: url) ?? .failure(.unavailable)
  }

  private func repairYouTubeTitle(
    for item: HistoryItem, url: URL, snapshot: Data, context: ModelContext
  ) async -> LinkPreviewResult? {
    let generation = item.linkPreviewGeneration
    guard let lookup = await result(for: RequestKey(url: url, kind: .youtubeTitleRepair)),
          !Task.isCancelled, item.modelContext === context, !item.isDeleted,
          item.linkPreviewGeneration == generation, item.linkPreviewSourceURL == url else { return nil }
    // Another window may have completed this repair while the shared request was running.
    guard item.linkPreviewSnapshot == snapshot else {
      return item.linkPreviewSnapshot.flatMap { LinkPreviewSnapshot.decode($0, sourceURL: url) }
    }
    let title: String?
    if case .preview(let preview) = lookup { title = preview.title } else { title = nil }
    guard let repaired = LinkPreviewSnapshot.markYouTubeTitleRepaired(snapshot, sourceURL: url, title: title) else {
      return LinkPreviewSnapshot.decode(snapshot, sourceURL: url)
    }
    save(repaired, for: item, in: context)
    return LinkPreviewSnapshot.decode(repaired, sourceURL: url)
  }

  private func save(_ snapshot: Data, for item: HistoryItem, in context: ModelContext) {
    item.linkPreviewSnapshot = snapshot
    do {
      try context.save()
    } catch {
      // Store errors can contain source URLs; keep the log free of clipboard contents.
      logger.error("Failed to save a link preview snapshot.")
    }
  }

  func preview(for url: URL) async -> ClipboardLinkPreview? {
    if case .preview(let preview) = await result(for: url) { return preview }
    return nil
  }

  func result(for url: URL) async -> LinkPreviewResult? {
    await result(for: RequestKey(url: url))
  }

  private func result(for key: RequestKey) async -> LinkPreviewResult? {
    let url = key.url
    guard !Task.isCancelled, Self.candidateURL(from: url.absoluteString) != nil else { return nil }
    if let entry = cache[key] {
      if entry.expiresAt > now() {
        touch(key)
        return entry.result
      }
      cache[key] = nil
      cacheOrder.removeAll { $0 == key }
    }

    let waiterID = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: nil)
          return
        }
        if let request = requests[key] {
          request.waiters[waiterID] = continuation
        } else {
          let request = Request()
          request.waiters[waiterID] = continuation
          requests[key] = request
          queue.append(key)
          startQueuedRequests()
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelWaiter(waiterID, for: key) }
    }
  }

  private func startQueuedRequests() {
    while activeCount < concurrentLimit, !queue.isEmpty {
      let key = queue.removeFirst()
      let url = key.url
      guard let request = requests[key] else { continue }
      let requestID = request.id
      activeCount += 1
      request.task = Task { [weak self, fetch, probe, youtubeTitle] in
        let result: LinkPreviewResult?
        switch key.kind {
        case .youtubeTitleRepair:
          if let title = await youtubeTitle(url) {
            result = .preview(ClipboardLinkPreview(url: url, title: title, image: nil))
          } else {
            result = .failure(.unavailable)
          }
        case .preview:
          result = await Self.fetchResult(for: url, fetch: fetch, probe: probe, youtubeTitle: youtubeTitle)
        }
        self?.finish(key, requestID: requestID, result: result, cancelled: Task.isCancelled)
      }
    }
  }

  private static func fetchResult(
    for url: URL, fetch: Fetch, probe: Probe, youtubeTitle: YouTubeTitle
  ) async -> LinkPreviewResult? {
    let availability = await probe(url)
    guard !Task.isCancelled else { return nil }
    if case .status(let status) = availability, status == 404 || status == 410 {
      return .failure(.notFound)
    }
    // YouTube's LP title can be the channel name. Ask the video-specific endpoint for its title.
    async let videoTitle = YouTubeLinkMetadata.canonicalVideoURL(from: url) != nil ? youtubeTitle(url) : nil
    let metadata = await fetch(url)
    let title = await videoTitle
    guard !Task.isCancelled else { return nil }
    if let title {
      let image: NSImage?
      if case .preview(let preview) = metadata { image = preview.image } else { image = nil }
      return .preview(ClipboardLinkPreview(url: url, title: title, image: image))
    }
    if case .preview = metadata { return metadata }
    if case .connectionFailure = availability { return .failure(.connectionFailure) }
    if case .failure(.connectionFailure) = metadata { return metadata }
    return .failure(.unavailable)
  }

  private func finish(_ key: RequestKey, requestID: UUID, result: LinkPreviewResult?, cancelled: Bool) {
    activeCount -= 1
    defer { startQueuedRequests() }
    guard let request = requests[key], request.id == requestID else { return }
    requests[key] = nil
    if !cancelled, request.shouldCache, let result {
      let lifetime: TimeInterval
      if case .failure = result { lifetime = failureLifetime } else { lifetime = successLifetime }
      cache[key] = CacheEntry(result: result, expiresAt: now().addingTimeInterval(lifetime))
      touch(key)
      while cacheOrder.count > capacity { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }
    request.waiters.values.forEach { $0.resume(returning: cancelled ? nil : result) }
  }

  private func cancelWaiter(_ id: UUID, for key: RequestKey) {
    guard let request = requests[key], let waiter = request.waiters.removeValue(forKey: id) else { return }
    waiter.resume(returning: nil)
    guard request.waiters.isEmpty else { return }
    requests[key] = nil
    if let task = request.task {
      // Retain its concurrency slot until the underlying provider acknowledges cancellation.
      task.cancel()
    } else {
      queue.removeAll { $0 == key }
    }
  }

  private func touch(_ key: RequestKey) {
    cacheOrder.removeAll { $0 == key }
    cacheOrder.append(key)
  }

  private static func fetchMetadata(for url: URL) async -> LinkPreviewResult? {
    let fetch = MetadataFetch()
    return await withTaskCancellationHandler {
      await fetch.preview(for: url)
    } onCancel: {
      Task { @MainActor in fetch.cancel() }
    }
  }

  private static func probeURL(_ url: URL) async -> LinkPreviewProbeResult? {
    guard !Task.isCancelled else { return nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 8
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    do {
      // A GET response reflects the page, unlike servers that handle HEAD differently.
      // Do not consume the bytes: stop as soon as the response headers are available.
      let (bytes, response) = try await session.bytes(from: url)
      bytes.task.cancel()
      guard !Task.isCancelled else { return nil }
      guard let response = response as? HTTPURLResponse else { return .unavailable }
      return .status(response.statusCode)
    } catch {
      guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return nil }
      return (error as? URLError) == nil ? .unavailable : .connectionFailure
    }
  }

  nonisolated private static func isPublicHost(_ original: String) -> Bool {
    let host = original.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let localSuffixes = ["localhost", "local", "internal", "lan", "home", "test", "invalid"]
    guard !localSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }

    var ipv4 = in_addr()
    if inet_pton(AF_INET, host, &ipv4) == 1 {
      return withUnsafeBytes(of: &ipv4) { isPublicIPv4(Array($0)) }
    }
    var ipv6 = in6_addr()
    if inet_pton(AF_INET6, host, &ipv6) == 1 {
      let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
      if bytes.prefix(12) == Array(repeating: UInt8(0), count: 10) + [255, 255] {
        return isPublicIPv4(Array(bytes.suffix(4)))
      }
      // Also exclude obsolete IPv4-compatible and site-local IPv6 addresses.
      return bytes.prefix(12).contains(where: { $0 != 0 })
        && bytes[0] & 0xfe != 0xfc && bytes[0] != 0xff
        && !(bytes[0] == 0xfe && bytes[1] & 0xc0 >= 0x80)
    }
    // Reject single-label names, numeric IPv4 shorthand and malformed hostnames.
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    return labels.count >= 2 && labels.last?.contains(where: { $0.isLetter }) == true
      && labels.allSatisfy {
        !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
          && $0.unicodeScalars.allSatisfy { allowed.contains($0) }
      }
  }

  nonisolated private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 4 else { return false }
    let first = bytes[0]
    let second = bytes[1]
    return first != 0 && first != 10 && first != 127 && first < 224
      && !(first == 100 && (64...127).contains(second))
      && !(first == 169 && second == 254)
      && !(first == 172 && (16...31).contains(second))
      && !(first == 192 && (second == 168 || second == 0))
      && !(first == 198 && (18...19).contains(second))
  }
}

/// One provider per request; cancellation also stops an outstanding image representation load.
@MainActor
private final class MetadataFetch {
  private let provider = LPMetadataProvider()
  private var imageProgress: Progress?
  private var imageContinuation: CheckedContinuation<Data?, Never>?
  private var imageTimeout: Task<Void, Never>?
  private var cancelled = false

  func cancel() {
    cancelled = true
    provider.cancel()
    finishImage(nil, cancelLoad: true)
  }

  func preview(for url: URL) async -> LinkPreviewResult? {
    guard !cancelled, !Task.isCancelled else { return nil }
    provider.timeout = 10
    provider.shouldFetchSubresources = true
    let metadata: LPLinkMetadata
    do {
      metadata = try await provider.startFetchingMetadata(for: url)
    } catch {
      guard !cancelled, !Task.isCancelled else { return nil }
      let error = error as NSError
      let timedOut = error.domain == LPErrorDomain && error.code == LPError.Code.metadataFetchTimedOut.rawValue
      let connectionFailed = error.domain == NSURLErrorDomain
      return .failure(timedOut || connectionFailed ? .connectionFailure : .unavailable)
    }
    guard !cancelled, !Task.isCancelled else { return nil }

    let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var image: NSImage?
    // The representative image is deliberate: a site's favicon must not become a huge card image.
    if let imageProvider = metadata.imageProvider,
       let type = imageProvider.registeredTypeIdentifiers.first(where: {
         UTType($0)?.conforms(to: .image) == true
       }) {
      let data = await loadImageData(from: imageProvider, type: type)
      guard !cancelled, !Task.isCancelled else { return nil }
      if let data, data.count <= 20 * 1024 * 1024,
         let decoded = await ClipboardImageSource.loadFirst([.data(data)], maxPixelSize: 1200) {
        image = NSImage(cgImage: decoded.image, size: NSSize(width: decoded.image.width, height: decoded.image.height))
      }
    }
    guard !cancelled, !Task.isCancelled else { return nil }
    guard !title.isEmpty || image != nil else { return .failure(.unavailable) }
    return .preview(ClipboardLinkPreview(
      url: url, title: title.isEmpty ? url.host ?? url.absoluteString : title, image: image
    ))
  }

  private func loadImageData(from itemProvider: NSItemProvider, type: String) async -> Data? {
    guard !cancelled, !Task.isCancelled else { return nil }
    return await withCheckedContinuation { continuation in
      imageContinuation = continuation
      imageTimeout = Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        self?.finishImage(nil, cancelLoad: true)
      }
      imageProgress = itemProvider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
        Task { @MainActor in self?.finishImage(data) }
      }
    }
  }

  private func finishImage(_ data: Data?, cancelLoad: Bool = false) {
    guard let continuation = imageContinuation else { return }
    imageContinuation = nil
    imageTimeout?.cancel()
    imageTimeout = nil
    if cancelLoad { imageProgress?.cancel() }
    imageProgress = nil
    continuation.resume(returning: data)
  }
}
