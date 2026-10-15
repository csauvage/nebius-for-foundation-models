// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct NebiusAPIError: LocalizedError, Decodable, Sendable {
  public var message: String
  public var type: String?
  public var param: String?
  public var code: String?

  public init(message: String, type: String? = nil, param: String? = nil, code: String? = nil) {
    self.message = message
    self.type = type
    self.param = param
    self.code = code
  }

  public var errorDescription: String? { message }
}

public enum NebiusTransportError: LocalizedError, Sendable {
  case invalidBaseURL(URL)
  case invalidStreamData(String)
  case httpError(statusCode: Int, body: Data)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL(let url):
      "The Nebius base URL is invalid or is not HTTPS: \(url.absoluteString)"
    case .invalidStreamData(let line):
      "Invalid server-sent event: \(line)"
    case .httpError(let statusCode, let body):
      "HTTP \(statusCode): \(String(data: body, encoding: .utf8) ?? body.description)"
    }
  }
}

struct ErrorEnvelope: Decodable {
  var error: NebiusAPIError
}
