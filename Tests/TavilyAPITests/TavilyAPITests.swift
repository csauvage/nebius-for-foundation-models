// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation
import TavilyAPI

#if canImport(FoundationModels)
  import FoundationModels
  import TavilyForFoundationModels
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

@main
struct TavilyAPITests {
  static func main() async throws {
    try endpointAndHeaders()
    try requestEncoding()
    try responseDecoding()
    try validation()
    try await transportSuccess()
    try await transportError()
    try await researchPolling()
    try await researchStreaming()
    #if canImport(FoundationModels)
      if #available(macOS 26.0, iOS 26.0, visionOS 26.0, watchOS 26.0, *) {
        try await toolOutput()
      }
    #endif
    print("TavilyAPITests: 9 tests passed")
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) throws {
    guard condition() else { throw TestFailure(description: message) }
  }

  private static func endpointAndHeaders() throws {
    let client = try TavilyClient(
      auth: .apiKey("tvly-test"),
      projectID: "project",
      sessionID: "session",
      humanID: "human"
    )
    let request = try client.makeURLRequest(TavilySearchRequest(query: "Swift"))
    try expect(request.url?.absoluteString == "https://api.tavily.com/search", "Wrong endpoint")
    try expect(
      request.value(forHTTPHeaderField: "Authorization") == "Bearer tvly-test",
      "Missing Tavily authorization"
    )
    try expect(request.value(forHTTPHeaderField: "X-Project-ID") == "project", "Missing project")
    try expect(request.value(forHTTPHeaderField: "X-Session-Id") == "session", "Missing session")
    try expect(request.value(forHTTPHeaderField: "X-Human-Id") == "human", "Missing human")

    let proxy = try TavilyClient(
      auth: .proxied(headers: ["X-App-Token": "test"]),
      baseURL: URL(string: "https://example.com/tavily")!
    )
    let proxyRequest = try proxy.makeCrawlURLRequest(
      TavilyCrawlRequest(url: "https://swift.org")
    )
    try expect(
      proxyRequest.url?.absoluteString == "https://example.com/tavily/crawl",
      "Wrong proxy endpoint"
    )
    try expect(
      proxyRequest.value(forHTTPHeaderField: "X-App-Token") == "test",
      "Proxy headers were not forwarded"
    )
  }

  private static func requestEncoding() throws {
    let client = try TavilyClient(auth: .apiKey("test"))
    let search = try client.makeURLRequest(
      TavilySearchRequest(
        query: "Foundation Models",
        searchDepth: .advanced,
        chunksPerSource: 2,
        maxResults: 5,
        topic: .news,
        timeRange: .week,
        includePublishedDate: true,
        includeUsage: true,
        safeSearch: true
      )
    )
    let json = try object(search.httpBody)
    try expect(json["search_depth"] as? String == "advanced", "Wrong search depth")
    try expect(json["max_results"] as? Int == 5, "Wrong search result limit")
    try expect(json["include_answer"] as? Bool == false, "Answer should be disabled")
    try expect(json["include_raw_content"] as? Bool == false, "Raw content should be disabled")

    let extract = try client.makeURLRequest(
      TavilyExtractRequest(
        urls: ["https://developer.apple.com"],
        query: "Foundation Models tools",
        chunksPerSource: 3
      )
    )
    let extractJSON = try object(extract.httpBody)
    try expect(extractJSON["urls"] as? [String] == ["https://developer.apple.com"], "Wrong URLs")
    try expect(extractJSON["chunks_per_source"] as? Int == 3, "Wrong extract chunks")

    let map = try client.makeMapURLRequest(
      TavilyMapRequest(url: "https://docs.tavily.com", maxDepth: 2, allowExternal: false)
    )
    try expect(map.url?.path.hasSuffix("/map") == true, "Wrong Map endpoint")

    let research = try client.makeResearchURLRequest(
      TavilyResearchRequest(input: "Compare model providers", outputLength: .short)
    )
    let researchJSON = try object(research.httpBody)
    try expect(researchJSON["citation_format"] as? String == "numbered", "Wrong citations")
    try expect(researchJSON["output_length"] as? String == "short", "Wrong output length")
  }

  private static func responseDecoding() throws {
    let searchData = Data(
      #"{"query":"Swift","results":[{"title":"Swift","url":"https://swift.org","content":"A language","score":0.9}],"response_time":0.2,"request_id":"req"}"#
        .utf8
    )
    let search = try JSONDecoder().decode(TavilySearchResponse.self, from: searchData)
    try expect(search.results.first?.url == "https://swift.org", "Search result was not decoded")
    try expect(search.answer == nil, "Missing answer should remain optional")

    let researchData = Data(
      #"{"request_id":"r1","status":"completed","content":{"company":"Acme"},"sources":[{"title":"Acme","url":"https://example.com"}],"response_time":1.5}"#
        .utf8
    )
    let research = try JSONDecoder().decode(TavilyResearchCompleted.self, from: researchData)
    try expect(
      research.content.promptText.contains("Acme"),
      "Structured research content was not decoded"
    )

    let extractData = Data(
      #"{"results":[{"url":"https://example.com","raw_content":"Page"}],"failed_results":[],"request_id":"e1"}"#
        .utf8
    )
    let extract = try JSONDecoder().decode(TavilyExtractResponse.self, from: extractData)
    try expect(extract.results?.first?.rawContent == "Page", "Extract result was not decoded")

    let mapData = Data(
      #"{"base_url":"https://example.com","results":["https://example.com/docs"]}"#.utf8
    )
    let map = try JSONDecoder().decode(TavilyMapResponse.self, from: mapData)
    try expect(map.results == ["https://example.com/docs"], "Map result was not decoded")

    let crawlData = Data(
      #"{"base_url":"https://example.com","results":[{"url":"https://example.com/docs","raw_content":"Docs"}]}"#
        .utf8
    )
    let crawl = try JSONDecoder().decode(TavilyCrawlResponse.self, from: crawlData)
    try expect(crawl.results?.first?.rawContent == "Docs", "Crawl result was not decoded")
  }

  private static func validation() throws {
    do {
      _ = try TavilyClient(auth: .apiKey(""))
      throw TestFailure(description: "An empty API key was accepted")
    } catch TavilyAPIError.missingCredential {}

    do {
      _ = try TavilyClient(
        auth: .apiKey("test"),
        baseURL: URL(string: "http://api.tavily.com")!
      )
      throw TestFailure(description: "An insecure endpoint was accepted")
    } catch TavilyAPIError.invalidBaseURL {}

    let client = try TavilyClient(auth: .apiKey("test"))
    do {
      _ = try client.makeURLRequest(
        TavilySearchRequest(query: "Swift", searchDepth: .fast, safeSearch: true)
      )
      throw TestFailure(description: "An incompatible safe search request was accepted")
    } catch TavilyAPIError.invalidRequest {}
  }

  private static func transportSuccess() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.handler = { request in
      let body = Data(
        #"{"query":"Swift","results":[],"response_time":0.1,"request_id":"ok"}"#.utf8
      )
      return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        body
      )
    }
    let client = try TavilyClient(
      auth: .apiKey("test"),
      sessionConfiguration: configuration
    )
    let response = try await client.search(TavilySearchRequest(query: "Swift"))
    try expect(response.requestID == "ok", "Transport response was not decoded")
  }

  private static func transportError() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.handler = { request in
      let body = Data(#"{"detail":{"error":"Rate limit exceeded"},"request_id":"limit"}"#.utf8)
      return (
        HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
        body
      )
    }
    let client = try TavilyClient(
      auth: .apiKey("test"),
      sessionConfiguration: configuration
    )
    do {
      _ = try await client.search(TavilySearchRequest(query: "Swift"))
      throw TestFailure(description: "Expected a Tavily HTTP error")
    } catch TavilyAPIError.httpError(let status, let message, let requestID) {
      try expect(status == 429, "Wrong HTTP error status")
      try expect(message == "Rate limit exceeded", "Tavily error message was lost")
      try expect(requestID == "limit", "Tavily request ID was lost")
    }
  }

  private static func researchPolling() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let counter = LockedCounter()
    MockURLProtocol.handler = { request in
      if request.httpMethod == "POST" {
        let body = Data(
          #"{"request_id":"research-1","created_at":"2026-09-15T00:00:00Z","status":"pending","input":"Swift","model":"mini","response_time":0.1}"#
            .utf8
        )
        return (
          HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
          body
        )
      }
      let call = counter.increment()
      if call == 1 {
        let body = Data(
          #"{"request_id":"research-1","status":"in_progress","response_time":0.1}"#.utf8
        )
        return (
          HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
          body
        )
      }
      let body = Data(
        #"{"request_id":"research-1","status":"completed","content":"Report","sources":[{"title":"Swift","url":"https://swift.org"}],"response_time":1.0}"#
          .utf8
      )
      return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        body
      )
    }
    let client = try TavilyClient(
      auth: .apiKey("test"),
      sessionConfiguration: configuration
    )
    let result = try await client.research(
      TavilyResearchRequest(input: "Swift"),
      pollingInterval: 0.001,
      timeout: 2
    )
    try expect(result.content.promptText == "Report", "Research polling lost the report")
    try expect(counter.value == 2, "Research polling did not wait for completion")
  }

  private static func researchStreaming() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.handler = { request in
      let body = Data(
        """
        data: {"id":"event-1","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant","content":"Bonjour"}}]}

        event: done

        """.utf8
      )
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "text/event-stream"]
      )!
      return (response, body)
    }
    let client = try TavilyClient(
      auth: .apiKey("test"),
      sessionConfiguration: configuration
    )
    var chunkCount = 0
    var sawDone = false
    for try await event in client.researchStream(TavilyResearchRequest(input: "Swift")) {
      switch event {
      case .chunk(let chunk):
        chunkCount += 1
        try expect(chunk.id == "event-1", "Wrong research stream chunk")
      case .failure(let message):
        throw TestFailure(description: "Unexpected research stream failure: \(message)")
      case .done:
        sawDone = true
      }
    }
    try expect(chunkCount == 1, "Research stream did not emit its chunk")
    try expect(sawDone, "Research stream did not emit done")
  }

  #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, watchOS 26.0, *)
    private static func toolOutput() async throws {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockURLProtocol.self]
      MockURLProtocol.handler = { request in
        let body = Data(
          #"{"query":"Swift","results":[{"title":"Swift.org","url":"https://swift.org","content":"Official Swift information","published_date":"Mon, 14 Sep 2026 10:00:00 GMT"}]}"#
            .utf8
        )
        return (
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
          body
        )
      }
      let client = try TavilyClient(
        auth: .apiKey("test"),
        sessionConfiguration: configuration
      )
      let tool = TavilySearchTool(client: client)
      let output = try await tool.call(arguments: .init(query: "Swift"))
      try expect(output.contains("untrusted web content"), "Tool output lost its safety warning")
      try expect(output.contains("https://swift.org"), "Tool output lost the source URL")
      try expect(output.contains("Official Swift information"), "Tool output lost its evidence")

      let boundedTool = TavilySearchTool(
        client: client,
        configuration: .init(
          output: .init(maximumCharacters: 80, maximumItems: 1)
        )
      )
      let bounded = try await boundedTool.call(arguments: .init(query: "Swift"))
      try expect(bounded.count <= 80, "Tool output exceeded its configured character limit")
      try expect(bounded.contains("Output truncated"), "Truncated tool output was not marked")
    }
  #endif

  private static func object(_ data: Data?) throws -> [String: Any] {
    guard let data,
      let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw TestFailure(description: "Request body is missing or invalid")
    }
    return value
  }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) =
    { request in
      throw TestFailure(
        description: "No mock handler for \(request.url?.absoluteString ?? "request")")
    }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      let (response, data) = try Self.handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    storage += 1
    return storage
  }

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}
