// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

#if compiler(>=6.4)
  import Foundation
  import FoundationModels
  import NebiusAPI
  @testable import NebiusForFoundationModels
  import Testing

  @Suite struct StreamingUsageTests {
    @Test func arrayCountGuidesReachTheWireSchema() throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let schema = try GenerationSchema(
        root: DynamicGenerationSchema(
          name: "Card",
          properties: [
            .init(
              name: "senses",
              schema: .init(
                arrayOf: .init(type: String.self),
                minimumElements: 1, maximumElements: 3))
          ]), dependencies: [])
      let model = NebiusLanguageModel(
        name: .init(id: "fixture", capabilities: [.structuredOutput]),
        auth: .proxied(headers: [:]))
      let executor = try NebiusExecutor(configuration: model.executorConfiguration)
      let encoded = try executor.schemaJSON(schema)
      guard case .object(let root) = encoded,
        case .object(let properties) = root["properties"],
        case .object(let senses) = properties["senses"]
      else {
        Issue.record("Missing senses schema")
        return
      }
      #expect(senses["minItems"] == .number(1))
      #expect(senses["maxItems"] == .number(3))
    }
    @Test func lateCachedTokensDoNotCrashDuringStreaming() async throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let session = LanguageModelSession(model: FixtureModel(executorConfiguration: .cached))
      var sawPartialAnswer = false
      var answer = ""
      for try await snapshot in session.streamResponse(to: "Test") {
        answer = snapshot.content
        if answer == "Hello world" { sawPartialAnswer = true }
      }
      #expect(sawPartialAnswer)
      #expect(answer == "Hello world!")
      #expect(session.usage.input.totalTokenCount == 4352)
      #expect(session.usage.input.cachedTokenCount == 4352)
      #expect(session.usage.output.totalTokenCount == 4)
    }

    @Test func streamWithoutUsageStillCompletes() async throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let session = LanguageModelSession(model: FixtureModel(executorConfiguration: .noUsage))
      let response = try await session.respond(to: "Test")
      #expect(response.content == "Hello world!")
      #expect(response.usage.input.totalTokenCount == 0)
    }

    @Test func reasoningUsageIsNotDoubleCounted() async throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let session = LanguageModelSession(model: FixtureModel(executorConfiguration: .reasoning))
      let response = try await session.respond(to: "Test")
      #expect(response.content == "Hello world!")
      #expect(response.usage.output.totalTokenCount == 4)
      #expect(response.usage.output.reasoningTokenCount == 2)
    }

    @Test func toolRoundUsageAndFinalResponseArePreserved() async throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let session = LanguageModelSession(
        model: FixtureModel(executorConfiguration: .tools), tools: [FixtureTool()])
      let response = try await session.respond(to: "Test")
      #expect(response.content == "Hello world!")
      #expect(response.usage.input.totalTokenCount == 4352)
      #expect(response.usage.input.cachedTokenCount == 4352)
      #expect(response.usage.output.totalTokenCount == 4)
      let calls = session.transcript.filter { if case .toolCalls = $0 { true } else { false } }
      #expect(calls.count == 1)
    }

    @Test(arguments: [Fixture.invalidCache, .negativeInput, .invalidReasoning])
    func malformedUsageThrowsInsteadOfTrapping(_ fixture: Fixture) async {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let session = LanguageModelSession(model: FixtureModel(executorConfiguration: fixture))
      do {
        _ = try await session.respond(to: "Test")
        Issue.record("Malformed usage should fail as a recoverable error")
      } catch {
        // Apple may wrap executor errors; reaching this catch proves no process trap.
        #expect(
          String(describing: error).contains("inconsistent token usage")
            || String(describing: error).contains("invalidUsage"))
      }
    }

    @Test func cancellationPropagates() async throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let task = Task {
        let session = LanguageModelSession(model: FixtureModel(executorConfiguration: .cached))
        for try await _ in session.streamResponse(to: "Test") { try Task.checkCancellation() }
        try Task.checkCancellation()
      }
      try await Task.sleep(for: .milliseconds(100))
      task.cancel()
      do {
        try await task.value
        Issue.record("Cancellation should stop the stream")
      } catch {}
    }
  }

  enum Fixture: String, Hashable, Sendable {
    case cached, noUsage, reasoning, tools, invalidCache, negativeInput, invalidReasoning
  }

  @available(macOS 27.0, iOS 27.0, *)
  private struct FixtureModel: LanguageModel {
    typealias Executor = FixtureExecutor
    let executorConfiguration: Fixture
    var capabilities: LanguageModelCapabilities { .init([.reasoning, .toolCalling]) }
  }

  @available(macOS 27.0, iOS 27.0, *)
  private struct FixtureExecutor: LanguageModelExecutor {
    typealias Model = FixtureModel
    let configuration: Fixture
    init(configuration: Fixture) { self.configuration = configuration }

    func respond(
      to request: LanguageModelExecutorGenerationRequest, model: FixtureModel,
      streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
      let isToolRound =
        configuration == .tools
        && !request.transcript.contains {
          if case .toolOutput = $0 { true } else { false }
        }
      let stream = AsyncThrowingStream<ChatCompletionChunk, Error> { continuation in
        let task = Task {
          do {
            func emit(_ json: String) throws {
              continuation.yield(
                try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8)))
            }
            if configuration == .reasoning {
              try emit(#"{"choices":[{"delta":{"reasoning_content":"Let me think"}}]}"#)
            }
            if isToolRound {
              try emit(
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call1","function":{"name":"fixtureTool","arguments":"{}"}}]}}]}"#
              )
            } else {
              try emit(#"{"choices":[{"delta":{"content":"Hello"}}]}"#)
            }
            if configuration != .noUsage {
              try emit(#"{"choices":[],"usage":{"prompt_tokens":4352,"completion_tokens":1}}"#)
            }
            if !isToolRound { try emit(#"{"choices":[{"delta":{"content":" world"}}]}"#) }
            // Ensure Apple delivers the earlier snapshot before cache accounting arrives.
            // The old adapter traps at FoundationModels + 921188 with x8=0, x9=4352.
            try await Task.sleep(for: .milliseconds(500))
            if configuration != .noUsage {
              let input = configuration == .negativeInput ? -1 : 4352
              let cached = configuration == .invalidCache ? 5000 : (isToolRound ? 0 : 4352)
              let reasoning =
                configuration == .invalidReasoning ? 5 : (configuration == .reasoning ? 2 : 0)
              try emit(
                """
                {"choices":[],"usage":{"prompt_tokens":\(input),"completion_tokens":4,"prompt_tokens_details":{"cached_tokens":\(cached)},"completion_tokens_details":{"reasoning_tokens":\(reasoning)}}}
                """)
            }
            if !isToolRound { try emit(#"{"choices":[{"delta":{"content":"!"}}]}"#) }
            continuation.finish()
          } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
      }
      try await NebiusExecutor.process(
        stream, into: channel, requestID: UUID(), modelID: "fixture", observer: nil)
    }
  }

  @available(macOS 27.0, iOS 27.0, *)
  private struct FixtureTool: Tool {
    let name = "fixtureTool"
    let description = "A local test fixture"
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String { "Done" }
  }
#endif
