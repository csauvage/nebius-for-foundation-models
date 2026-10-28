// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A Token Factory model and the features the adapter may request from it.
public struct NebiusModel: Hashable, Sendable {
  public struct Capabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    public static let vision = Capabilities(rawValue: 1 << 0)
    public static let toolCalling = Capabilities(rawValue: 1 << 1)
    public static let reasoning = Capabilities(rawValue: 1 << 2)
    public static let structuredOutput = Capabilities(rawValue: 1 << 3)

    /// A useful default for modern text models with tool use, reasoning and
    /// JSON-schema output, but no image input.
    public static let fullText: Capabilities = [.toolCalling, .reasoning, .structuredOutput]
  }

  /// The normal model ID sent to Token Factory.
  public let id: String

  /// Optional low-latency variant selected for Apple's `.light` reasoning
  /// level. All other levels use ``id``.
  public let fastVariantID: String?

  public let capabilities: Capabilities

  public init(
    id: String,
    fastVariantID: String? = nil,
    capabilities: Capabilities = .fullText
  ) {
    precondition(!id.isEmpty, "A Nebius model ID cannot be empty")
    self.id = id
    self.fastVariantID = fastVariantID
    self.capabilities = capabilities
  }
}

// Convenient aliases for commonly used entries. See `NebiusModelCatalog` for
// the complete, dated public catalog, or use `NebiusModel(id:capabilities:)`
// for private checkpoints and dedicated endpoints.
extension NebiusModel {
  public static let nemotron35Lightning = NebiusModel(
    id: "nvidia/Nemotron-3_5-Lightning"
  )

  public static let minimaxM3 = NebiusModel(
    id: "MiniMaxAI/MiniMax-M3"
  )

  public static let minimaxM31Flash = NebiusModel(
    id: "MiniMaxAI/MiniMax-M3.1-Flash",
    capabilities: [.vision, .toolCalling, .reasoning]
  )

  public static let deepSeekV41Flash1017 = NebiusModel(
    id: "deepseek-ai/DeepSeek-V4.1-Flash-1017",
    capabilities: [.vision, .toolCalling, .reasoning]
  )

  public static let museSparkOpen = NebiusModel(
    id: "meta-models/muse-spark-open",
    capabilities: [.vision, .toolCalling, .reasoning]
  )

  public static let nemotron35SuperVL = NebiusModel(
    id: "nvidia/Nemotron-3.5-Super-VL",
    capabilities: [.vision, .toolCalling, .reasoning]
  )

  public static let reflectionBeam = NebiusModel(
    id: "reflection/beam",
    capabilities: [.toolCalling, .reasoning]
  )

  public static let qwen35Large = NebiusModel(
    id: "Qwen/Qwen3.5-397B-A17B"
  )

  public static let gptOSS120B = NebiusModel(
    id: "openai/gpt-oss-120b"
  )

  public static let deepSeekV4Flash0731 = NebiusModel(
    id: "deepseek-ai/DeepSeek-V4-Flash-0731"
  )
}
