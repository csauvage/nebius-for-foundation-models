// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct SSEParser: Sendable {
  private let decoder = JSONDecoder()

  public init() {}

  /// Parses one SSE line. Empty lines, comments, event metadata and `[DONE]`
  /// return `nil`.
  public func parse(_ line: String) throws -> ChatCompletionChunk? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix(":"), trimmed.hasPrefix("data:") else {
      return nil
    }

    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard payload != "[DONE]" else { return nil }
    guard let data = payload.data(using: .utf8) else {
      throw NebiusTransportError.invalidStreamData(line)
    }

    do {
      return try decoder.decode(ChatCompletionChunk.self, from: data)
    } catch {
      if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
        throw envelope.error
      }
      throw NebiusTransportError.invalidStreamData(line)
    }
  }
}
