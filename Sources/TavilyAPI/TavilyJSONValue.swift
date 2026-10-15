// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A Sendable representation of arbitrary JSON, including structured
/// Tavily Research output.
public enum TavilyJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([TavilyJSONValue])
  case object([String: TavilyJSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([TavilyJSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: TavilyJSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Value is not valid JSON"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public var jsonString: String {
    guard let data = try? JSONEncoder().encode(self) else { return "null" }
    return String(decoding: data, as: UTF8.self)
  }
}
