// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation
import NebiusAPI

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private let endpointID = "15951bdb-98c1-492f-9142-76e4216e2f65"
private let endpointJSON =
  #"{"id":"15951bdb-98c1-492f-9142-76e4216e2f65","name":"test","description":"","enabled":true,"routing_key":"test-route","model_name":"example/model","flavor_name":"base","region":"eu-north1","gpu_type":"H100","gpu_count":2,"scaling":{"min_replicas":1,"max_replicas":3},"deployment":{"ready_replicas":1,"status":"UNKNOWN_FUTURE_STATE","readiness":"READY"},"created_at":"2026-09-16T00:00:00Z","reservation_policy":{"policy":"AUTO"},"custom_weights_id":null}"#
private let templatesJSON =
  #"{"object":"list","data":[{"name":"example/model","type":"text","metadata":{"context_length":4096},"flavors":{"base":{"quantization":"fp8","use_cases":["chat"],"tags":[],"base_model_slug":"example/model","available_configurations":{"gpu_configurations":{"H100":{"allowed_regions":["eu-north1"],"allowed_gpu_counts":[2,4],"max_replicas_allowed":3}}}}}}]}"#

private struct EndpointTestFailure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw EndpointTestFailure(message: message) }
}

private final class EndpointHTTPState: @unchecked Sendable {
  let lock = NSLock()
  private var status = 200
  private var body = ""
  private var records: [(URLRequest, Data?)] = []
  var requests: [(URLRequest, Data?)] { lock.withLock { records } }
  func respond(_ body: String, status: Int = 200) {
    lock.withLock {
      self.body = body
      self.status = status
    }
  }
  func receive(_ request: URLRequest) -> (Int, String) {
    var data = request.httpBody
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 4096)
      var result = Data()
      while true {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }
        result.append(contentsOf: bytes.prefix(count))
      }
      data = result
    }
    return lock.withLock {
      records.append((request, data))
      return (status, body)
    }
  }
}

private final class EndpointURLProtocol: URLProtocol, @unchecked Sendable {
  static let state = EndpointHTTPState()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, body) = Self.state.receive(request)
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: status,
        httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

extension NebiusAPITests {
  static func dedicatedEndpointAPITests() async throws {
    let state = EndpointURLProtocol.state
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EndpointURLProtocol.self]
    let client = try NebiusClient(
      directAPIKey: "  test-direct-key\n", sessionConfiguration: configuration)
    state.respond("{\"data\":[\(endpointJSON)],\"object\":\"list\"}")
    let endpoints = try await client.listDedicatedEndpoints()
    try check(
      endpoints.count == 1 && endpoints[0].gpuCount == 2, "Decode endpoint snake-case fields")
    try check(
      endpoints[0].deployment.status == "UNKNOWN_FUTURE_STATE",
      "Preserve unknown deployment statuses")
    state.respond(templatesJSON)
    let templates = try await client.listDedicatedEndpointTemplates()
    let create = DedicatedEndpointCreateRequest(
      name: "new", modelName: "example/model", flavorName: "base",
      gpuType: "H100", region: "eu-north1", gpuCount: 2,
      scaling: .init(minReplicas: 1, maxReplicas: 3))
    try check(create.isSupported(by: templates), "Decode nested templates and allowed combinations")
    try check(!create.isSupported(by: []), "Absent templates are not deployable")
    state.respond("{\"endpoint\":\(endpointJSON)}", status: 201)
    _ = try await client.createDedicatedEndpoint(create)
    let body = try JSONSerialization.jsonObject(with: state.requests.last!.1!) as! [String: Any]
    try check(
      body["model_name"] as? String == "example/model" && body["gpu_count"] as? Int == 2,
      "Encode POST fields")
    try check(
      (body["scaling"] as? [String: Int]) == ["min_replicas": 1, "max_replicas": 3],
      "Encode scaling")
    state.respond(endpointJSON)
    _ = try await client.updateDedicatedEndpoint(
      id: endpointID, request: .init(scaling: .init(minReplicas: 1, maxReplicas: 2)))
    let patch = try JSONSerialization.jsonObject(with: state.requests.last!.1!) as! [String: Any]
    try check(Set(patch.keys) == ["scaling"], "Omit all nil PATCH fields")
    for enabled in [false, true] {
      _ = try await client.updateDedicatedEndpoint(id: endpointID, request: .init(enabled: enabled))
      let toggle =
        try JSONSerialization.jsonObject(with: state.requests.last!.1!) as! [String: Bool]
      try check(toggle == ["enabled": enabled], "Enable and disable send explicit booleans")
    }
    state.respond("{}")
    try await client.deleteDedicatedEndpoint(id: endpointID)
    state.respond("", status: 204)
    try await client.deleteDedicatedEndpoint(id: endpointID)
    let calls = state.requests.map(\.0)
    try check(calls.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData }, "Never reuse cached project data or deployment templates")
    try check(
      calls.map(\.httpMethod) == [
        "GET", "GET", "POST", "PATCH", "PATCH", "PATCH", "DELETE", "DELETE",
      ], "Lifecycle methods")
    try check(calls[1].url!.path == "/v0/dedicated_endpoints/templates", "Template route")
    try check(calls[3].url!.path == "/v0/dedicated_endpoints/\(endpointID)", "Mutation route")
    try check(
      calls.allSatisfy {
        $0.url!.host == "api.tokenfactory.nebius.com" && $0.url!.scheme == "https"
          && $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-direct-key"
      }, "Use only fixed official host and direct key")

    for code in [401, 403, 404, 422, 429, 500] {
      state.respond(
        #"{"detail":[{"loc":["body","scaling"],"msg":"invalid","type":"value_error"}]}"#,
        status: code)
      do {
        _ = try await client.listDedicatedEndpoints()
        try check(false, "HTTP error expected")
      } catch DedicatedEndpointAPIError.httpError(let status, let detail) {
        try check(status == code && detail != nil, "Retain structured validation errors")
      }
    }
    state.respond("not JSON")
    do {
      _ = try await client.listDedicatedEndpointTemplates()
      try check(false, "Reject malformed response")
    } catch DedicatedEndpointAPIError.invalidResponse {}

    let before = state.requests.count
    for url in [NebiusClient.defaultBaseURL, URL(string: "https://proxy.example/v1")!] {
      let unauthorized = try NebiusClient(
        baseURL: url, headers: ["Authorization": "Bearer proxy-token"],
        sessionConfiguration: configuration)
      do {
        _ = try await unauthorized.listDedicatedEndpoints()
        try check(false, "Headers are not explicit direct-key authority")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
      do {
        _ = try await unauthorized.listDedicatedEndpointTemplates()
        try check(false, "Block proxy templates")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
      do {
        _ = try await unauthorized.createDedicatedEndpoint(create)
        try check(false, "Block proxy creation")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
      do {
        _ = try await unauthorized.updateDedicatedEndpoint(
          id: endpointID, request: .init(enabled: false))
        try check(false, "Block proxy update")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
      do {
        try await unauthorized.deleteDedicatedEndpoint(id: endpointID)
        try check(false, "Block proxy deletion")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
    }
    for key in ["", " \n", "bad key", "key\r\nInjected:header"] {
      do {
        _ = try NebiusClient(directAPIKey: key)
        try check(false, "Reject malformed keys")
      } catch DedicatedEndpointAPIError.directAPIKeyRequired {}
    }
    do {
      try await client.deleteDedicatedEndpoint(id: "../templates")
      try check(false, "Reject path injection")
    } catch DedicatedEndpointAPIError.invalidRequest {}
    do {
      _ = try await client.updateDedicatedEndpoint(id: endpointID, request: .init())
      try check(false, "Reject empty patch")
    } catch DedicatedEndpointAPIError.invalidRequest {}
    var invalid = create
    invalid.scaling = .init(minReplicas: 0, maxReplicas: 2)
    do {
      _ = try await client.createDedicatedEndpoint(invalid)
      try check(false, "Reject invalid scaling")
    } catch DedicatedEndpointAPIError.invalidRequest {}
    try check(state.requests.count == before, "Invalid requests never reach transport")
    print(
      "DedicatedEndpointAPITests: mocked lifecycle, templates, validation, errors, fixed host and direct-key isolation passed"
    )
  }
}
