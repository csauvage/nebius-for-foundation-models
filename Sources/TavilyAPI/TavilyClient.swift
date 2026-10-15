// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Authentication sent by the Tavily client.
public enum TavilyAuth: Hashable, Sendable {
  /// Suitable for local development and simulators. Never ship an API key in
  /// an app bundle: it can be extracted by anyone who downloads the app.
  // Annotate the call site only; proxy-only clients produce no warning.
  #if NEBIUS_RELEASE_BUILD
    @available(
      *, deprecated,
      message:
        "Release build: direct Tavily API-key authentication. Never embed a provider key in a distributed app; use .proxied with your backend. User-supplied keys remain supported."
    )
  #endif
  case apiKey(String)

  /// Routes through a developer-controlled relay that injects the real Tavily
  /// credential. Headers can authorize the app or end user with that relay.
  case proxied(headers: [String: String])
}

/// A dependency-free client for Tavily Search, Extract, Map, Crawl, and Research.
public struct TavilyClient: @unchecked Sendable {
  public static let defaultBaseURL = URL(string: "https://api.tavily.com")!

  public let baseURL: URL
  public let headers: [String: String]
  private let session: URLSession

  public init(
    auth: TavilyAuth,
    baseURL: URL = TavilyClient.defaultBaseURL,
    timeout: TimeInterval = 150,
    projectID: String? = nil,
    sessionID: String? = nil,
    humanID: String? = nil,
    sessionConfiguration: URLSessionConfiguration? = nil
  ) throws {
    guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
      throw TavilyAPIError.invalidBaseURL(baseURL)
    }
    guard timeout > 0 else {
      throw TavilyAPIError.invalidRequest("timeout must be greater than zero")
    }

    var headers: [String: String]
    switch auth {
    case .apiKey(let key):
      guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TavilyAPIError.missingCredential
      }
      headers = ["Authorization": "Bearer \(key)"]
    case .proxied(let proxyHeaders):
      headers = proxyHeaders
    }
    if let projectID { headers["X-Project-ID"] = projectID }
    if let sessionID { headers["X-Session-Id"] = sessionID }
    if let humanID { headers["X-Human-Id"] = humanID }

    self.baseURL = baseURL
    self.headers = headers
    let configuration = sessionConfiguration ?? .ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    self.session = URLSession(
      configuration: configuration,
      delegate: TavilySameOriginRedirectDelegate(),
      delegateQueue: nil
    )
  }

  public func search(_ request: TavilySearchRequest) async throws -> TavilySearchResponse {
    try validate(request)
    return try await execute(makeURLRequest(request), expecting: [200])
  }

  public func extract(_ request: TavilyExtractRequest) async throws -> TavilyExtractResponse {
    try validate(request)
    return try await execute(makeURLRequest(request), expecting: [200])
  }

  public func map(_ request: TavilyMapRequest) async throws -> TavilyMapResponse {
    try validate(request)
    return try await execute(makeMapURLRequest(request), expecting: [200])
  }

  public func crawl(_ request: TavilyCrawlRequest) async throws -> TavilyCrawlResponse {
    try validate(request)
    return try await execute(makeCrawlURLRequest(request), expecting: [200])
  }

  public func createResearch(
    _ request: TavilyResearchRequest
  ) async throws -> TavilyResearchTask {
    try validate(request)
    guard !request.stream else {
      throw TavilyAPIError.invalidRequest(
        "createResearch requires stream=false; use researchStream for SSE"
      )
    }
    return try await execute(makeResearchURLRequest(request), expecting: [201])
  }

  public func researchStatus(
    requestID: String,
    includeUsage: Bool = false
  ) async throws -> TavilyResearchStatus {
    guard
      requestID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    else {
      throw TavilyAPIError.invalidRequest("research request ID contains invalid characters")
    }
    var components = URLComponents(
      url: endpointURL("research").appendingPathComponent(requestID),
      resolvingAgainstBaseURL: false
    )!
    if includeUsage {
      components.queryItems = [URLQueryItem(name: "include_usage", value: "true")]
    }
    var request = baseRequest(url: components.url!)
    request.httpMethod = "GET"
    let (data, response) = try await session.data(for: request)
    try Self.validate(response: response, body: data, expecting: [200, 202])

    let status = try JSONDecoder().decode(ResearchStatusEnvelope.self, from: data).status
    switch status {
    case "pending": return .pending(requestID: requestID)
    case "in_progress": return .inProgress(requestID: requestID)
    case "completed":
      return .completed(try JSONDecoder().decode(TavilyResearchCompleted.self, from: data))
    case "failed": return .failed(requestID: requestID)
    default:
      throw TavilyAPIError.invalidResponse("unknown research status: \(status)")
    }
  }

  /// Creates a research task and polls until it completes. Cancellation of the
  /// calling task stops polling immediately.
  public func research(
    _ request: TavilyResearchRequest,
    pollingInterval: TimeInterval = 2,
    timeout: TimeInterval = 150
  ) async throws -> TavilyResearchCompleted {
    guard pollingInterval > 0, timeout > 0 else {
      throw TavilyAPIError.invalidRequest("polling interval and timeout must be positive")
    }
    var request = request
    request.stream = false
    let task = try await createResearch(request)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))

    while clock.now < deadline {
      try Task.checkCancellation()
      switch try await researchStatus(requestID: task.requestID, includeUsage: true) {
      case .completed(let result): return result
      case .failed(let requestID):
        throw TavilyAPIError.researchFailed(requestID: requestID)
      case .pending, .inProgress:
        try await Task.sleep(for: .seconds(pollingInterval))
      }
    }
    throw TavilyAPIError.researchTimedOut(requestID: task.requestID)
  }

  /// Streams Tavily Research SSE events. Progress details are retained as
  /// flexible JSON because Tavily can add new research tool event kinds.
  public func researchStream(
    _ request: TavilyResearchRequest
  ) -> AsyncThrowingStream<TavilyResearchStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try validate(request)
          var request = request
          request.stream = true
          let urlRequest = try makeResearchURLRequest(request)
          #if canImport(Darwin)
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
              throw TavilyAPIError.invalidResponse("missing HTTP response")
            }
            guard httpResponse.statusCode == 200 else {
              let body = try await bytes.reduce(into: Data()) { data, byte in
                data.append(byte)
              }
              try Self.validate(response: response, body: body, expecting: [200])
              return
            }
            var parser = TavilyResearchSSEParser()
            for try await line in bytes.lines {
              if let event = try parser.consume(line) { continuation.yield(event) }
            }
            if let event = try parser.finish() { continuation.yield(event) }
          #else
            let (data, response) = try await session.data(for: urlRequest)
            try Self.validate(response: response, body: data, expecting: [200])
            var parser = TavilyResearchSSEParser()
            let body = String(decoding: data, as: UTF8.self)
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
              if let event = try parser.consume(String(line)) { continuation.yield(event) }
            }
            if let event = try parser.finish() { continuation.yield(event) }
          #endif
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func makeURLRequest(_ request: TavilySearchRequest) throws -> URLRequest {
    try validate(request)
    return try postRequest(request, endpoint: "search")
  }

  public func makeURLRequest(_ request: TavilyExtractRequest) throws -> URLRequest {
    try validate(request)
    return try postRequest(request, endpoint: "extract")
  }

  public func makeMapURLRequest(_ request: TavilyMapRequest) throws -> URLRequest {
    try validate(request)
    return try postRequest(request, endpoint: "map")
  }

  public func makeCrawlURLRequest(_ request: TavilyCrawlRequest) throws -> URLRequest {
    try validate(request)
    return try postRequest(request, endpoint: "crawl")
  }

  public func makeResearchURLRequest(_ request: TavilyResearchRequest) throws -> URLRequest {
    try validate(request)
    return try postRequest(request, endpoint: "research", acceptSSE: request.stream)
  }

  private func postRequest<T: Encodable>(
    _ body: T,
    endpoint: String,
    acceptSSE: Bool = false
  ) throws -> URLRequest {
    var request = baseRequest(url: endpointURL(endpoint))
    request.httpMethod = "POST"
    request.setValue(
      acceptSSE ? "text/event-stream" : "application/json",
      forHTTPHeaderField: "Accept"
    )
    request.httpBody = try JSONEncoder().encode(body)
    return request
  }

  private func baseRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    let defaults = [
      "Content-Type": "application/json",
      "Accept": "application/json",
      "User-Agent": "TavilyForFoundationModels/0.1",
    ]
    for (name, value) in defaults.merging(headers, uniquingKeysWith: { _, custom in custom }) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return request
  }

  private func endpointURL(_ endpoint: String) -> URL {
    if baseURL.lastPathComponent == endpoint { return baseURL }
    return baseURL.appendingPathComponent(endpoint)
  }

  private func execute<Response: Decodable>(
    _ request: URLRequest,
    expecting statusCodes: Set<Int>
  ) async throws -> Response {
    let (data, response) = try await session.data(for: request)
    try Self.validate(response: response, body: data, expecting: statusCodes)
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw TavilyAPIError.invalidResponse(String(describing: error))
    }
  }

  private static func validate(
    response: URLResponse,
    body: Data,
    expecting statusCodes: Set<Int>
  ) throws {
    guard let response = response as? HTTPURLResponse else {
      throw TavilyAPIError.invalidResponse("missing HTTP response")
    }
    guard statusCodes.contains(response.statusCode) else {
      let envelope = try? JSONDecoder().decode(TavilyErrorEnvelope.self, from: body)
      throw TavilyAPIError.httpError(
        statusCode: response.statusCode,
        message: envelope?.detail?.message,
        requestID: envelope?.requestID
      )
    }
  }

  private func validate(_ request: TavilySearchRequest) throws {
    try validateNonempty(request.query, name: "query")
    guard (1...3).contains(request.chunksPerSource) else {
      throw TavilyAPIError.invalidRequest("chunksPerSource must be between 1 and 3")
    }
    guard (0...20).contains(request.maxResults) else {
      throw TavilyAPIError.invalidRequest("maxResults must be between 0 and 20")
    }
    guard request.includeDomains.count <= 300, request.excludeDomains.count <= 150 else {
      throw TavilyAPIError.invalidRequest("too many search domain filters")
    }
    if request.includeDomainsMode != nil, request.includeDomains.isEmpty {
      throw TavilyAPIError.invalidRequest("includeDomainsMode requires includeDomains")
    }
    if request.filterByLanguage, request.language?.isEmpty != false {
      throw TavilyAPIError.invalidRequest("filterByLanguage requires language")
    }
    if request.country != nil, request.topic != .general {
      throw TavilyAPIError.invalidRequest("country is available only for general searches")
    }
    if request.safeSearch, request.searchDepth == .fast || request.searchDepth == .ultraFast {
      throw TavilyAPIError.invalidRequest("safeSearch is unavailable for fast search depths")
    }
    try validateDate(request.startDate, name: "startDate")
    try validateDate(request.endDate, name: "endDate")
  }

  private func validate(_ request: TavilyExtractRequest) throws {
    guard (1...20).contains(request.urls.count) else {
      throw TavilyAPIError.invalidRequest("Extract requires between 1 and 20 URLs")
    }
    try request.urls.forEach(validateWebURL)
    if let query = request.query {
      try validateNonempty(query, name: "extraction query")
    }
    if let chunks = request.chunksPerSource {
      guard request.query?.isEmpty == false else {
        throw TavilyAPIError.invalidRequest("chunksPerSource requires an extraction query")
      }
      guard (1...5).contains(chunks) else {
        throw TavilyAPIError.invalidRequest("chunksPerSource must be between 1 and 5")
      }
    }
    if let timeout = request.timeout, !(1...60).contains(timeout) {
      throw TavilyAPIError.invalidRequest("Extract timeout must be between 1 and 60 seconds")
    }
  }

  private func validate(_ request: TavilyMapRequest) throws {
    try validateSite(
      url: request.url,
      instructions: request.instructions,
      maxDepth: request.maxDepth,
      maxBreadth: request.maxBreadth,
      limit: request.limit,
      timeout: request.timeout
    )
  }

  private func validate(_ request: TavilyCrawlRequest) throws {
    try validateSite(
      url: request.url,
      instructions: request.instructions,
      maxDepth: request.maxDepth,
      maxBreadth: request.maxBreadth,
      limit: request.limit,
      timeout: request.timeout
    )
    if let chunks = request.chunksPerSource {
      guard request.instructions?.isEmpty == false else {
        throw TavilyAPIError.invalidRequest("chunksPerSource requires instructions")
      }
      guard (1...5).contains(chunks) else {
        throw TavilyAPIError.invalidRequest("chunksPerSource must be between 1 and 5")
      }
    }
  }

  private func validateSite(
    url: String,
    instructions: String?,
    maxDepth: Int,
    maxBreadth: Int,
    limit: Int,
    timeout: Double
  ) throws {
    try validateWebURL(url)
    if let instructions {
      try validateNonempty(instructions, name: "site instructions")
    }
    guard (1...5).contains(maxDepth) else {
      throw TavilyAPIError.invalidRequest("maxDepth must be between 1 and 5")
    }
    guard (1...500).contains(maxBreadth) else {
      throw TavilyAPIError.invalidRequest("maxBreadth must be between 1 and 500")
    }
    guard limit > 0 else {
      throw TavilyAPIError.invalidRequest("limit must be greater than zero")
    }
    guard (10...150).contains(timeout) else {
      throw TavilyAPIError.invalidRequest("site timeout must be between 10 and 150 seconds")
    }
  }

  private func validate(_ request: TavilyResearchRequest) throws {
    try validateNonempty(request.input, name: "research input")
    guard request.includeDomains.count <= 20, request.excludeDomains.count <= 20 else {
      throw TavilyAPIError.invalidRequest("Research supports at most 20 domain filters")
    }
    guard request.files.count <= 5 else {
      throw TavilyAPIError.invalidRequest("Research supports at most 5 files")
    }
    let extensions = Set(["txt", "md", "json"])
    for file in request.files {
      guard extensions.contains((file.name as NSString).pathExtension.lowercased()) else {
        throw TavilyAPIError.invalidRequest("Research files must be .txt, .md, or .json")
      }
      try validateNonempty(file.data, name: "research file data")
    }
    if let schema = request.outputSchema {
      guard case .object(let object) = schema, object["properties"] != nil else {
        throw TavilyAPIError.invalidRequest("outputSchema must be an object containing properties")
      }
    }
  }

  private func validateNonempty(_ value: String, name: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw TavilyAPIError.invalidRequest("\(name) must not be empty")
    }
  }

  private func validateWebURL(_ value: String) throws {
    guard let url = URL(string: value),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil
    else {
      throw TavilyAPIError.invalidRequest("invalid web URL: \(value)")
    }
  }

  private func validateDate(_ value: String?, name: String) throws {
    guard let value else { return }
    guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
    else {
      throw TavilyAPIError.invalidRequest("\(name) must use YYYY-MM-DD")
    }
  }
}

private struct ResearchStatusEnvelope: Decodable {
  let status: String
}

private struct TavilyResearchSSEParser {
  private var eventName: String?
  private var dataLines: [String] = []

  mutating func consume(_ line: String) throws -> TavilyResearchStreamEvent? {
    if line.isEmpty { return try emit() }
    if line.hasPrefix(":") { return nil }
    if line.hasPrefix("event:") {
      let nextEventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      let pending = dataLines.isEmpty ? nil : try emit()
      eventName = nextEventName
      return pending
    } else if line.hasPrefix("data:") {
      dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
      return try emitIfComplete()
    }
    return nil
  }

  mutating func finish() throws -> TavilyResearchStreamEvent? {
    try emit()
  }

  private mutating func emit() throws -> TavilyResearchStreamEvent? {
    defer {
      eventName = nil
      dataLines.removeAll(keepingCapacity: true)
    }
    let data = dataLines.joined(separator: "\n")
    if eventName == "done" || data == "[DONE]" { return .done }
    guard !data.isEmpty else { return nil }
    guard let bytes = data.data(using: .utf8) else {
      throw TavilyAPIError.invalidResponse("research SSE contains invalid UTF-8")
    }
    do {
      let chunk = try JSONDecoder().decode(TavilyResearchStreamChunk.self, from: bytes)
      if let message = chunk.error { return .failure(message: message) }
      return .chunk(chunk)
    } catch {
      throw TavilyAPIError.invalidResponse("invalid research SSE event: \(error)")
    }
  }

  private mutating func emitIfComplete() throws -> TavilyResearchStreamEvent? {
    let data = dataLines.joined(separator: "\n")
    if data == "[DONE]" { return try emit() }
    guard let bytes = data.data(using: .utf8),
      (try? JSONDecoder().decode(TavilyResearchStreamChunk.self, from: bytes)) != nil
    else {
      return nil
    }
    return try emit()
  }
}

/// A custom Authorization header must never follow a redirect to another
/// origin. Same-origin redirects remain available for canonicalization.
private final class TavilySameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate,
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
