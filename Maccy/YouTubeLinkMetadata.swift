import Foundation

/// Video-specific titles from YouTube's own oEmbed endpoint.
/// The original clipboard URL remains untouched, including its timestamp and playlist parameters.
@MainActor
enum YouTubeLinkMetadata {
  nonisolated static let maximumResponseBytes = 64 * 1_024
  nonisolated static let maximumTitleCharacters = 2_048
  nonisolated static let maximumTitleBytes = 16 * 1_024

  nonisolated static func canonicalVideoURL(from url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          url.user == nil, url.password == nil,
          url.port == nil || url.port == (scheme == "https" ? 443 : 80),
          let host = url.host?.lowercased(),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

    let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
    let videoID: String?
    switch host {
    case "youtu.be":
      videoID = path.count == 1 ? String(path[0]) : nil
    case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
      if path.count == 1, path[0] == "watch" {
        let values = components.queryItems?.filter { $0.name == "v" } ?? []
        videoID = values.count == 1 ? values[0].value : nil
      } else if path.count == 2, ["shorts", "live", "embed"].contains(String(path[0])) {
        videoID = String(path[1])
      } else {
        videoID = nil
      }
    case "youtube-nocookie.com", "www.youtube-nocookie.com":
      videoID = path.count == 2 && path[0] == "embed" ? String(path[1]) : nil
    default:
      return nil
    }
    guard let videoID, validVideoID(videoID) else { return nil }
    var canonical = URLComponents()
    canonical.scheme = "https"
    canonical.host = "www.youtube.com"
    canonical.path = "/watch"
    canonical.queryItems = [URLQueryItem(name: "v", value: videoID)]
    return canonical.url
  }

  nonisolated static func oEmbedURL(for url: URL) -> URL? {
    guard let videoURL = canonicalVideoURL(from: url) else { return nil }
    var endpoint = URLComponents()
    endpoint.scheme = "https"
    endpoint.host = "www.youtube.com"
    endpoint.path = "/oembed"
    endpoint.queryItems = [
      URLQueryItem(name: "url", value: videoURL.absoluteString),
      URLQueryItem(name: "format", value: "json")
    ]
    return endpoint.url
  }

  static func title(for url: URL) async -> String? {
    guard !Task.isCancelled, let endpoint = oEmbedURL(for: url) else { return nil }
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
      let (bytes, response) = try await session.bytes(from: endpoint)
      defer { bytes.task.cancel() }
      guard !Task.isCancelled, let response = response as? HTTPURLResponse,
            response.statusCode == 200,
            response.expectedContentLength <= Int64(maximumResponseBytes) else { return nil }
      var data = Data()
      for try await byte in bytes {
        guard !Task.isCancelled, data.count < maximumResponseBytes else { return nil }
        data.append(byte)
      }
      guard !Task.isCancelled else { return nil }
      return title(from: data)
    } catch {
      return nil
    }
  }

  nonisolated static func title(from data: Data) -> String? {
    guard data.count <= maximumResponseBytes,
          let metadata = try? JSONDecoder().decode(VideoMetadata.self, from: data),
          metadata.type == "video" else { return nil }
    var title = String(metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(maximumTitleCharacters))
    // Do not split a grapheme, even when it contains an unusually large number of combining marks.
    while title.utf8.count > maximumTitleBytes { title = String(title.prefix(title.count / 2)) }
    return title.isEmpty ? nil : title
  }

  nonisolated private struct VideoMetadata: Decodable, Sendable {
    let type: String
    let title: String
  }

  nonisolated private static func validVideoID(_ value: String) -> Bool {
    value.utf8.count == 11 && value.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
    }
  }
}
