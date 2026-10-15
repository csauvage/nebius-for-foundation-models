// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct NebiusClient: @unchecked Sendable {
  public static let defaultBaseURL = URL(string: "https://api.tokenfactory.nebius.com/v1")!

  public let baseURL: URL
  public let chatCompletionsPath: String?
  public let endpointURL: URL
  public let headers: [String: String]
  let session: URLSession
  // Set only by the explicit direct-key initializer. Arbitrary headers (including
  // relay tokens) must never authorize control-plane operations.
  private(set) var directAPIKey: String?

  #if NEBIUS_RELEASE_BUILD
    @available(
      *, deprecated,
      message:
        "Release build: direct Nebius management API-key authentication. Never embed a provider key in a distributed app; use a backend for app-owned credentials. User-supplied keys remain supported."
    )
  #endif
  public init(directAPIKey: String, sessionConfiguration: URLSessionConfiguration? = nil) throws {
    let key = directAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty,
      !key.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      })
    else { throw DedicatedEndpointAPIError.directAPIKeyRequired }
    try self.init(
      headers: ["Authorization": "Bearer \(key)"], sessionConfiguration: sessionConfiguration)
    self.directAPIKey = key
  }

  public init(
    baseURL: URL = NebiusClient.defaultBaseURL,
    chatCompletionsPath: String? = nil,
    headers: [String: String],
    sessionConfiguration: URLSessionConfiguration? = nil
  ) throws {
    guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
      throw NebiusTransportError.invalidBaseURL(baseURL)
    }
    self.endpointURL = try Self.chatEndpointURL(
      baseURL: baseURL, chatCompletionsPath: chatCompletionsPath)
    self.chatCompletionsPath = chatCompletionsPath
    self.baseURL = baseURL
    self.headers = headers
    let configuration = sessionConfiguration ?? .ephemeral
    self.session = URLSession(
      configuration: configuration,
      delegate: SameOriginRedirectDelegate(),
      delegateQueue: nil
    )
  }

  public func stream(
    _ request: ChatCompletionRequest
  ) -> AsyncThrowingStream<ChatCompletionChunk, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let urlRequest = try makeURLRequest(request)
          #if canImport(Darwin)
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
              throw NebiusTransportError.invalidStreamData("Missing HTTP response")
            }
            guard httpResponse.statusCode == 200 else {
              let body = try await bytes.reduce(into: Data()) { data, byte in
                data.append(byte)
              }
              try Self.validate(response: response, body: body)
              return
            }

            let parser = SSEParser()
            for try await line in bytes.lines {
              if let chunk = try parser.parse(line) {
                continuation.yield(chunk)
              }
            }
          #else
            let (data, response) = try await session.data(for: urlRequest)
            try Self.validate(response: response, body: data)

            let parser = SSEParser()
            let body = String(data: data, encoding: .utf8) ?? ""
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
              if let chunk = try parser.parse(String(line)) {
                continuation.yield(chunk)
              }
            }
          #endif
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func makeURLRequest(_ request: ChatCompletionRequest) throws -> URLRequest {
    var urlRequest = URLRequest(url: endpointURL)
    urlRequest.httpMethod = "POST"

    let defaults = [
      "Content-Type": "application/json",
      "Accept": "text/event-stream",
      "User-Agent": "NebiusForFoundationModels/0.1",
    ]
    for (name, value) in defaults.merging(headers, uniquingKeysWith: { _, custom in custom }) {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    urlRequest.httpBody = try JSONEncoder().encode(request)
    return urlRequest
  }

  /// Resolves the inference URL without creating a session or sending a request.
  /// A nil path preserves automatic Nebius routing. An explicit path is appended to
  /// the entire base URL path, with no version detection or insertion. A leading
  /// slash is optional; it does not replace the base URL path.
  public static func chatEndpointURL(baseURL: URL, chatCompletionsPath: String? = nil) throws -> URL
  {
    guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
      throw NebiusTransportError.invalidBaseURL(baseURL)
    }
    if let chatCompletionsPath {
      let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
      let segments = chatCompletionsPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      guard !segments.isEmpty, !chatCompletionsPath.contains("//"),
        chatCompletionsPath.unicodeScalars.allSatisfy({ allowed.contains($0) }),
        !segments.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
      else { throw NebiusChatRouteError.invalidPath }
      return baseURL.appendingPathComponent(segments)
    }
    let versioned = baseURL.pathComponents.contains { component in
      component.range(of: #"^v[0-9]+$"#, options: .regularExpression) != nil
    }
    return baseURL.appendingPathComponent(versioned ? "chat/completions" : "v1/chat/completions")
  }

  private static func validate(response: URLResponse, body: Data?) throws {
    guard let response = response as? HTTPURLResponse else {
      throw NebiusTransportError.invalidStreamData("Missing HTTP response")
    }
    guard response.statusCode == 200 else {
      let body = body ?? Data()
      if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body) {
        throw envelope.error
      }
      throw NebiusTransportError.httpError(statusCode: response.statusCode, body: body)
    }
  }
}

/// A custom Authorization header must never follow a redirect to another
/// origin. Same-origin redirects remain available for infrastructure-level
/// canonicalization.
private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let source = task.currentRequest?.url ?? task.originalRequest?.url,
      let destination = request.url,
      source.scheme?.caseInsensitiveCompare(destination.scheme ?? "") == .orderedSame,
      source.host?.caseInsensitiveCompare(destination.host ?? "") == .orderedSame,
      effectivePort(source) == effectivePort(destination)
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  private func effectivePort(_ url: URL) -> Int? {
    if let port = url.port { return port }
    switch url.scheme?.lowercased() {
    case "https": return 443
    case "http": return 80
    default: return nil
    }
  }
}

/// Invalid route configuration, reported without including credential-bearing input.
public enum NebiusChatRouteError: LocalizedError, Sendable {
  case invalidPath
  public var errorDescription: String? {
    "Use a nonempty API path with letters, digits, slashes, hyphens, underscores, dots or tildes; no URL, query, fragment or dot segments."
  }
}
