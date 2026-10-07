import XCTest
@testable import Maccy

final class YouTubeLinkMetadataTests: XCTestCase {
  private let videoID = "DzHMhNyjcOQ"
  private var canonical: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }

  func testCanonicalizesWatchURLsAndDropsPlaybackParameters() {
    for host in ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"] {
      let url = URL(string: "https://\(host)/watch?v=\(videoID)&t=201s&list=playlist#fragment")!
      XCTAssertEqual(YouTubeLinkMetadata.canonicalVideoURL(from: url), canonical)
    }
  }

  func testCanonicalizesShortLiveEmbedAndShareURLs() {
    let urls = [
      "https://youtu.be/\(videoID)?si=tracking&t=201",
      "https://www.youtube.com/shorts/\(videoID)",
      "https://m.youtube.com/live/\(videoID)?feature=share",
      "https://youtube.com/embed/\(videoID)?autoplay=1",
      "https://www.youtube-nocookie.com/embed/\(videoID)",
      "https://youtube-nocookie.com/embed/\(videoID)"
    ]
    for value in urls {
      XCTAssertEqual(YouTubeLinkMetadata.canonicalVideoURL(from: URL(string: value)!), canonical, value)
    }
  }

  func testAcceptsCaseInsensitiveHostsAndValidASCIIVideoIDSymbols() {
    let url = URL(string: "https://WWW.YOUTUBE.COM/watch?v=Aa09_-BbCcD")!
    XCTAssertEqual(YouTubeLinkMetadata.canonicalVideoURL(from: url)?.absoluteString,
                   "https://www.youtube.com/watch?v=Aa09_-BbCcD")
  }

  func testRejectsCredentialsAndUntrustedHosts() {
    let urls = [
      "https://youtube.com.evil.example/watch?v=\(videoID)",
      "https://evil-youtube.com/watch?v=\(videoID)",
      "https://youtu.be.evil.example/\(videoID)",
      "https://www.youtube.com@evil.example/watch?v=\(videoID)",
      "https://user:password@www.youtube.com/watch?v=\(videoID)",
      "https://user@youtu.be/\(videoID)",
      "https://www.youtube.com:444/watch?v=\(videoID)",
      "ftp://www.youtube.com/watch?v=\(videoID)",
      "file:///watch?v=\(videoID)"
    ]
    for value in urls {
      XCTAssertNil(YouTubeLinkMetadata.canonicalVideoURL(from: URL(string: value)!), value)
    }
  }

  func testRejectsChannelsPlaylistsAndMalformedVideoIDs() {
    let urls = [
      "https://www.youtube.com/@StillPlaces",
      "https://www.youtube.com/channel/\(videoID)",
      "https://www.youtube.com/playlist?list=\(videoID)",
      "https://www.youtube.com/watch",
      "https://www.youtube.com/watch?v=short",
      "https://www.youtube.com/watch?v=\(videoID)long",
      "https://www.youtube.com/watch?v=abcdefghij!",
      "https://www.youtube.com/watch?v=\(videoID)&v=\(videoID)",
      "https://youtu.be/\(videoID)/extra",
      "https://www.youtube.com/embed/\(videoID)/extra",
      "https://www.youtube-nocookie.com/watch?v=\(videoID)",
      "https://www.youtube.com/watch?v=abcdefghij한"
    ]
    for value in urls {
      XCTAssertNil(YouTubeLinkMetadata.canonicalVideoURL(from: URL(string: value)!), value)
    }
  }

  func testBuildsYouTubeOEmbedEndpointWithOnlyCanonicalVideoURL() throws {
    let original = URL(string: "https://www.youtube.com/watch?v=\(videoID)&t=201s")!
    let endpoint = try XCTUnwrap(YouTubeLinkMetadata.oEmbedURL(for: original))
    let components = try XCTUnwrap(URLComponents(url: endpoint, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "https")
    XCTAssertEqual(components.host, "www.youtube.com")
    XCTAssertEqual(components.path, "/oembed")
    XCTAssertEqual(components.queryItems, [
      URLQueryItem(name: "url", value: canonical.absoluteString),
      URLQueryItem(name: "format", value: "json")
    ])
    XCTAssertEqual(original.absoluteString, "https://www.youtube.com/watch?v=\(videoID)&t=201s")
    XCTAssertNil(YouTubeLinkMetadata.oEmbedURL(for: URL(string: "https://example.com/")!))
  }

  func testDecodesVideoTitleInsteadOfChannelAuthorName() throws {
    let expected = "Cozy Coastal Fire Pit 🌅 Ocean Sounds & Crackling Fire"
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "video", "title": " \n\(expected)\n ", "author_name": "Still Places"
    ])
    XCTAssertEqual(YouTubeLinkMetadata.title(from: data), expected)
  }

  func testRejectsInvalidMissingAndNonVideoMetadata() throws {
    let documents: [[String: Any]] = [
      ["type": "video", "author_name": "Still Places"],
      ["type": "video", "title": " \n\t "],
      ["type": "link", "title": "Not a video"],
      ["title": "Missing type"],
      ["type": "video", "title": 123]
    ]
    for document in documents {
      XCTAssertNil(YouTubeLinkMetadata.title(from: try JSONSerialization.data(withJSONObject: document)))
    }
    XCTAssertNil(YouTubeLinkMetadata.title(from: Data("invalid json".utf8)))
  }

  func testBoundsResponseSizeBeforeDecoding() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "video", "title": "Title", "unused": String(repeating: "x", count: 64 * 1_024)
    ])
    XCTAssertNil(YouTubeLinkMetadata.title(from: data))
  }

  func testBoundsTitleLengthWithoutSplittingUnicodeCharacters() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "video", "title": String(repeating: "🌅", count: 3_000)
    ])
    let title = try XCTUnwrap(YouTubeLinkMetadata.title(from: data))
    XCTAssertEqual(title.count, 2_048)
    XCTAssertLessThanOrEqual(title.utf8.count, 16 * 1_024)
    XCTAssertTrue(title.allSatisfy { $0 == "🌅" })
  }

  func testRejectsASingleGraphemeThatExceedsTitleByteBudget() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "video", "title": "a" + String(repeating: "\u{0301}", count: 10_000)
    ])
    XCTAssertNil(YouTubeLinkMetadata.title(from: data))
  }
}
