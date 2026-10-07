import AppKit
import Observation
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
