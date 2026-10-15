// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation
import NebiusAPI
import NebiusForFoundationModels

private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

@main
struct NebiusAPITests {
  static func main() async throws {
    try await dedicatedEndpointAPITests()
    try endpointURL()
    try customChatRoutes()
    try requestEncoding()
    try sseParsing()
    try sseAPIError()
    try rejectsInsecureEndpoints()
    try catalogSnapshot()
    try catalogMetadata()
    print("NebiusAPITests: 8 tests passed")
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) throws {
    guard condition() else { throw TestFailure(description: message) }
  }

  private static func endpointURL() throws {
    let versioned = try NebiusClient(
      baseURL: URL(string: "https://api.tokenfactory.nebius.com/v1/")!,
      headers: [:]
    )
    try expect(
      versioned.endpointURL.absoluteString
        == "https://api.tokenfactory.nebius.com/v1/chat/completions",
      "Versioned base URL produced the wrong endpoint"
    )

    let proxy = try NebiusClient(
      baseURL: URL(string: "https://example.com/nebius")!,
      headers: [:]
    )
    try expect(
      proxy.endpointURL.absoluteString == "https://example.com/nebius/v1/chat/completions",
      "Unversioned proxy URL produced the wrong endpoint"
    )
  }

  private static func customChatRoutes() throws {
    let cases: [(String, String?, String)] = [
      ("https://relay.example", nil, "https://relay.example/v1/chat/completions"),
      ("https://relay.example/v1", nil, "https://relay.example/v1/chat/completions"),
      (
        "https://relay.example", "/v1/chat/completions", "https://relay.example/v1/chat/completions"
      ),
      (
        "https://relay.example/v1/", "/chat/completions/",
        "https://relay.example/v1/chat/completions"
      ),
      ("https://relay.example/gateway", "messages", "https://relay.example/gateway/messages"),
      (
        "https://relay.example/v1beta/openai", "/chat/completions",
        "https://relay.example/v1beta/openai/chat/completions"
      ),
      ("https://relay.example/v2", "custom/chat", "https://relay.example/v2/custom/chat"),
    ]
    for (base, path, expected) in cases {
      let client = try NebiusClient(
        baseURL: URL(string: base)!, chatCompletionsPath: path,
        headers: ["Authorization": "Bearer route-test"])
      let request = try client.makeURLRequest(.init(model: "private-model", messages: []))
      try expect(request.url?.absoluteString == expected, "Request must use exact resolved route")
      try expect(request.httpMethod == "POST", "Custom route keeps POST semantics")
      try expect(
        request.value(forHTTPHeaderField: "Authorization") == "Bearer route-test",
        "Custom route keeps authentication")
      let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      try expect(
        json["stream"] as? Bool == true && json["model"] as? String == "private-model",
        "Custom routes keep Chat Completions streaming format")
    }
    for invalid in [
      "", "/", "//other.example/chat", "https://other.example/chat", "../chat", "x/./chat",
      "x/../chat", "chat?key=secret", "chat#fragment", "chat%2Fother", "chat\\other",
      "chat completions", "chat\ncompletions",
    ] {
      do {
        _ = try NebiusClient(
          baseURL: URL(string: "https://relay.example")!, chatCompletionsPath: invalid, headers: [:]
        )
        throw TestFailure(description: "Invalid custom route was accepted")
      } catch NebiusChatRouteError.invalidPath {}
    }
    #if compiler(>=6.4)
      if #available(macOS 27.0, iOS 27.0, *) {
        let model = NebiusLanguageModel(
          name: NebiusModel(id: "private/model", capabilities: []),
          auth: .apiKey("test"), baseURL: URL(string: "https://relay.example")!,
          chatCompletionsPath: "gateway/chat")
        try expect(
          model.executorConfiguration.chatCompletionsPath == "gateway/chat",
          "Foundation Models forwards the route to its executor")
        _ = try NebiusExecutor(configuration: model.executorConfiguration)
        let invalid = NebiusLanguageModel(
          name: model.model, auth: .apiKey("test"), chatCompletionsPath: "../chat")
        do {
          _ = try NebiusExecutor(configuration: invalid.executorConfiguration)
          throw TestFailure(
            description: "Executor did not forward the configured route to transport validation")
        } catch NebiusChatRouteError.invalidPath {}
      }
    #endif
  }

  private static func requestEncoding() throws {
    let request = ChatCompletionRequest(
      model: "openai/gpt-oss-120b",
      messages: [ChatMessage(role: .user, content: .text("Hello"))],
      reasoningEffort: .high,
      responseFormat: ResponseFormat(
        name: "answer",
        schema: .object([
          "type": .string("object"),
          "properties": .object(["answer": .object(["type": .string("string")])]),
        ])
      ),
      serviceTier: .flex
    )
    let client = try NebiusClient(headers: ["Authorization": "Bearer test-key"])
    let urlRequest = try client.makeURLRequest(request)
    guard let body = urlRequest.httpBody,
      let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
      throw TestFailure(description: "Request body is missing or invalid")
    }

    try expect(json["model"] as? String == "openai/gpt-oss-120b", "Wrong model")
    try expect(json["store"] as? Bool == false, "store must be false")
    try expect(json["reasoning_effort"] as? String == "high", "Wrong effort")
    try expect(json["service_tier"] as? String == "flex", "Wrong service tier")
    try expect(json["stream"] as? Bool == true, "Streaming must be enabled")
    let streamOptions = json["stream_options"] as? [String: Any]
    try expect(streamOptions?["include_usage"] as? Bool == true, "Usage must be requested")
    let responseFormat = json["response_format"] as? [String: Any]
    try expect(responseFormat?["type"] as? String == "json_schema", "Wrong schema mode")
    try expect(
      urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
      "Authorization header was not forwarded"
    )
  }

  private static func sseParsing() throws {
    let parser = SSEParser()
    let text = try parser.parse(
      #"data: {"id":"1","choices":[{"delta":{"content":"Bonjour"}}]}"#
    )
    try expect(text?.choices.first?.delta.content == "Bonjour", "Text delta was not parsed")

    let reasoning = try parser.parse(
      #"data: {"id":"2","choices":[{"delta":{"reasoning":"Analyse"}}]}"#
    )
    try expect(
      reasoning?.choices.first?.delta.reasoningContent == "Analyse",
      "Reasoning delta was not parsed"
    )

    let usage = try parser.parse(
      #"data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":7}}"#
    )
    try expect(usage?.usage?.promptTokens == 4, "Prompt usage was not parsed")
    try expect(usage?.usage?.completionTokens == 7, "Completion usage was not parsed")
    let done = try parser.parse("data: [DONE]")
    let comment = try parser.parse(": keep-alive")
    try expect(done == nil, "DONE should not emit a chunk")
    try expect(comment == nil, "Comments should not emit a chunk")
  }

  private static func sseAPIError() throws {
    let parser = SSEParser()
    do {
      _ = try parser.parse(
        #"data: {"error":{"message":"Unknown model","type":"invalid_request_error","param":"model","code":"model_not_found"}}"#
      )
      throw TestFailure(description: "Expected an API error")
    } catch let error as NebiusAPIError {
      try expect(error.message == "Unknown model", "API message was lost")
      try expect(error.param == "model", "API parameter was lost")
      try expect(error.code == "model_not_found", "API code was lost")
    }
  }

  private static func rejectsInsecureEndpoints() throws {
    do {
      _ = try NebiusClient(baseURL: URL(string: "http://example.com")!, headers: [:])
      throw TestFailure(description: "An insecure endpoint was accepted")
    } catch is NebiusTransportError {
      return
    }
  }

  private static func catalogSnapshot() throws {
    let expectedIDs = [
      "deepseek-ai/DeepSeek-V4.1-Flash",
      "deepseek-ai/DeepSeek-V4-Flash-0731",
      "deepseek-ai/DeepSeek-V4-Pro",
      "deepseek-ai/DeepSeek-V4-Pro-0813",
      "google/gemma-3-27b-it",
      "MiniMaxAI/MiniMax-M3",
      "moonshotai/Kimi-K2.6",
      "moonshotai/Kimi-K2.7-Code",
      "moonshotai/Kimi-K3",
      "NousResearch/Hermes-4-405B",
      "nvidia/Nemotron-3_5-Lightning",
      "nvidia/nemotron-3-super-120b-a12b",
      "nvidia/Nemotron-3-Ultra-550b-a55b",
      "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B",
      "openai/gpt-oss-120b",
      "openbmb/MiniCPM-V-4_5",
      "Qwen/Qwen3-30B-A3B-Instruct-2507",
      "Qwen/Qwen3-235B-A22B-Instruct-2507",
      "Qwen/Qwen3-Embedding-8B",
      "Qwen/Qwen3.5-397B-A17B",
      "Qwen/Qwen3.8-27B",
      "zai-org/GLM-5.1",
      "zai-org/GLM-5.2",
      "zai-org/GLM-5.3",
      "zai-org/GLM-5.3-Flash",
    ].sorted()

    try expect(NebiusModelCatalog.snapshotDate == "2026-10-15", "Wrong snapshot date")
    try expect(NebiusModelCatalog.all.map(\.id) == expectedIDs, "Catalog IDs changed")
    try expect(Set(NebiusModelCatalog.all.map(\.id)).count == 25, "Catalog IDs are not unique")
    try expect(NebiusModelCatalog.textGeneration.count == 18, "Wrong text model count")
    try expect(NebiusModelCatalog.visionLanguage.count == 6, "Wrong vision model count")
    try expect(NebiusModelCatalog.embeddings.count == 1, "Wrong embedding model count")
    try expect(NebiusModelCatalog.generative.count == 24, "Wrong generative model count")

    let embedding = NebiusModelCatalog.model(id: "Qwen/Qwen3-Embedding-8B")
    try expect(embedding?.languageModel == nil, "Embedding model became generative")

    let kimi = NebiusModelCatalog.model(id: "moonshotai/Kimi-K3")
    try expect(kimi?.capabilities.contains(.vision) == true, "Kimi K3 lost vision")
    try expect(kimi?.capabilities.contains(.toolCalling) == true, "Kimi K3 lost tool calling")
    try expect(kimi?.capabilities.contains(.reasoning) == true, "Kimi K3 lost reasoning")

    let gptOSS = NebiusModelCatalog.model(id: "openai/gpt-oss-120b")
    try expect(
      gptOSS?.capabilities.contains(.structuredOutput) == true,
      "gpt-oss-120b lost JSON mode"
    )
  }

  private static func catalogMetadata() throws {
    let snapshotURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(
        "Tools/CatalogSnapshots/models_info-\(NebiusModelCatalog.snapshotDate).json")
    let data = try Data(contentsOf: snapshotURL)
    guard let families = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw TestFailure(description: "Invalid catalog fixture")
    }
    var checkedIDs = Set<String>()
    for family in families where family["status"] as? String == "active" {
      guard let rawUseCases = family["use_cases"] as? [String],
        let flavors = family["flavors"] as? [[String: Any]]
      else { throw TestFailure(description: "Missing use cases or flavors in catalog fixture") }
      let useCases = try JSONDecoder().decode(
        [NebiusCatalogModel.UseCase].self,
        from: JSONSerialization.data(withJSONObject: rawUseCases))
      for flavor in flavors {
        guard let id = flavor["model_id"] as? String,
          let regionObjects = flavor["regions"] as? [[String: String]],
          let model = NebiusModelCatalog.model(id: id)
        else { throw TestFailure(description: "Missing model or regions in catalog fixture") }
        let rawRegions = try regionObjects.map { region in
          guard let name = region["name"] else {
            throw TestFailure(description: "Missing region name for \(id)")
          }
          return name
        }
        let regions = try JSONDecoder().decode(
          [NebiusCatalogModel.Region].self,
          from: JSONSerialization.data(withJSONObject: rawRegions))
        try expect(model.useCases == useCases, "Use-case mapping changed for \(id)")
        try expect(model.regions == regions, "Region mapping changed for \(id)")
        let encodedUseCases = try JSONDecoder().decode(
          [String].self, from: JSONEncoder().encode(model.useCases))
        let encodedRegions = try JSONDecoder().decode(
          [String].self, from: JSONEncoder().encode(model.regions))
        try expect(encodedUseCases == rawUseCases, "Use-case encoding changed for \(id)")
        try expect(encodedRegions == rawRegions, "Region encoding changed for \(id)")
        try expect(
          model.supportsFineTuning == rawUseCases.contains("fine_tune"),
          "Fine-tuning support changed for \(id)")
        try expect(
          model.supportsResponsesAPI == rawUseCases.contains("responses_api"),
          "Responses API support changed for \(id)")
        checkedIDs.insert(id)
      }
    }
    try expect(
      checkedIDs == Set(NebiusModelCatalog.all.map(\.id)),
      "Every catalog model must be checked against the source snapshot")
  }
}
