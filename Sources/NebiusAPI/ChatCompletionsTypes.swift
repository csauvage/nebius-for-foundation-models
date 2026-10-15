// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ChatCompletionRequest: Encodable, Sendable {
  public var model: String
  public var messages: [ChatMessage]
  public var store: Bool
  public var temperature: Double?
  public var topP: Double?
  public var maxCompletionTokens: Int?
  public var tools: [ChatTool]?
  public var toolChoice: ToolChoice?
  public var reasoningEffort: ReasoningEffort?
  public var responseFormat: ResponseFormat?
  public var serviceTier: ServiceTier
  public var stream: Bool
  public var streamOptions: StreamOptions

  public init(
    model: String,
    messages: [ChatMessage],
    store: Bool = false,
    temperature: Double? = nil,
    topP: Double? = nil,
    maxCompletionTokens: Int? = nil,
    tools: [ChatTool]? = nil,
    toolChoice: ToolChoice? = nil,
    reasoningEffort: ReasoningEffort? = nil,
    responseFormat: ResponseFormat? = nil,
    serviceTier: ServiceTier = .auto,
    stream: Bool = true,
    streamOptions: StreamOptions = .init(includeUsage: true)
  ) {
    self.model = model
    self.messages = messages
    self.store = store
    self.temperature = temperature
    self.topP = topP
    self.maxCompletionTokens = maxCompletionTokens
    self.tools = tools
    self.toolChoice = toolChoice
    self.reasoningEffort = reasoningEffort
    self.responseFormat = responseFormat
    self.serviceTier = serviceTier
    self.stream = stream
    self.streamOptions = streamOptions
  }

  enum CodingKeys: String, CodingKey {
    case model, messages, store, temperature, tools, stream
    case topP = "top_p"
    case maxCompletionTokens = "max_completion_tokens"
    case toolChoice = "tool_choice"
    case reasoningEffort = "reasoning_effort"
    case responseFormat = "response_format"
    case serviceTier = "service_tier"
    case streamOptions = "stream_options"
  }

  public struct StreamOptions: Encodable, Sendable {
    public var includeUsage: Bool

    public init(includeUsage: Bool) {
      self.includeUsage = includeUsage
    }

    enum CodingKeys: String, CodingKey {
      case includeUsage = "include_usage"
    }
  }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
  case none
  case minimal
  case low
  case medium
  case high
  case xhigh
  case max
}

public enum ServiceTier: String, Codable, CaseIterable, Sendable {
  case auto
  case `default`
  case overLimit = "over-limit"
  case flex
  case noLimit = "no-limit"
}

public enum ToolChoice: String, Encodable, Sendable {
  case none
  case auto
  case required
}

public struct ChatMessage: Encodable, Sendable {
  public enum Role: String, Encodable, Sendable {
    case system
    case user
    case assistant
    case tool
  }

  public enum Content: Encodable, Sendable {
    case text(String)
    case parts([ContentPart])

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .text(let text):
        try container.encode(text)
      case .parts(let parts):
        try container.encode(parts)
      }
    }
  }

  public var role: Role
  public var content: Content?
  public var toolCalls: [ToolCall]?
  public var toolCallID: String?
  public var reasoningContent: String?

  public init(
    role: Role,
    content: Content? = nil,
    toolCalls: [ToolCall]? = nil,
    toolCallID: String? = nil,
    reasoningContent: String? = nil
  ) {
    self.role = role
    self.content = content
    self.toolCalls = toolCalls
    self.toolCallID = toolCallID
    self.reasoningContent = reasoningContent
  }

  enum CodingKeys: String, CodingKey {
    case role, content
    case toolCalls = "tool_calls"
    case toolCallID = "tool_call_id"
    case reasoningContent = "reasoning_content"
  }
}

public struct ContentPart: Codable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case text
    case imageURL = "image_url"
  }

  public struct ImageURL: Codable, Sendable {
    public var url: URL
    public var detail: String?

    public init(url: URL, detail: String? = "auto") {
      self.url = url
      self.detail = detail
    }
  }

  public var type: Kind
  public var text: String?
  public var imageURL: ImageURL?

  public init(text: String) {
    self.type = .text
    self.text = text
    self.imageURL = nil
  }

  public init(imageURL: ImageURL) {
    self.type = .imageURL
    self.text = nil
    self.imageURL = imageURL
  }

  enum CodingKeys: String, CodingKey {
    case type, text
    case imageURL = "image_url"
  }
}

public struct ChatTool: Encodable, Sendable {
  public var type = "function"
  public var function: Function

  public init(name: String, description: String, parameters: JSONValue, strict: Bool = true) {
    self.function = Function(
      name: name,
      description: description,
      parameters: parameters,
      strict: strict
    )
  }

  public struct Function: Encodable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    public var strict: Bool
  }
}

public struct ToolCall: Codable, Sendable {
  public var id: String
  public var type = "function"
  public var function: FunctionCall

  public init(id: String, name: String, arguments: String) {
    self.id = id
    self.function = FunctionCall(name: name, arguments: arguments)
  }

  public struct FunctionCall: Codable, Sendable {
    public var name: String
    public var arguments: String
  }
}

public struct ResponseFormat: Encodable, Sendable {
  public var type = "json_schema"
  public var jsonSchema: JSONSchema

  public init(name: String, description: String? = nil, schema: JSONValue, strict: Bool = true) {
    self.jsonSchema = JSONSchema(
      name: name,
      description: description,
      schema: schema,
      strict: strict
    )
  }

  enum CodingKeys: String, CodingKey {
    case type
    case jsonSchema = "json_schema"
  }

  public struct JSONSchema: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var schema: JSONValue
    public var strict: Bool
  }
}

public struct ChatCompletionChunk: Decodable, Sendable {
  public var id: String?
  public var model: String?
  public var choices: [Choice]
  public var usage: Usage?

  public struct Choice: Decodable, Sendable {
    public var index: Int?
    public var delta: Delta
    public var finishReason: String?

    enum CodingKeys: String, CodingKey {
      case index, delta
      case finishReason = "finish_reason"
    }
  }

  public struct Delta: Decodable, Sendable {
    public var role: String?
    public var content: String?
    public var reasoningContent: String?
    public var toolCalls: [ToolCallDelta]?

    enum CodingKeys: String, CodingKey {
      case role, content, reasoning
      case reasoningContent = "reasoning_content"
      case toolCalls = "tool_calls"
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      role = try container.decodeIfPresent(String.self, forKey: .role)
      content = try container.decodeIfPresent(String.self, forKey: .content)
      reasoningContent =
        try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        ?? container.decodeIfPresent(String.self, forKey: .reasoning)
      toolCalls = try container.decodeIfPresent([ToolCallDelta].self, forKey: .toolCalls)
    }
  }

  public struct ToolCallDelta: Decodable, Sendable {
    public var index: Int
    public var id: String?
    public var function: FunctionCallDelta?

    public struct FunctionCallDelta: Decodable, Sendable {
      public var name: String?
      public var arguments: String?
    }
  }

  public struct Usage: Decodable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var promptTokensDetails: PromptTokenDetails?
    public var completionTokensDetails: CompletionTokenDetails?

    enum CodingKeys: String, CodingKey {
      case promptTokens = "prompt_tokens"
      case completionTokens = "completion_tokens"
      case promptTokensDetails = "prompt_tokens_details"
      case completionTokensDetails = "completion_tokens_details"
    }

    public struct PromptTokenDetails: Decodable, Sendable {
      public var cachedTokens: Int?

      enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
      }
    }

    public struct CompletionTokenDetails: Decodable, Sendable {
      public var reasoningTokens: Int?

      enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
      }
    }
  }
}
