// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One provider request, including intermediate requests made while calling tools.
/// Nil token counts mean the provider has not reported usage; they are never estimates.
public struct NebiusUsageEvent: Sendable {
  public let requestID: UUID
  public let modelID: String
  public let inputTokens: Int?
  public let outputTokens: Int?
  public let cachedInputTokens: Int

  public init(
    requestID: UUID, modelID: String, inputTokens: Int? = nil,
    outputTokens: Int? = nil, cachedInputTokens: Int = 0
  ) {
    self.requestID = requestID
    self.modelID = modelID
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cachedInputTokens = cachedInputTokens
  }
}

/// Identity-based observer keeps executor configurations Hashable while supporting async telemetry.
/// Called before each provider request and when provider-reported usage arrives, including tool rounds.
public struct NebiusUsageObserver: Hashable, Sendable {
  private let id = UUID()
  private let handler: @Sendable (NebiusUsageEvent) async -> Void
  public init(_ handler: @escaping @Sendable (NebiusUsageEvent) async -> Void) {
    self.handler = handler
  }
  public func report(_ event: NebiusUsageEvent) async { await handler(event) }
  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
