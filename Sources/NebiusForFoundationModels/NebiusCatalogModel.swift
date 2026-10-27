// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Metadata for one model flavor in a dated Token Factory catalog snapshot.
public struct NebiusCatalogModel: Hashable, Sendable, Identifiable {
  public enum Modality: String, Hashable, Sendable {
    case textToText = "text2text"
    case imageToText = "image2text"
    case embedding
  }

  /// A use case advertised by Token Factory. Raw values preserve the API spelling.
  public enum UseCase: String, Codable, CaseIterable, Hashable, Sendable {
    case classification
    case clustering
    case code
    case complexWriting = "complex_writing"
    case contextAndRAG = "context_and_rag"
    case dedicatedEndpoint = "dedicated-endpoint"
    case fineTune = "fine_tune"
    case functionCalling = "function_calling"
    case image
    case multilabelClassification = "multilabel classification"
    case multilingual
    case pairClassification = "pair classification"
    case reasoning
    case reranking
    case responsesAPI = "responses_api"
    case retrieval
    case summarization
    case text
    case video
  }

  /// A deployment region advertised in the public model catalog.
  public enum Region: String, Codable, CaseIterable, Hashable, Sendable {
    case euNorth1 = "eu-north1"
    case euWest2 = "eu-west2"
    case ukSouth1 = "uk-south1"
    case usCentral1 = "us-central1"
    case usNorth1 = "us-north1"
  }

  public let id: String
  public let name: String
  public let vendor: String
  public let modality: Modality
  public let description: String
  public let contextWindow: Int
  public let inputPricePerMillionTokens: Double
  public let outputPricePerMillionTokens: Double
  public let tokensPerSecond: Double?
  public let quantization: String?
  public let tags: [String]
  public let useCases: [UseCase]
  /// Provider values, including newer use cases not represented by `UseCase`.
  public let rawUseCases: [String]
  public let regions: [Region]
  public let capabilities: NebiusModel.Capabilities

  public init(
    id: String,
    name: String,
    vendor: String,
    modality: Modality,
    description: String,
    contextWindow: Int,
    inputPricePerMillionTokens: Double,
    outputPricePerMillionTokens: Double,
    tokensPerSecond: Double?,
    quantization: String?,
    tags: [String],
    useCases: [UseCase],
    regions: [Region],
    capabilities: NebiusModel.Capabilities
  ) {
    self.init(
      id: id, name: name, vendor: vendor, modality: modality,
      description: description, contextWindow: contextWindow,
      inputPricePerMillionTokens: inputPricePerMillionTokens,
      outputPricePerMillionTokens: outputPricePerMillionTokens,
      tokensPerSecond: tokensPerSecond, quantization: quantization,
      tags: tags, rawUseCases: useCases.map(\.rawValue),
      regions: regions, capabilities: capabilities
    )
  }

  /// Preserves provider metadata while exposing recognized values through `useCases`.
  public init(
    id: String,
    name: String,
    vendor: String,
    modality: Modality,
    description: String,
    contextWindow: Int,
    inputPricePerMillionTokens: Double,
    outputPricePerMillionTokens: Double,
    tokensPerSecond: Double?,
    quantization: String?,
    tags: [String],
    rawUseCases: [String],
    regions: [Region],
    capabilities: NebiusModel.Capabilities
  ) {
    self.id = id
    self.name = name
    self.vendor = vendor
    self.modality = modality
    self.description = description
    self.contextWindow = contextWindow
    self.inputPricePerMillionTokens = inputPricePerMillionTokens
    self.outputPricePerMillionTokens = outputPricePerMillionTokens
    self.tokensPerSecond = tokensPerSecond
    self.quantization = quantization
    self.tags = tags
    self.useCases = rawUseCases.compactMap(UseCase.init(rawValue:))
    self.rawUseCases = rawUseCases
    self.regions = regions
    self.capabilities = capabilities
  }

  /// A Foundation Models configuration when this entry supports generation.
  /// Embedding-only entries intentionally return `nil`.
  public var languageModel: NebiusModel? {
    guard modality != .embedding else { return nil }
    return NebiusModel(id: id, capabilities: capabilities)
  }

  public var supportsFineTuning: Bool {
    useCases.contains(.fineTune)
  }

  public var supportsResponsesAPI: Bool {
    useCases.contains(.responsesAPI)
  }
}
