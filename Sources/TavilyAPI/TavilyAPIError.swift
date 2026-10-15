// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TavilyAPIError: LocalizedError, Sendable {
  case missingCredential
  case invalidBaseURL(URL)
  case invalidRequest(String)
  case invalidResponse(String)
  case httpError(statusCode: Int, message: String?, requestID: String?)
  case researchFailed(requestID: String)
  case researchTimedOut(requestID: String)

  public var errorDescription: String? {
    switch self {
    case .missingCredential:
      "The Tavily API key is empty. Use a development key or configure a production proxy."
    case .invalidBaseURL(let url):
      "The Tavily base URL is invalid or is not HTTPS: \(url.absoluteString)"
    case .invalidRequest(let message):
      "Invalid Tavily request: \(message)"
    case .invalidResponse(let message):
      "Invalid Tavily response: \(message)"
    case .httpError(let statusCode, let message, let requestID):
      ["Tavily HTTP \(statusCode)", message, requestID.map { "request_id=\($0)" }]
        .compactMap { $0 }
        .joined(separator: ": ")
    case .researchFailed(let requestID):
      "Tavily research task failed: \(requestID)"
    case .researchTimedOut(let requestID):
      "Tavily research task timed out: \(requestID)"
    }
  }
}

struct TavilyErrorEnvelope: Decodable {
  let detail: Detail?
  let requestID: String?

  enum CodingKeys: String, CodingKey {
    case detail
    case requestID = "request_id"
  }

  enum Detail: Decodable {
    case string(String)
    case object(String)

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let value = try? container.decode(String.self) {
        self = .string(value)
      } else {
        let object = try container.decode([String: String].self)
        self = .object(object["error"] ?? object.description)
      }
    }

    var message: String {
      switch self {
      case .string(let value), .object(let value): value
      }
    }
  }
}
