import AppKit
import Observation
import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class LinkPreviewLoaderTests: XCTestCase {
  func testAcceptsOnlyACompleteWebURL() {
    let values = [
      "https://github.com/PasteBar/PasteBarApp",
      "  https://example.com/path?q=one%20two#section\n",
      "http://www.example.com:8080/",
      "https://8.8.8.8/",
      "https://[2606:4700:4700::1111]/"
    ]
    for value in values {
      XCTAssertNotNil(LinkPreviewLoader.candidateURL(from: value), value)
    }
    XCTAssertEqual(
      LinkPreviewLoader.candidateURL(from: values[1])?.absoluteString,
      "https://example.com/path?q=one%20two#section"
    )
  }

  func testRejectsSourceURLsTooLargeForASnapshotIdentity() {
    let oversized = "https://example.com/" + String(repeating: "a", count: 16 * 1_024)
    let oversizedAfterEncoding = "https://example.com/" + String(repeating: "한", count: 2_000)
    XCTAssertNil(LinkPreviewLoader.candidateURL(from: oversized))
    XCTAssertNil(LinkPreviewLoader.candidateURL(from: oversizedAfterEncoding))
  }

  func testRejectsProseFilesCredentialsAndMultipleLinks() {
    let values = [
      "", "example.com", "ftp://example.com/file", "file:///tmp/image.png",
      "See https://example.com", "https://example.com some notes",
      "https://example.com\nhttps://apple.com", "https://example.com\thttps://apple.com",
      "[https://example.com](https://example.com)",
      "https://user:password@example.com", "https://user@example.com",
      "https://example.com:0", "https://example.com:65536"
    ]
    for value in values { XCTAssertNil(LinkPreviewLoader.candidateURL(from: value), value) }
  }

  func testRejectsLocalHostsAndPrivateAddressLiterals() {
    let values = [
      "http://localhost", "http://localhost./", "http://sub.localhost/", "http://server/",
      "http://printer.local/", "https://router.lan/", "http://example.internal/",
      "http://127.0.0.1/", "http://10.2.3.4/", "http://172.16.0.1/", "http://192.168.1.2/",
      "http://169.254.169.254/", "http://100.64.0.1/", "http://0.0.0.0/", "http://224.0.0.1/",
      "http://127.1/", "http://2130706433/", "http://0x7f000001/",
      "http://[::1]/", "http://[::]/", "http://[fd00::1]/", "http://[fe80::1]/",
      "http://[::ffff:192.168.1.2]/", "http://[::192.168.1.2]/", "http://[fec0::1]/"
    ]
    for value in values { XCTAssertNil(LinkPreviewLoader.candidateURL(from: value), value) }
  }

  func testRepeatedSuccessUsesCacheWithoutFetchingAgain() async {
    var requests = 0
    let loader = LinkPreviewLoader(fetch: { url in
      requests += 1
      return .preview(ClipboardLinkPreview(url: url, title: "Example", image: nil))
    }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    let first = await loader.preview(for: url)
    let second = await loader.preview(for: url)
    XCTAssertEqual(first?.title, "Example")
    XCTAssertEqual(second?.title, "Example")
    XCTAssertEqual(requests, 1)
  }

  func testFailureIsCachedUntilLifetimeExpires() async {
    var requests = 0
    var date = Date(timeIntervalSince1970: 1_000)
    let loader = LinkPreviewLoader(failureLifetime: 300, now: { date }, fetch: { _ in
      requests += 1
      return .failure(.unavailable)
    }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    let first = await loader.preview(for: url)
    let second = await loader.preview(for: url)
    XCTAssertNil(first)
    XCTAssertNil(second)
    XCTAssertEqual(requests, 1)
    date = date.addingTimeInterval(301)
    _ = await loader.preview(for: url)
    XCTAssertEqual(requests, 2)
  }

  func testCacheEvictsLeastRecentlyUsedEntry() async {
    var fetched: [URL] = []
    let loader = LinkPreviewLoader(capacity: 2, fetch: { url in
      fetched.append(url)
      return .preview(ClipboardLinkPreview(url: url, title: url.path, image: nil))
    }, probe: { _ in .status(200) })
    let urls = ["a", "b", "c"].map { URL(string: "https://example.com/\($0)")! }
    _ = await loader.preview(for: urls[0])
    _ = await loader.preview(for: urls[1])
    _ = await loader.preview(for: urls[0])
    _ = await loader.preview(for: urls[2])
    _ = await loader.preview(for: urls[1])
    XCTAssertEqual(fetched, [urls[0], urls[1], urls[2], urls[1]])
  }

  func testConcurrentCallersShareTheSameRequest() async {
    let gate = FetchGate()
    let loader = LinkPreviewLoader(fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    let first = Task { await loader.preview(for: url) }
    let second = Task { await loader.preview(for: url) }
    await waitFor { gate.started.count == 1 }
    await Task.yield()
    gate.complete(url)
    let firstResult = await first.value
    let secondResult = await second.value
    XCTAssertEqual(firstResult?.title, "Example")
    XCTAssertEqual(secondResult?.title, "Example")
    XCTAssertEqual(gate.started, [url])
  }

  func testRequestsRespectConcurrencyLimit() async {
    let gate = FetchGate()
    let loader = LinkPreviewLoader(concurrentLimit: 2, fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let urls = (0..<3).map { URL(string: "https://example.com/\($0)")! }
    let tasks = urls.map { url in Task { await loader.preview(for: url) } }
    await waitFor { gate.started.count == 2 }
    XCTAssertEqual(gate.pending.count, 2)
    let finished = gate.started[0]
    gate.complete(finished)
    await waitFor { gate.started.count == 3 }
    XCTAssertEqual(gate.pending.count, 2)
    for url in urls where url != finished { gate.complete(url) }
    for task in tasks { _ = await task.value }
  }

  func testCancellingOneWaiterDoesNotCancelSharedRequest() async {
    let gate = FetchGate()
    let loader = LinkPreviewLoader(fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    let first = Task { await loader.preview(for: url) }
    let second = Task { await loader.preview(for: url) }
    await waitFor { gate.started.count == 1 }
    await Task.yield()
    first.cancel()
    let firstResult = await first.value
    XCTAssertNil(firstResult)
    gate.complete(url)
    let secondResult = await second.value
    XCTAssertEqual(secondResult?.title, "Example")
    XCTAssertEqual(gate.started.count, 1)
  }

  func testCancellingQueuedRequestSkipsItsNetworkFetch() async {
    let gate = FetchGate()
    let loader = LinkPreviewLoader(concurrentLimit: 1, fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let firstURL = URL(string: "https://example.com/first")!
    let secondURL = URL(string: "https://example.com/second")!
    let first = Task { await loader.preview(for: firstURL) }
    await waitFor { gate.started.count == 1 }
    let second = Task { await loader.preview(for: secondURL) }
    await Task.yield()
    second.cancel()
    let secondResult = await second.value
    XCTAssertNil(secondResult)
    gate.complete(firstURL)
    _ = await first.value
    XCTAssertEqual(gate.started, [firstURL])
  }

  func testCancelledLoadCannotOverwriteANewerRequestForSameURL() async {
    let gate = FetchGate()
    let loader = LinkPreviewLoader(concurrentLimit: 1, fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    let first = Task { await loader.preview(for: url) }
    await waitFor { gate.started.count == 1 }
    first.cancel()
    _ = await first.value
    let second = Task { await loader.preview(for: url) }
    await Task.yield()
    gate.complete(url, title: "Stale")
    await waitFor { gate.started.count == 2 }
    gate.complete(url, title: "Fresh")
    let result = await second.value
    XCTAssertEqual(result?.title, "Fresh")
    let cached = await loader.preview(for: url)
    XCTAssertEqual(cached?.title, "Fresh")
  }

  func testNotFoundResponsesNeverLoadErrorPageMetadata() async {
    let url = URL(string: "https://example.com/missing")!
    for status in [404, 410] {
      var metadataCalls = 0
      var probeCalls = 0
      let loader = LinkPreviewLoader(fetch: { url in
        metadataCalls += 1
        return .preview(ClipboardLinkPreview(url: url, title: "404 error page", image: nil))
      }, probe: { _ in
        probeCalls += 1
        return .status(status)
      })
      let first = await loader.result(for: url)
      let second = await loader.result(for: url)
      assertFailure(first, equals: .notFound)
      assertFailure(second, equals: .notFound)
      XCTAssertEqual(metadataCalls, 0)
      XCTAssertEqual(probeCalls, 1)
    }
  }

  func testForbiddenProbeDoesNotPreventUsableMetadata() async {
    let loader = LinkPreviewLoader(fetch: { url in
      .preview(ClipboardLinkPreview(url: url, title: "A valid page", image: nil))
    }, probe: { _ in .status(403) })
    let preview = await loader.preview(for: URL(string: "https://example.com/")!)
    XCTAssertEqual(preview?.title, "A valid page")
  }

  func testConnectionFailureIsReportedWhenBothAttemptsFail() async {
    let loader = LinkPreviewLoader(fetch: { _ in .failure(.unavailable) }, probe: { _ in .connectionFailure })
    let result = await loader.result(for: URL(string: "https://example.com/")!)
    assertFailure(result, equals: .connectionFailure)
  }

  func testSuccessfulMetadataOverridesFailedProbe() async {
    let loader = LinkPreviewLoader(fetch: { url in
      .preview(ClipboardLinkPreview(url: url, title: "Available after all", image: nil))
    }, probe: { _ in .connectionFailure })
    let preview = await loader.preview(for: URL(string: "https://example.com/")!)
    XCTAssertEqual(preview?.title, "Available after all")
  }

  func testMetadataTimeoutRemainsAConnectionFailure() async {
    let loader = LinkPreviewLoader(fetch: { _ in .failure(.connectionFailure) }, probe: { _ in .status(200) })
    let result = await loader.result(for: URL(string: "https://example.com/")!)
    assertFailure(result, equals: .connectionFailure)
  }

  func testOtherHTTPStatusesDoNotMeanPageNotFound() async {
    for status in [200, 401, 403, 405, 429, 500, 503] {
      let loader = LinkPreviewLoader(fetch: { _ in .failure(.unavailable) }, probe: { _ in .status(status) })
      let result = await loader.result(for: URL(string: "https://example.com/")!)
      assertFailure(result, equals: .unavailable)
    }
  }

  func testCancellingProbeDoesNotCacheItsLateFailure() async {
    var pending: CheckedContinuation<LinkPreviewProbeResult?, Never>?
    var probeCalls = 0
    var fetchCalls = 0
    let loader = LinkPreviewLoader(concurrentLimit: 1, fetch: { url in
      fetchCalls += 1
      return .preview(ClipboardLinkPreview(url: url, title: "Fresh", image: nil))
    }, probe: { _ in
      probeCalls += 1
      if probeCalls == 1 { return await withCheckedContinuation { pending = $0 } }
      return .status(200)
    })
    let url = URL(string: "https://example.com/")!
    let first = Task { await loader.result(for: url) }
    await waitFor { pending != nil }
    first.cancel()
    let cancelled = await first.value
    XCTAssertNil(cancelled)
    pending?.resume(returning: .status(404))
    pending = nil
    let result = await loader.preview(for: url)
    XCTAssertEqual(result?.title, "Fresh")
    XCTAssertEqual(probeCalls, 2)
    XCTAssertEqual(fetchCalls, 1)
  }

  func testCachedResultDoesNotExposeAnExpiredEntry() async {
    var date = Date(timeIntervalSince1970: 1_000)
    let loader = LinkPreviewLoader(failureLifetime: 300, now: { date }, fetch: { _ in
      .failure(.unavailable)
    }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    XCTAssertNil(loader.cachedResult(for: url))
    _ = await loader.result(for: url)
    assertFailure(loader.cachedResult(for: url), equals: .unavailable)
    date = date.addingTimeInterval(301)
    XCTAssertNil(loader.cachedResult(for: url))
  }

  func testCachedResultObservationTracksRefreshAfterExpiry() async {
    var fetchCalls = 0
    var date = Date(timeIntervalSince1970: 1_000)
    let loader = LinkPreviewLoader(failureLifetime: 300, now: { date }, fetch: { url in
      fetchCalls += 1
      if fetchCalls == 1 { return .failure(.unavailable) }
      return .preview(ClipboardLinkPreview(url: url, title: "Recovered", image: nil))
    }, probe: { _ in .status(200) })
    let url = URL(string: "https://example.com/")!
    _ = await loader.result(for: url)
    let signal = ObservationSignal()
    withObservationTracking {
      _ = loader.cachedResult(for: url)
    } onChange: {
      Task { @MainActor in signal.changed = true }
    }
    date = date.addingTimeInterval(301)
    _ = await loader.result(for: url)
    await waitFor { signal.changed }
    guard case .preview(let preview) = loader.cachedResult(for: url) else {
      return XCTFail("Another consumer must see the new successful preview")
    }
    XCTAssertEqual(preview.title, "Recovered")
  }

  @MainActor
  private final class ObservationSignal {
    var changed = false
  }

  func testSavedSuccessAndFailureAreUsedByANewLoaderAndContext() async throws {
    let url = URL(string: "https://example.com/saved")!
    for expected in [LinkPreviewResult.preview(ClipboardLinkPreview(url: url, title: "Saved title", image: nil)),
                     .failure(.notFound), .failure(.unavailable), .failure(.connectionFailure)] {
      let container = try ModelContainer(for: HistoryItem.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let writer = ModelContext(container)
      let item = try makeHistoryItem(in: writer, url: url)
      let loader = LinkPreviewLoader(fetch: { _ in expected }, probe: { _ in .status(200) })
      // notFound can only originate from an observed HTTP status.
      if case .failure(.notFound) = expected {
        item.linkPreviewSnapshot = LinkPreviewSnapshot.encode(expected, sourceURL: url)
        try writer.save()
      } else {
        _ = await loader.result(for: item, url: url)
      }
      let reader = ModelContext(container)
      let restored = try XCTUnwrap(reader.model(for: item.persistentModelID) as? HistoryItem)
      let actual = await offlineLoader().result(for: restored, url: url)
      assertSameResult(actual, expected)
      XCTAssertNotNil(restored.linkPreviewSnapshot)
    }
  }

  func testSnapshotsSurviveFileBackedStoreReopenWithoutNetwork() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = URL(string: "https://example.com/saved")!
    let expected: [LinkPreviewResult] = [
      .preview(ClipboardLinkPreview(url: url, title: "Stored on disk", image: nil)),
      .failure(.unavailable), .failure(.connectionFailure), .failure(.notFound)
    ]
    for (index, result) in expected.enumerated() {
      let store = directory.appendingPathComponent("preview-\(index).sqlite")
      try await writeSnapshot(result, url: url, store: store)
      let reopened = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: store))
      let reader = ModelContext(reopened)
      let item = try XCTUnwrap(reader.fetch(FetchDescriptor<HistoryItem>()).first)
      let actual = await offlineLoader().result(for: item, url: url)
      assertSameResult(actual, result)
      XCTAssertEqual(item.contents.first?.value, Data(url.absoluteString.utf8))
    }
  }

  func testSavedSnapshotsIgnoreMemoryCacheExpiryAndEviction() async throws {
    let url = URL(string: "https://example.com/saved")!
    for shouldFail in [false, true] {
      let container = try ModelContainer(for: HistoryItem.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let context = ModelContext(container)
      let item = try makeHistoryItem(in: context, url: url)
      var date = Date(timeIntervalSince1970: 1_000)
      var fetches = 0
      let loader = LinkPreviewLoader(capacity: 1, failureLifetime: 1, successLifetime: 1, now: { date }, fetch: { url in
        fetches += 1
        return shouldFail ? .failure(.unavailable) : .preview(
          ClipboardLinkPreview(url: url, title: "Initial title", image: nil)
        )
      }, probe: { _ in .status(200) })
      let original = await loader.result(for: item, url: url)
      _ = await loader.result(for: URL(string: "https://example.com/other")!)
      date = date.addingTimeInterval(10_000)
      let restored = await loader.result(for: item, url: url)
      assertSameResult(restored, try XCTUnwrap(original))
      XCTAssertEqual(fetches, 2)
    }
  }

  func testCorruptSavedSnapshotDoesNotTriggerAnotherRequest() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/saved")!
    let item = try makeHistoryItem(in: context, url: url)
    item.linkPreviewSnapshot = Data("corrupt snapshot".utf8)
    try context.save()
    let result = await offlineLoader().result(for: item, url: url)
    assertFailure(result, equals: .unavailable)
  }

  func testDeletedItemDoesNotPersistACompletedRequest() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/saved")!
    let item = try makeHistoryItem(in: context, url: url)
    let gate = FetchGate()
    let loader = LinkPreviewLoader(fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    context.delete(item)
    try context.save()
    gate.complete(url)
    let result = await load.value
    XCTAssertNil(result)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItem>()), 0)
  }

  func testEditedSourceDoesNotPersistACompletedRequest() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/old")!
    let replacement = URL(string: "https://example.com/new")!
    let item = try makeHistoryItem(in: context, url: url)
    let gate = FetchGate()
    let loader = LinkPreviewLoader(fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    // Verify the source guard independently of the explicit generation invalidation.
    item.contents.first?.value = Data(replacement.absoluteString.utf8)
    item.title = replacement.absoluteString
    try context.save()
    gate.complete(url)
    let result = await load.value
    XCTAssertNil(result)
    XCTAssertNil(item.linkPreviewSnapshot)
  }

  func testGenerationInvalidationBlocksSaveWithoutCancellingSharedWaiters() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/saved")!
    let item = try makeHistoryItem(in: context, url: url)
    let gate = FetchGate()
    let loader = LinkPreviewLoader(fetch: { await gate.fetch($0) }, probe: { _ in .status(200) })
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    let shared = Task { await loader.result(for: url) }
    await Task.yield()
    item.linkPreviewGeneration = UUID()
    item.linkPreviewSnapshot = nil
    loader.invalidateCachedResult(for: url)
    gate.complete(url)
    let discarded = await load.value
    let sharedResult = await shared.value
    XCTAssertNil(discarded)
    guard case .preview = sharedResult else { return XCTFail("The shared waiter must still finish") }
    XCTAssertNil(item.linkPreviewSnapshot)
    XCTAssertNil(loader.cachedResult(for: url))
  }

  func testCompletedCacheCanBeInvalidatedWithoutChangingStoredSnapshot() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/saved")!
    let item = try makeHistoryItem(in: context, url: url)
    let loader = LinkPreviewLoader(fetch: { url in
      .preview(ClipboardLinkPreview(url: url, title: "Stored", image: nil))
    }, probe: { _ in .status(200) })
    _ = await loader.result(for: item, url: url)
    let snapshot = item.linkPreviewSnapshot
    XCTAssertNotNil(loader.cachedResult(for: url))
    loader.invalidateCachedResult(for: url)
    XCTAssertNil(loader.cachedResult(for: url))
    XCTAssertEqual(item.linkPreviewSnapshot, snapshot)
  }

  func testStoredResultMatchesFirstDisplayAndPreservesClipboardRepresentations() async throws {
    let container = try ModelContainer(for: HistoryItem.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let url = URL(string: "https://example.com/saved")!
    let item = try makeHistoryItem(in: context, url: url)
    let html = Data("<a href='https://example.com/saved'>Original formatting</a>".utf8)
    item.contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: html))
    try context.save()
    let originalContents = Dictionary(uniqueKeysWithValues: item.contents.map { ($0.type, $0.value) })
    let image = NSImage(size: NSSize(width: 2_400, height: 1_200))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let loader = LinkPreviewLoader(fetch: { url in
      .preview(ClipboardLinkPreview(url: url, title: "Page title", image: image))
    }, probe: { _ in .status(200) })
    let first = await loader.result(for: item, url: url)
    let stored = try XCTUnwrap(item.linkPreviewSnapshot)
    let decoded = LinkPreviewSnapshot.decode(stored, sourceURL: url)
    guard case .preview(let firstPreview) = first, case .preview(let decodedPreview) = decoded else {
      return XCTFail("Expected both rendered previews")
    }
    XCTAssertNotNil(firstPreview.image)
    XCTAssertEqual(firstPreview.image?.size, decodedPreview.image?.size)
    XCTAssertEqual(firstPreview.title, decodedPreview.title)
    XCTAssertEqual(Dictionary(uniqueKeysWithValues: item.contents.map { ($0.type, $0.value) }), originalContents)
    XCTAssertEqual(item.title, url.absoluteString)
  }

  func testYouTubeVideoTitleOverridesChannelMetadataAndPreservesURLAndImage() async {
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")!
    let image = NSImage(size: NSSize(width: 120, height: 80))
    var titleURLs: [URL] = []
    let loader = LinkPreviewLoader(fetch: { source in
      .preview(ClipboardLinkPreview(url: source, title: "Channel name", image: image))
    }, probe: { _ in .status(200) }, youtubeTitle: { source in
      titleURLs.append(source)
      return "Actual video title"
    })

    let preview = await loader.preview(for: url)

    XCTAssertEqual(preview?.title, "Actual video title")
    XCTAssertEqual(preview?.url, url)
    XCTAssertTrue(preview?.image === image)
    XCTAssertEqual(titleURLs, [url])
  }

  func testYouTubeTitleAloneSucceedsWhenLinkPresentationFails() async {
    let url = URL(string: "https://youtu.be/dQw4w9WgXcQ?t=42")!
    let loader = LinkPreviewLoader(fetch: { _ in .failure(.unavailable) },
                                  probe: { _ in .connectionFailure },
                                  youtubeTitle: { _ in "Actual video title" })

    let preview = await loader.preview(for: url)

    XCTAssertEqual(preview?.title, "Actual video title")
    XCTAssertEqual(preview?.url, url)
    XCTAssertNil(preview?.image)
  }

  func testYouTubeNotFoundStatusOverridesAvailableVideoTitle() async {
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    for status in [404, 410] {
      let loader = LinkPreviewLoader(fetch: { source in
        .preview(ClipboardLinkPreview(url: source, title: "Stale metadata", image: nil))
      }, probe: { _ in .status(status) }, youtubeTitle: { _ in "Stale video title" })

      assertFailure(await loader.result(for: url), equals: .notFound)
    }
  }

  func testLegacyYouTubeSnapshotRepairsOnlyTitleAndPersistsWithoutReencodingThumbnail() async throws {
    let container = try memoryContainer()
    let writer = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")!
    let item = try makeHistoryItem(in: writer, url: url)
    let legacy = try legacyYouTubeSnapshot(url: url)
    item.linkPreviewSnapshot = legacy
    try writer.save()
    let originalThumbnail = try XCTUnwrap(snapshotRecord(legacy)["thumbnail"] as? Data)
    let originalContents = Dictionary(uniqueKeysWithValues: item.contents.map { ($0.type, $0.value) })
    var requests = 0
    let loader = titleRepairLoader { source in
      XCTAssertEqual(source, url)
      requests += 1
      return "Correct video title"
    }

    let repaired = await loader.result(for: item, url: url)
    assertSameResult(repaired, .preview(ClipboardLinkPreview(url: url, title: "Correct video title", image: nil)))
    let saved = try XCTUnwrap(item.linkPreviewSnapshot)
    let record = try snapshotRecord(saved)
    XCTAssertEqual(record["thumbnail"] as? Data, originalThumbnail)
    XCTAssertEqual(record["youtubeTitleVersion"] as? Int, 1)
    XCTAssertEqual(Dictionary(uniqueKeysWithValues: item.contents.map { ($0.type, $0.value) }), originalContents)

    let reader = ModelContext(container)
    let restored = try XCTUnwrap(reader.model(for: item.persistentModelID) as? HistoryItem)
    XCTAssertEqual(restored.linkPreviewSnapshot, saved)
    let reopened = await offlineLoader().result(for: restored, url: url)
    assertSameResult(reopened, .preview(ClipboardLinkPreview(url: url, title: "Correct video title", image: nil)))
    _ = await loader.result(for: item, url: url)
    XCTAssertEqual(requests, 1)
  }

  func testUnavailableYouTubeTitleMarksLegacyRepairAttemptAndKeepsOriginalSnapshotContent() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://youtu.be/dQw4w9WgXcQ?t=42")!
    let item = try makeHistoryItem(in: context, url: url)
    let original = try legacyYouTubeSnapshot(url: url)
    item.linkPreviewSnapshot = original
    try context.save()
    var requests = 0
    let loader = titleRepairLoader { _ in requests += 1; return nil }

    let result = await loader.result(for: item, url: url)
    assertSameResult(result, .preview(ClipboardLinkPreview(url: url, title: "Old channel title", image: nil)))
    let patched = try XCTUnwrap(item.linkPreviewSnapshot)
    let record = try snapshotRecord(patched)
    XCTAssertEqual(record["youtubeTitleVersion"] as? Int, 1)
    XCTAssertEqual(record["thumbnail"] as? Data, try snapshotRecord(original)["thumbnail"] as? Data)
    _ = await loader.result(for: item, url: url)
    let reader = ModelContext(container)
    let restored = try XCTUnwrap(reader.model(for: item.persistentModelID) as? HistoryItem)
    let reopened = await offlineLoader().result(for: restored, url: url)
    assertSameResult(reopened, .preview(ClipboardLinkPreview(url: url, title: "Old channel title", image: nil)))
    XCTAssertEqual(requests, 1)
  }

  func testTwoWindowsShareLegacyYouTubeTitleRepair() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let item = try makeHistoryItem(in: context, url: url)
    item.linkPreviewSnapshot = try legacyYouTubeSnapshot(url: url)
    try context.save()
    let gate = YouTubeTitleGate()
    let loader = titleRepairLoader { await gate.fetch($0) }
    let first = Task { await loader.result(for: item, url: url) }
    let second = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    await Task.yield()

    gate.complete(url, title: "Shared video title")
    let expected = LinkPreviewResult.preview(ClipboardLinkPreview(url: url, title: "Shared video title", image: nil))
    assertSameResult(await first.value, expected)
    assertSameResult(await second.value, expected)
    XCTAssertEqual(gate.started, [url])
    XCTAssertEqual(try snapshotRecord(XCTUnwrap(item.linkPreviewSnapshot))["youtubeTitleVersion"] as? Int, 1)
  }

  func testLegacyTitleRepairAndRegularPreviewShareConcurrencyLimit() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let videoURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let otherURL = URL(string: "https://example.com/queued")!
    let item = try makeHistoryItem(in: context, url: videoURL)
    item.linkPreviewSnapshot = try legacyYouTubeSnapshot(url: videoURL)
    try context.save()
    let titleGate = YouTubeTitleGate()
    let metadataGate = FetchGate()
    let loader = LinkPreviewLoader(concurrentLimit: 1, fetch: { await metadataGate.fetch($0) },
                                  probe: { _ in .status(200) }, youtubeTitle: { await titleGate.fetch($0) })
    let repair = Task { await loader.result(for: item, url: videoURL) }
    await waitFor { titleGate.started.count == 1 }
    let ordinary = Task { await loader.result(for: otherURL) }
    for _ in 0..<10 { await Task.yield() }
    XCTAssertTrue(metadataGate.started.isEmpty)

    titleGate.complete(videoURL, title: "Video title")
    await waitFor { metadataGate.started.count == 1 }
    metadataGate.complete(otherURL)
    _ = await repair.value
    _ = await ordinary.value
    XCTAssertEqual(metadataGate.started, [otherURL])
  }

  func testCancelledLegacyYouTubeRepairLeavesAttemptUnmarked() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let item = try makeHistoryItem(in: context, url: url)
    let original = try legacyYouTubeSnapshot(url: url)
    item.linkPreviewSnapshot = original
    try context.save()
    let gate = YouTubeTitleGate()
    let loader = titleRepairLoader { await gate.fetch($0) }
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }

    load.cancel()
    let cancelled = await load.value
    XCTAssertNil(cancelled)
    gate.complete(url, title: "Too late")
    await Task.yield()
    XCTAssertEqual(item.linkPreviewSnapshot, original)

    let retryLoader = titleRepairLoader { _ in "Completed later" }
    let retry = await retryLoader.result(for: item, url: url)
    assertSameResult(retry, .preview(ClipboardLinkPreview(url: url, title: "Completed later", image: nil)))
  }

  func testDeletedItemCannotBeRecreatedByLegacyYouTubeRepair() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let item = try makeHistoryItem(in: context, url: url)
    item.linkPreviewSnapshot = try legacyYouTubeSnapshot(url: url)
    try context.save()
    let gate = YouTubeTitleGate()
    let loader = titleRepairLoader { await gate.fetch($0) }
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }

    context.delete(item)
    try context.save()
    gate.complete(url, title: "Too late")
    let result = await load.value

    XCTAssertNil(result)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItem>()), 0)
  }

  func testEditedItemCannotBeOverwrittenByLegacyYouTubeRepair() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let replacement = URL(string: "https://example.com/new")!
    let item = try makeHistoryItem(in: context, url: url)
    item.linkPreviewSnapshot = try legacyYouTubeSnapshot(url: url)
    try context.save()
    let gate = YouTubeTitleGate()
    let loader = titleRepairLoader { await gate.fetch($0) }
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    let changedSnapshot = try XCTUnwrap(LinkPreviewSnapshot.encode(.failure(.notFound), sourceURL: replacement))
    item.contents.first?.value = Data(replacement.absoluteString.utf8)
    item.title = replacement.absoluteString
    item.linkPreviewSnapshot = changedSnapshot
    try context.save()

    gate.complete(url, title: "Too late")
    let result = await load.value

    XCTAssertNil(result)
    XCTAssertEqual(item.linkPreviewSnapshot, changedSnapshot)
    XCTAssertEqual(item.linkPreviewSourceURL, replacement)
  }

  func testInvalidatedGenerationCannotBeOverwrittenByLegacyYouTubeRepair() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let item = try makeHistoryItem(in: context, url: url)
    let original = try legacyYouTubeSnapshot(url: url)
    item.linkPreviewSnapshot = original
    try context.save()
    let gate = YouTubeTitleGate()
    let loader = titleRepairLoader { await gate.fetch($0) }
    let load = Task { await loader.result(for: item, url: url) }
    await waitFor { gate.started.count == 1 }
    item.linkPreviewGeneration = UUID()

    gate.complete(url, title: "Too late")
    let result = await load.value

    XCTAssertNil(result)
    XCTAssertEqual(item.linkPreviewSnapshot, original)
  }

  func testOnlyLegacySuccessfulYouTubeVideosTriggerTitleRepair() async throws {
    let container = try memoryContainer()
    let context = ModelContext(container)
    let nonVideoURLs = [
      "https://www.youtube.com/@example", "https://www.youtube.com/playlist?list=PL123",
      "https://example.com/video"
    ]
    for value in nonVideoURLs {
      let url = URL(string: value)!
      let item = try makeHistoryItem(in: context, url: url)
      item.linkPreviewSnapshot = try legacyYouTubeSnapshot(url: url)
      let result = await offlineLoader().result(for: item, url: url)
      assertSameResult(result, .preview(ClipboardLinkPreview(url: url, title: "Old channel title", image: nil)))
    }
    let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    let item = try makeHistoryItem(in: context, url: url)
    let correct = LinkPreviewResult.preview(ClipboardLinkPreview(url: url, title: "Already corrected", image: nil))
    item.linkPreviewSnapshot = LinkPreviewSnapshot.encode(correct, sourceURL: url)
    let cached = await offlineLoader().result(for: item, url: url)
    assertSameResult(cached, correct)
    for failure in [LinkPreviewFailure.notFound, .unavailable, .connectionFailure] {
      item.linkPreviewSnapshot = LinkPreviewSnapshot.encode(.failure(failure), sourceURL: url)
      assertFailure(await offlineLoader().result(for: item, url: url), equals: failure)
    }
  }

  private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  private func snapshotRecord(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
  }

  private func legacyYouTubeSnapshot(url: URL) throws -> Data {
    let image = NSImage(size: NSSize(width: 80, height: 40))
    image.lockFocus()
    NSColor.blue.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let encoded = try XCTUnwrap(LinkPreviewSnapshot.encode(
      .preview(ClipboardLinkPreview(url: url, title: "Old channel title", image: image)), sourceURL: url
    ))
    var record = try snapshotRecord(encoded)
    record.removeValue(forKey: "youtubeTitleVersion")
    return try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
  }

  private func titleRepairLoader(
    _ title: @escaping @MainActor (URL) async -> String?
  ) -> LinkPreviewLoader {
    LinkPreviewLoader(fetch: { _ in
      XCTFail("Repairing an existing YouTube title must not fetch link metadata")
      return .failure(.unavailable)
    }, probe: { _ in
      XCTFail("Repairing an existing YouTube title must not probe the page")
      return .unavailable
    }, youtubeTitle: title)
  }

  @MainActor
  private final class YouTubeTitleGate {
    var started: [URL] = []
    var pending: [URL: CheckedContinuation<String?, Never>] = [:]

    func fetch(_ url: URL) async -> String? {
      started.append(url)
      return await withCheckedContinuation { pending[url] = $0 }
    }

    func complete(_ url: URL, title: String?) {
      pending.removeValue(forKey: url)?.resume(returning: title)
    }
  }

  private func makeHistoryItem(in context: ModelContext, url: URL) throws -> HistoryItem {
    let item = HistoryItem(contents: [HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue, value: Data(url.absoluteString.utf8)
    )])
    item.title = url.absoluteString
    context.insert(item)
    try context.save()
    return item
  }

  private func offlineLoader() -> LinkPreviewLoader {
    LinkPreviewLoader(fetch: { _ in
      XCTFail("A saved preview must never fetch metadata again")
      return .failure(.unavailable)
    }, probe: { _ in
      XCTFail("A saved preview must never probe the URL again")
      return .unavailable
    }, youtubeTitle: { _ in
      XCTFail("A saved preview must not request a YouTube title again")
      return nil
    })
  }

  private func writeSnapshot(_ result: LinkPreviewResult, url: URL, store: URL) async throws {
    let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: store))
    let context = ModelContext(container)
    let item = try makeHistoryItem(in: context, url: url)
    let loader = LinkPreviewLoader(fetch: { _ in result }, probe: { _ in
      if case .failure(.notFound) = result { return .status(404) }
      return .status(200)
    })
    _ = await loader.result(for: item, url: url)
    // The loader must have saved the model itself; no explicit save here.
    XCTAssertNotNil(item.linkPreviewSnapshot)
  }

  private func assertSameResult(
    _ actual: LinkPreviewResult?, _ expected: LinkPreviewResult,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    switch (actual, expected) {
    case (.preview(let actual), .preview(let expected)):
      XCTAssertEqual(actual.url, expected.url, file: file, line: line)
      XCTAssertEqual(actual.title, expected.title, file: file, line: line)
    case (.failure(let actual), .failure(let expected)):
      XCTAssertEqual(actual, expected, file: file, line: line)
    default:
      XCTFail("The stored result changed", file: file, line: line)
    }
  }

  private func assertFailure(
    _ result: LinkPreviewResult?, equals expected: LinkPreviewFailure,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    guard case .failure(let actual) = result else {
      return XCTFail("Expected a failure result", file: file, line: line)
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
  }

  private func waitFor(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<1_000 {
      if predicate() { return }
      await Task.yield()
    }
    XCTFail("Timed out waiting for the fake fetch", file: file, line: line)
  }

  @MainActor
  private final class FetchGate {
    var started: [URL] = []
    var pending: [URL: CheckedContinuation<LinkPreviewResult?, Never>] = [:]

    func fetch(_ url: URL) async -> LinkPreviewResult? {
      started.append(url)
      return await withCheckedContinuation { pending[url] = $0 }
    }

    func complete(_ url: URL, title: String = "Example") {
      pending.removeValue(forKey: url)?.resume(returning: .preview(
        ClipboardLinkPreview(url: url, title: title, image: nil)
      ))
    }
  }
}
