// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

#if compiler(>=6.4)
  import Foundation
  import FoundationModels
  public import NebiusAPI

  /// A Nebius Token Factory model exposed through Apple's Foundation Models
  /// framework.
  ///
  /// ```swift
  /// let model = NebiusLanguageModel(
  ///   name: .nemotron35Lightning,
  ///   auth: .apiKey(ProcessInfo.processInfo.environment["NEBIUS_API_KEY"] ?? "")
  /// )
  /// let session = LanguageModelSession(model: model)
  /// let response = try await session.respond(to: "Plan a weekend in Amsterdam")
  /// ```
  @available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
  public struct NebiusLanguageModel: Sendable {
    public static let defaultBaseURL = NebiusClient.defaultBaseURL

    public let model: NebiusModel
    public let baseURL: URL
    /// Nil keeps automatic Nebius routing; otherwise append this exact path to baseURL.
    public let chatCompletionsPath: String?
    public let fixedReasoningEffort: ReasoningEffort?
    public let serviceTier: ServiceTier
    public let timeout: TimeInterval
    public let usageObserver: NebiusUsageObserver?
    let auth: NebiusAuth

    public init(
      name: NebiusModel,
      auth: NebiusAuth,
      fixedReasoningEffort: ReasoningEffort? = nil,
      serviceTier: ServiceTier = .auto,
      baseURL: URL = NebiusLanguageModel.defaultBaseURL,
      chatCompletionsPath: String? = nil,
      timeout: TimeInterval = 60,
      usageObserver: NebiusUsageObserver? = nil
    ) {
      if fixedReasoningEffort != nil {
        precondition(
          name.capabilities.contains(.reasoning),
          "A fixed reasoning effort requires a reasoning-capable model"
        )
      }
      precondition(timeout > 0, "Timeout must be greater than zero")
      self.model = name
      self.auth = auth
      self.fixedReasoningEffort = fixedReasoningEffort
      self.serviceTier = serviceTier
      self.baseURL = baseURL
      self.chatCompletionsPath = chatCompletionsPath
      self.timeout = timeout
      self.usageObserver = usageObserver
    }
  }

  @available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
  extension NebiusLanguageModel: LanguageModel {
    public typealias Executor = NebiusExecutor

    public var capabilities: LanguageModelCapabilities {
      var result: [LanguageModelCapabilities.Capability] = []
      if model.capabilities.contains(.vision) { result.append(.vision) }
      if model.capabilities.contains(.toolCalling) { result.append(.toolCalling) }
      if model.capabilities.contains(.reasoning) { result.append(.reasoning) }
      if model.capabilities.contains(.structuredOutput) { result.append(.guidedGeneration) }
      return LanguageModelCapabilities(result)
    }

    public var executorConfiguration: NebiusExecutor.Configuration {
      .init(
        model: model,
        baseURL: baseURL,
        chatCompletionsPath: chatCompletionsPath,
        auth: auth,
        fixedReasoningEffort: fixedReasoningEffort,
        serviceTier: serviceTier,
        timeout: timeout,
        usageObserver: usageObserver
      )
    }
  }
#endif
