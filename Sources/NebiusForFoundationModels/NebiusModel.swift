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

  /// Prefer a typed model constant or a catalog entry for public models.
  /// This initializer remains functional for source compatibility.
  @available(
    *, deprecated,
    message: "Prefer typed model constants (for example .kimiK31Pro) or a catalog entry's .languageModel. For custom or dedicated models, use NebiusModel.custom(id:fastVariantID:capabilities:)."
  )
  public init(
    id: String,
    fastVariantID: String? = nil,
    capabilities: Capabilities = .fullText
  ) {
    self.init(modelID: id, fastVariantID: fastVariantID, capabilities: capabilities)
  }

  /// Explicitly configures a private, fine-tuned, dedicated, or uncatalogued model.
  /// Supply its actual capabilities; they are not inferred from the ID.
  public static func custom(
    id: String,
    fastVariantID: String? = nil,
    capabilities: Capabilities
  ) -> NebiusModel {
    NebiusModel(modelID: id, fastVariantID: fastVariantID, capabilities: capabilities)
  }

  // Catalog entries and generated constants already resolve metadata internally.
  init(
    modelID: String,
    fastVariantID: String? = nil,
    capabilities: Capabilities
  ) {
    precondition(!modelID.isEmpty, "A Nebius model ID cannot be empty")
    self.id = modelID
    self.fastVariantID = fastVariantID
    self.capabilities = capabilities
  }
}

// Public model aliases and their deprecation annotations are generated alongside
// NebiusModelCatalog. Use .custom(id:fastVariantID:capabilities:) for custom IDs.
