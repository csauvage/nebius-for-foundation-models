// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension NebiusClient {
  public func listDedicatedEndpoints() async throws -> [DedicatedEndpoint] {
    try await controlPlaneResponse("GET", as: EndpointList<DedicatedEndpoint>.self).data
  }

  public func listDedicatedEndpointTemplates() async throws -> [DedicatedEndpointTemplate] {
    try await controlPlaneResponse(
      "GET", suffix: "templates", as: EndpointList<DedicatedEndpointTemplate>.self
    ).data
  }

  public func createDedicatedEndpoint(_ request: DedicatedEndpointCreateRequest) async throws
    -> DedicatedEndpoint
  {
    guard validEndpointName(request.name), request.description.count <= 500,
      !request.modelName.isEmpty, !request.flavorName.isEmpty, !request.gpuType.isEmpty,
      !request.region.isEmpty, request.gpuCount >= 0, request.scaling.isValid
    else { throw DedicatedEndpointAPIError.invalidRequest }
    return try await controlPlaneResponse(
      "POST", body: encodeControlPlane(request), as: EndpointCreated.self
    ).endpoint
  }

  public func updateDedicatedEndpoint(id: String, request: DedicatedEndpointUpdateRequest)
    async throws -> DedicatedEndpoint
  {
    guard UUID(uuidString: id) != nil,
      request.name.map(validEndpointName) ?? true,
      request.description.map({ $0.count <= 500 }) ?? true,
      request.scaling?.isValid ?? true,
      request.name != nil || request.description != nil || request.enabled != nil
        || request.scaling != nil
    else { throw DedicatedEndpointAPIError.invalidRequest }
    return try await controlPlaneResponse(
      "PATCH", suffix: id, body: encodeControlPlane(request), as: DedicatedEndpoint.self)
  }

  public func deleteDedicatedEndpoint(id: String) async throws {
    guard UUID(uuidString: id) != nil else { throw DedicatedEndpointAPIError.invalidRequest }
    _ = try await controlPlaneData("DELETE", suffix: id)
  }

  private func validEndpointName(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100
  }

  private func encodeControlPlane<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try encoder.encode(value)
  }

  private func controlPlaneResponse<T: Decodable>(
    _ method: String, suffix: String? = nil, body: Data? = nil, as type: T.Type
  ) async throws -> T {
    let data = try await controlPlaneData(method, suffix: suffix, body: body)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do { return try decoder.decode(type, from: data) } catch {
      throw DedicatedEndpointAPIError.invalidResponse
    }
  }

  private func controlPlaneData(_ method: String, suffix: String? = nil, body: Data? = nil)
    async throws -> Data
  {
    guard let directAPIKey else { throw DedicatedEndpointAPIError.directAPIKeyRequired }
    try Task.checkCancellation()
    var url = URL(string: "https://api.tokenfactory.nebius.com/v0/dedicated_endpoints")!
    if let suffix { url.appendPathComponent(suffix) }
    var request = URLRequest(url: url)
    // Template revalidation and manual refresh must reach the control plane.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpMethod = method
    request.timeoutInterval = 60
    request.httpBody = body
    request.setValue("Bearer \(directAPIKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    // Deliberately does not use baseURL or headers: these can contain proxy credentials.
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw DedicatedEndpointAPIError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw DedicatedEndpointAPIError.httpError(
        statusCode: response.statusCode,
        detail: try? JSONDecoder().decode(JSONValue.self, from: data))
    }
    return data
  }
}

private struct EndpointList<T: Decodable>: Decodable { let data: [T] }
private struct EndpointCreated: Decodable { let endpoint: DedicatedEndpoint }
