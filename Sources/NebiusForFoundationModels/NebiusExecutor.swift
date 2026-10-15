// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

#if compiler(>=6.4)
  import Foundation
  import FoundationModels
  import NebiusAPI

  #if canImport(CoreImage)
    import CoreImage
    import UniformTypeIdentifiers
  #endif

  @available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
  public struct NebiusExecutor: LanguageModelExecutor {
    public typealias Model = NebiusLanguageModel

    public struct Configuration: Hashable, Sendable {
      public let model: NebiusModel
      public let baseURL: URL
      public let chatCompletionsPath: String?
      public let auth: NebiusAuth
      public let fixedReasoningEffort: ReasoningEffort?
      public let serviceTier: ServiceTier
      public let timeout: TimeInterval
      public let usageObserver: NebiusUsageObserver?

      public init(
        model: NebiusModel,
        baseURL: URL,
        chatCompletionsPath: String? = nil,
        auth: NebiusAuth,
        fixedReasoningEffort: ReasoningEffort?,
        serviceTier: ServiceTier,
        timeout: TimeInterval,
        usageObserver: NebiusUsageObserver? = nil
      ) {
        self.model = model
        self.baseURL = baseURL
        self.chatCompletionsPath = chatCompletionsPath
        self.auth = auth
        self.fixedReasoningEffort = fixedReasoningEffort
        self.serviceTier = serviceTier
        self.timeout = timeout
        self.usageObserver = usageObserver
      }
    }

    private let configuration: Configuration
    private let client: NebiusClient

    public init(configuration: Configuration) throws {
      self.configuration = configuration

      let headers: [String: String]
      switch configuration.auth {
      case .apiKey(let key):
        guard !key.isEmpty else { throw NebiusError.missingCredential }
        headers = ["Authorization": "Bearer \(key)"]
      case .proxied(let proxyHeaders):
        headers = proxyHeaders
      }

      let session = URLSessionConfiguration.ephemeral
      session.timeoutIntervalForRequest = configuration.timeout
      session.timeoutIntervalForResource = configuration.timeout
      self.client = try NebiusClient(
        baseURL: configuration.baseURL,
        chatCompletionsPath: configuration.chatCompletionsPath,
        headers: headers,
        sessionConfiguration: session
      )
    }

    public func respond(
      to request: LanguageModelExecutorGenerationRequest,
      model: NebiusLanguageModel,
      streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
      let effort = resolvedEffort(for: request)
      let tools = try request.enabledToolDefinitions.map { definition in
        ChatTool(
          name: definition.name,
          description: definition.description,
          parameters: try schemaJSON(definition.parameters)
        )
      }
      let wireRequest = ChatCompletionRequest(
        model: resolvedModelID(for: request, effort: effort),
        messages: try convertedTranscript(request.transcript),
        store: false,
        temperature: request.generationOptions.temperature,
        topP: try request.generationOptions.samplingMode.map(topP),
        maxCompletionTokens: request.generationOptions.maximumResponseTokens,
        tools: tools.isEmpty ? nil : tools,
        toolChoice: tools.isEmpty
          ? nil : toolChoice(for: request.generationOptions.toolCallingMode),
        reasoningEffort: effort,
        responseFormat: try request.schema.map { schema in
          ResponseFormat(name: schema.name, schema: try schemaJSON(schema))
        },
        serviceTier: configuration.serviceTier
      )

      let requestID = UUID()
      await configuration.usageObserver?.report(
        .init(requestID: requestID, modelID: wireRequest.model))
      try await Self.process(
        client.stream(wireRequest), into: channel,
        requestID: requestID, modelID: wireRequest.model,
        observer: configuration.usageObserver)
    }

    static func process<S: AsyncSequence>(
      _ chunks: S,
      into channel: LanguageModelExecutorGenerationChannel,
      requestID: UUID, modelID: String, observer: NebiusUsageObserver?
    ) async throws where S.Element == ChatCompletionChunk {
      var toolRouting: [Int: (id: String, name: String)] = [:]
      let responseID = UUID().uuidString
      let reasoningID = UUID().uuidString
      let toolCallsID = UUID().uuidString
      var finalUsage: ChatCompletionChunk.Usage?
      var hasResponse = false
      var hasReasoning = false
      var hasToolCalls = false

      for try await chunk in chunks {
        try Task.checkCancellation()
        if let delta = chunk.choices.first?.delta {
          if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
            hasReasoning = true
            await channel.send(
              .reasoning(entryID: reasoningID, action: .appendText(reasoning, tokenCount: 1))
            )
          }

          if let calls = delta.toolCalls, !calls.isEmpty {
            for call in calls {
              let previous = toolRouting[call.index] ?? (id: "", name: "")
              let route = (
                id: previous.id + (call.id ?? ""),
                name: previous.name + (call.function?.name ?? "")
              )
              toolRouting[call.index] = route
              guard !route.id.isEmpty, !route.name.isEmpty else { continue }

              hasToolCalls = true
              await channel.send(
                .toolCalls(
                  entryID: toolCallsID,
                  action: .toolCall(
                    id: route.id,
                    name: route.name,
                    action: .appendArguments(
                      call.function?.arguments ?? "",
                      tokenCount: 1
                    )
                  )
                )
              )
            }
          } else if let content = delta.content, !content.isEmpty {
            hasResponse = true
            await channel.send(
              .response(entryID: responseID, action: .appendText(content, tokenCount: 1))
            )
          }
        }

        if let usage = chunk.usage {
          try validateUsage(usage)
          finalUsage = usage
          await observer?.report(
            .init(
              requestID: requestID, modelID: modelID,
              inputTokens: usage.promptTokens, outputTokens: usage.completionTokens,
              cachedInputTokens: usage.promptTokensDetails?.cachedTokens ?? 0))
        }
      }

      try Task.checkCancellation()
      // Provider usage snapshots are cumulative and may revise cached tokens late.
      // Foundation Models 27 computes deltas between delivered snapshots and traps
      // if the cached-input delta exceeds the total-input delta. Publish the final
      // accounting once, while the observer still receives live provider usage.
      guard let usage = finalUsage else { return }
      let input = LanguageModelExecutorGenerationChannel.Usage.Input(
        totalTokenCount: usage.promptTokens,
        cachedTokenCount: usage.promptTokensDetails?.cachedTokens ?? 0)
      let output = LanguageModelExecutorGenerationChannel.Usage.Output(
        totalTokenCount: usage.completionTokens,
        reasoningTokenCount: usage.completionTokensDetails?.reasoningTokens ?? 0)
      // Keep tool-only rounds tool-only, without manufacturing an empty response.
      if hasToolCalls {
        await channel.send(
          .toolCalls(
            entryID: toolCallsID, action: .updateUsage(input: input, output: output)))
      } else if hasResponse {
        await channel.send(
          .response(
            entryID: responseID, action: .updateUsage(input: input, output: output)))
      } else if hasReasoning {
        await channel.send(
          .reasoning(
            entryID: reasoningID, action: .updateUsage(input: input, output: output)))
      }
    }

    private static func validateUsage(_ usage: ChatCompletionChunk.Usage) throws {
      let cached = usage.promptTokensDetails?.cachedTokens ?? 0
      let reasoning = usage.completionTokensDetails?.reasoningTokens ?? 0
      guard usage.promptTokens >= 0, usage.completionTokens >= 0,
        cached >= 0, cached <= usage.promptTokens,
        reasoning >= 0, reasoning <= usage.completionTokens
      else { throw NebiusError.invalidUsage }
    }

    private func resolvedModelID(
      for request: LanguageModelExecutorGenerationRequest,
      effort: ReasoningEffort?
    ) -> String {
      guard let fast = configuration.model.fastVariantID else {
        return configuration.model.id
      }
      if effort == .minimal || effort == .low { return fast }
      if case .light = request.contextOptions.reasoningLevel { return fast }
      return configuration.model.id
    }

    private func resolvedEffort(
      for request: LanguageModelExecutorGenerationRequest
    ) -> ReasoningEffort? {
      guard configuration.model.capabilities.contains(.reasoning) else { return nil }
      if let fixed = configuration.fixedReasoningEffort { return fixed }

      switch request.contextOptions.reasoningLevel {
      case .none: return nil
      case .light: return .low
      case .moderate: return .medium
      case .deep: return .high
      case .custom(let value): return ReasoningEffort(rawValue: value)
      @unknown default: return nil
      }
    }

    private func toolChoice(
      for mode: GenerationOptions.ToolCallingMode?
    ) -> ToolChoice? {
      switch mode?.kind {
      case .required: .required
      case .disallowed: ToolChoice.none
      case .allowed, .none: nil
      @unknown default: nil
      }
    }

    private func topP(_ mode: GenerationOptions.SamplingMode) throws -> Double {
      switch mode.kind {
      case .greedy:
        return 0
      case .randomProbabilityThreshold(let threshold, let seed):
        guard seed == nil else {
          throw NebiusError.unsupportedSamplingMode("random seeds")
        }
        return threshold
      case .randomTopK:
        throw NebiusError.unsupportedSamplingMode("top-k")
      @unknown default:
        throw NebiusError.unsupportedSamplingMode(String(describing: mode.kind))
      }
    }

    func schemaJSON(_ schema: GenerationSchema) throws -> JSONValue {
      sanitizeSchema(try JSONValue.encode(schema))
    }

    private func sanitizeSchema(_ value: JSONValue) -> JSONValue {
      let allowed: Set<String> = [
        "$defs", "$ref", "additionalProperties", "allOf", "anyOf", "const",
        "definitions", "description", "enum", "format", "items", "oneOf",
        "properties", "required", "type", "minItems", "maxItems",
      ]
      let maps: Set<String> = ["$defs", "definitions", "properties"]

      switch value {
      case .object(let object):
        var result: [String: JSONValue] = [:]
        for (key, nested) in object where allowed.contains(key) {
          if maps.contains(key), case .object(let entries) = nested {
            result[key] = .object(entries.mapValues(sanitizeSchema))
          } else {
            result[key] = sanitizeSchema(nested)
          }
        }
        if result["type"] == .string("object"), result["additionalProperties"] == nil {
          result["additionalProperties"] = .bool(false)
        }
        return .object(result)
      case .array(let values):
        return .array(values.map(sanitizeSchema))
      default:
        return value
      }
    }

    private func convertedTranscript(
      _ entries: some Collection<Transcript.Entry>
    ) throws -> [ChatMessage] {
      var messages: [ChatMessage] = []
      var pendingReasoning: String?

      func consumeReasoning() -> String? {
        defer { pendingReasoning = nil }
        return pendingReasoning
      }

      for entry in entries {
        switch entry {
        case .instructions(let instructions):
          messages.append(
            ChatMessage(
              role: .system,
              content: try messageContent(instructions.segments, entry: entry)
            )
          )
        case .prompt(let prompt):
          if let reasoning = consumeReasoning() {
            messages.append(ChatMessage(role: .assistant, reasoningContent: reasoning))
          }
          messages.append(
            ChatMessage(
              role: .user,
              content: try messageContent(prompt.segments, entry: entry)
            )
          )
        case .toolCalls(let calls):
          messages.append(
            ChatMessage(
              role: .assistant,
              toolCalls: calls.map {
                ToolCall(id: $0.id, name: $0.toolName, arguments: $0.arguments.jsonString)
              },
              reasoningContent: consumeReasoning()
            )
          )
        case .toolOutput(let output):
          messages.append(
            ChatMessage(
              role: .tool,
              content: try messageContent(output.segments, entry: entry),
              toolCallID: output.id
            )
          )
        case .response(let response):
          messages.append(
            ChatMessage(
              role: .assistant,
              content: try messageContent(response.segments, entry: entry),
              reasoningContent: consumeReasoning()
            )
          )
        case .reasoning(let reasoning):
          let text = reasoning.segments.compactMap { segment -> String? in
            guard case .text(let text) = segment else { return nil }
            return text.content
          }.joined()
          pendingReasoning = (pendingReasoning ?? "") + text
        @unknown default:
          continue
        }
      }

      if let reasoning = consumeReasoning() {
        messages.append(ChatMessage(role: .assistant, reasoningContent: reasoning))
      }
      return messages
    }

    private func messageContent(
      _ segments: some Collection<Transcript.Segment>,
      entry: Transcript.Entry
    ) throws -> ChatMessage.Content? {
      var parts: [ContentPart] = []
      for segment in segments {
        switch segment {
        case .text(let text):
          parts.append(ContentPart(text: text.content))
        case .structure(let structure):
          parts.append(ContentPart(text: structure.content.jsonString))
        case .attachment(let attachment):
          switch attachment.content {
          case .image(let image):
            #if canImport(CoreImage)
              let data = image.cgImage.nebiusJPEGData()
              let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")!
              parts.append(ContentPart(imageURL: .init(url: url)))
            #else
              guard let url = image.url else {
                throw LanguageModelError.unsupportedTranscriptContent(
                  .init(
                    unsupportedContent: [entry],
                    debugDescription: "An image without a URL is unsupported on this platform."
                  )
                )
              }
              parts.append(ContentPart(imageURL: .init(url: url)))
            #endif
          @unknown default:
            throw LanguageModelError.unsupportedTranscriptContent(
              .init(
                unsupportedContent: [entry],
                debugDescription: "This attachment type is not supported by Token Factory."
              )
            )
          }
        @unknown default:
          throw LanguageModelError.unsupportedTranscriptContent(
            .init(
              unsupportedContent: [entry],
              debugDescription: "This transcript segment is not supported by Token Factory."
            )
          )
        }
      }

      if parts.count == 1, parts[0].type == .text, let text = parts[0].text {
        return .text(text)
      }
      return parts.isEmpty ? nil : .parts(parts)
    }
  }

  #if canImport(CoreImage)
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
    extension CGImage {
      fileprivate func nebiusJPEGData() -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
          data,
          UTType.jpeg.identifier as CFString,
          1,
          nil
        )!
        CGImageDestinationAddImage(destination, self, nil)
        CGImageDestinationFinalize(destination)
        return Data(referencing: data)
      }
    }
  #endif
#endif
