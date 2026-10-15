// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TavilySearchDepth: String, Codable, CaseIterable, Sendable {
  case ultraFast = "ultra-fast"
  case fast
  case basic
  case advanced
}

public enum TavilyExtractDepth: String, Codable, CaseIterable, Sendable {
  case basic
  case advanced
}

public enum TavilySearchTopic: String, Codable, CaseIterable, Sendable {
  case general
  case news
  case finance
}

public enum TavilyTimeRange: String, Codable, CaseIterable, Sendable {
  case day
  case week
  case month
  case year
}

public enum TavilyDomainMode: String, Codable, CaseIterable, Sendable {
  case filter
  case boost
}

public enum TavilyContentFormat: String, Codable, CaseIterable, Sendable {
  case markdown
  case text
}

public enum TavilyAnswerMode: Encodable, Sendable {
  case none
  case basic
  case advanced

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .none: try container.encode(false)
    case .basic: try container.encode("basic")
    case .advanced: try container.encode("advanced")
    }
  }
}

public enum TavilyRawContentMode: Encodable, Sendable {
  case none
  case markdown
  case text

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .none: try container.encode(false)
    case .markdown: try container.encode("markdown")
    case .text: try container.encode("text")
    }
  }
}

public struct TavilyUsage: Decodable, Equatable, Sendable {
  public let credits: Int
}

public struct TavilySearchRequest: Encodable, Sendable {
  public var query: String
  public var searchDepth: TavilySearchDepth
  public var chunksPerSource: Int
  public var maxResults: Int
  public var topic: TavilySearchTopic
  public var timeRange: TavilyTimeRange?
  public var startDate: String?
  public var endDate: String?
  public var includePublishedDate: Bool
  public var filterByPublishedDate: Bool
  public var includeAnswer: TavilyAnswerMode
  public var includeRawContent: TavilyRawContentMode
  public var includeImages: Bool
  public var includeImageDescriptions: Bool
  public var includeFavicon: Bool
  public var includeDomains: [String]
  public var excludeDomains: [String]
  public var includeDomainsMode: TavilyDomainMode?
  public var country: String?
  public var language: String?
  public var filterByLanguage: Bool
  public var autoParameters: Bool
  public var exactMatch: Bool
  public var includeUsage: Bool
  public var safeSearch: Bool

  public init(
    query: String,
    searchDepth: TavilySearchDepth = .basic,
    chunksPerSource: Int = 3,
    maxResults: Int = 10,
    topic: TavilySearchTopic = .general,
    timeRange: TavilyTimeRange? = nil,
    startDate: String? = nil,
    endDate: String? = nil,
    includePublishedDate: Bool = false,
    filterByPublishedDate: Bool = false,
    includeAnswer: TavilyAnswerMode = .none,
    includeRawContent: TavilyRawContentMode = .none,
    includeImages: Bool = false,
    includeImageDescriptions: Bool = false,
    includeFavicon: Bool = false,
    includeDomains: [String] = [],
    excludeDomains: [String] = [],
    includeDomainsMode: TavilyDomainMode? = nil,
    country: String? = nil,
    language: String? = nil,
    filterByLanguage: Bool = false,
    autoParameters: Bool = false,
    exactMatch: Bool = false,
    includeUsage: Bool = false,
    safeSearch: Bool = false
  ) {
    self.query = query
    self.searchDepth = searchDepth
    self.chunksPerSource = chunksPerSource
    self.maxResults = maxResults
    self.topic = topic
    self.timeRange = timeRange
    self.startDate = startDate
    self.endDate = endDate
    self.includePublishedDate = includePublishedDate
    self.filterByPublishedDate = filterByPublishedDate
    self.includeAnswer = includeAnswer
    self.includeRawContent = includeRawContent
    self.includeImages = includeImages
    self.includeImageDescriptions = includeImageDescriptions
    self.includeFavicon = includeFavicon
    self.includeDomains = includeDomains
    self.excludeDomains = excludeDomains
    self.includeDomainsMode = includeDomainsMode
    self.country = country
    self.language = language
    self.filterByLanguage = filterByLanguage
    self.autoParameters = autoParameters
    self.exactMatch = exactMatch
    self.includeUsage = includeUsage
    self.safeSearch = safeSearch
  }

  enum CodingKeys: String, CodingKey {
    case query, topic, country, language
    case searchDepth = "search_depth"
    case chunksPerSource = "chunks_per_source"
    case maxResults = "max_results"
    case timeRange = "time_range"
    case startDate = "start_date"
    case endDate = "end_date"
    case includePublishedDate = "include_published_date"
    case filterByPublishedDate = "filter_by_published_date"
    case includeAnswer = "include_answer"
    case includeRawContent = "include_raw_content"
    case includeImages = "include_images"
    case includeImageDescriptions = "include_image_descriptions"
    case includeFavicon = "include_favicon"
    case includeDomains = "include_domains"
    case excludeDomains = "exclude_domains"
    case includeDomainsMode = "include_domains_mode"
    case filterByLanguage = "filter_by_language"
    case autoParameters = "auto_parameters"
    case exactMatch = "exact_match"
    case includeUsage = "include_usage"
    case safeSearch = "safe_search"
  }
}

public struct TavilyImage: Decodable, Equatable, Sendable {
  public let url: String
  public let description: String?
}

public struct TavilySearchResult: Decodable, Equatable, Sendable {
  public let title: String
  public let url: String
  public let content: String
  public let score: Double?
  public let rawContent: String?
  public let publishedDate: String?
  public let favicon: String?
  public let images: [TavilyImage]?
  public let id: String?

  enum CodingKeys: String, CodingKey {
    case title, url, content, score, favicon, images, id
    case rawContent = "raw_content"
    case publishedDate = "published_date"
  }
}

public struct TavilySearchResponse: Decodable, Sendable {
  public let query: String
  public let answer: String?
  public let images: [TavilyImage]?
  public let results: [TavilySearchResult]
  public let responseTime: Double?
  public let usage: TavilyUsage?
  public let requestID: String?

  enum CodingKeys: String, CodingKey {
    case query, answer, images, results, usage
    case responseTime = "response_time"
    case requestID = "request_id"
  }
}

public struct TavilyExtractRequest: Encodable, Sendable {
  public var urls: [String]
  public var query: String?
  public var chunksPerSource: Int?
  public var extractDepth: TavilyExtractDepth
  public var includeImages: Bool
  public var includeFavicon: Bool
  public var format: TavilyContentFormat
  public var timeout: Double?
  public var includeUsage: Bool

  public init(
    urls: [String],
    query: String? = nil,
    chunksPerSource: Int? = nil,
    extractDepth: TavilyExtractDepth = .basic,
    includeImages: Bool = false,
    includeFavicon: Bool = false,
    format: TavilyContentFormat = .markdown,
    timeout: Double? = nil,
    includeUsage: Bool = false
  ) {
    self.urls = urls
    self.query = query
    self.chunksPerSource = chunksPerSource
    self.extractDepth = extractDepth
    self.includeImages = includeImages
    self.includeFavicon = includeFavicon
    self.format = format
    self.timeout = timeout
    self.includeUsage = includeUsage
  }

  enum CodingKeys: String, CodingKey {
    case urls, query, format, timeout
    case chunksPerSource = "chunks_per_source"
    case extractDepth = "extract_depth"
    case includeImages = "include_images"
    case includeFavicon = "include_favicon"
    case includeUsage = "include_usage"
  }
}

public struct TavilyExtractResult: Decodable, Equatable, Sendable {
  public let url: String
  public let rawContent: String
  public let images: [String]?
  public let favicon: String?

  enum CodingKeys: String, CodingKey {
    case url, images, favicon
    case rawContent = "raw_content"
  }
}

public struct TavilyFailedResult: Decodable, Equatable, Sendable {
  public let url: String
  public let error: String
}

public struct TavilyExtractResponse: Decodable, Sendable {
  public let results: [TavilyExtractResult]?
  public let failedResults: [TavilyFailedResult]?
  public let responseTime: Double?
  public let usage: TavilyUsage?
  public let requestID: String?

  enum CodingKeys: String, CodingKey {
    case results, usage
    case failedResults = "failed_results"
    case responseTime = "response_time"
    case requestID = "request_id"
  }
}

public struct TavilyMapRequest: Encodable, Sendable {
  public var url: String
  public var instructions: String?
  public var maxDepth: Int
  public var maxBreadth: Int
  public var limit: Int
  public var selectPaths: [String]?
  public var selectDomains: [String]?
  public var excludePaths: [String]?
  public var excludeDomains: [String]?
  public var allowExternal: Bool
  public var timeout: Double
  public var includeUsage: Bool

  public init(
    url: String,
    instructions: String? = nil,
    maxDepth: Int = 1,
    maxBreadth: Int = 20,
    limit: Int = 50,
    selectPaths: [String]? = nil,
    selectDomains: [String]? = nil,
    excludePaths: [String]? = nil,
    excludeDomains: [String]? = nil,
    allowExternal: Bool = true,
    timeout: Double = 150,
    includeUsage: Bool = false
  ) {
    self.url = url
    self.instructions = instructions
    self.maxDepth = maxDepth
    self.maxBreadth = maxBreadth
    self.limit = limit
    self.selectPaths = selectPaths
    self.selectDomains = selectDomains
    self.excludePaths = excludePaths
    self.excludeDomains = excludeDomains
    self.allowExternal = allowExternal
    self.timeout = timeout
    self.includeUsage = includeUsage
  }

  enum CodingKeys: String, CodingKey {
    case url, instructions, limit, timeout
    case maxDepth = "max_depth"
    case maxBreadth = "max_breadth"
    case selectPaths = "select_paths"
    case selectDomains = "select_domains"
    case excludePaths = "exclude_paths"
    case excludeDomains = "exclude_domains"
    case allowExternal = "allow_external"
    case includeUsage = "include_usage"
  }
}

public struct TavilyCrawlRequest: Encodable, Sendable {
  public var url: String
  public var instructions: String?
  public var chunksPerSource: Int?
  public var maxDepth: Int
  public var maxBreadth: Int
  public var limit: Int
  public var selectPaths: [String]?
  public var selectDomains: [String]?
  public var excludePaths: [String]?
  public var excludeDomains: [String]?
  public var allowExternal: Bool
  public var includeImages: Bool
  public var extractDepth: TavilyExtractDepth
  public var format: TavilyContentFormat
  public var includeFavicon: Bool
  public var timeout: Double
  public var includeUsage: Bool

  public init(
    url: String,
    instructions: String? = nil,
    chunksPerSource: Int? = nil,
    maxDepth: Int = 1,
    maxBreadth: Int = 20,
    limit: Int = 50,
    selectPaths: [String]? = nil,
    selectDomains: [String]? = nil,
    excludePaths: [String]? = nil,
    excludeDomains: [String]? = nil,
    allowExternal: Bool = true,
    includeImages: Bool = false,
    extractDepth: TavilyExtractDepth = .basic,
    format: TavilyContentFormat = .markdown,
    includeFavicon: Bool = false,
    timeout: Double = 150,
    includeUsage: Bool = false
  ) {
    self.url = url
    self.instructions = instructions
    self.chunksPerSource = chunksPerSource
    self.maxDepth = maxDepth
    self.maxBreadth = maxBreadth
    self.limit = limit
    self.selectPaths = selectPaths
    self.selectDomains = selectDomains
    self.excludePaths = excludePaths
    self.excludeDomains = excludeDomains
    self.allowExternal = allowExternal
    self.includeImages = includeImages
    self.extractDepth = extractDepth
    self.format = format
    self.includeFavicon = includeFavicon
    self.timeout = timeout
    self.includeUsage = includeUsage
  }

  enum CodingKeys: String, CodingKey {
    case url, instructions, limit, format, timeout
    case chunksPerSource = "chunks_per_source"
    case maxDepth = "max_depth"
    case maxBreadth = "max_breadth"
    case selectPaths = "select_paths"
    case selectDomains = "select_domains"
    case excludePaths = "exclude_paths"
    case excludeDomains = "exclude_domains"
    case allowExternal = "allow_external"
    case includeImages = "include_images"
    case extractDepth = "extract_depth"
    case includeFavicon = "include_favicon"
    case includeUsage = "include_usage"
  }
}

public struct TavilyMapResponse: Decodable, Sendable {
  public let baseURL: String?
  public let results: [String]?
  public let responseTime: Double?
  public let usage: TavilyUsage?
  public let requestID: String?

  enum CodingKeys: String, CodingKey {
    case results, usage
    case baseURL = "base_url"
    case responseTime = "response_time"
    case requestID = "request_id"
  }
}

public struct TavilyCrawlResult: Decodable, Equatable, Sendable {
  public let url: String
  public let rawContent: String
  public let favicon: String?

  enum CodingKeys: String, CodingKey {
    case url, favicon
    case rawContent = "raw_content"
  }
}

public struct TavilyCrawlResponse: Decodable, Sendable {
  public let baseURL: String?
  public let results: [TavilyCrawlResult]?
  public let responseTime: Double?
  public let usage: TavilyUsage?
  public let requestID: String?

  enum CodingKeys: String, CodingKey {
    case results, usage
    case baseURL = "base_url"
    case responseTime = "response_time"
    case requestID = "request_id"
  }
}

public enum TavilyResearchModel: String, Codable, CaseIterable, Sendable {
  case mini
  case pro
  case auto
}

public enum TavilyCitationFormat: String, Codable, CaseIterable, Sendable {
  case numbered
  case mla
  case apa
  case chicago
}

public enum TavilyResearchOutputLength: String, Codable, CaseIterable, Sendable {
  case short
  case standard
  case long
}

public struct TavilyResearchFile: Encodable, Sendable {
  public var name: String
  public var data: String
  public var type: String

  public init(name: String, base64Data: String) {
    self.name = name
    self.data = base64Data
    self.type = "base64"
  }
}

public struct TavilyResearchRequest: Encodable, Sendable {
  public var input: String
  public var model: TavilyResearchModel
  public var stream: Bool
  public var outputSchema: TavilyJSONValue?
  public var citationFormat: TavilyCitationFormat
  public var includeDomains: [String]
  public var excludeDomains: [String]
  public var outputLength: TavilyResearchOutputLength
  public var files: [TavilyResearchFile]

  public init(
    input: String,
    model: TavilyResearchModel = .auto,
    stream: Bool = false,
    outputSchema: TavilyJSONValue? = nil,
    citationFormat: TavilyCitationFormat = .numbered,
    includeDomains: [String] = [],
    excludeDomains: [String] = [],
    outputLength: TavilyResearchOutputLength = .standard,
    files: [TavilyResearchFile] = []
  ) {
    self.input = input
    self.model = model
    self.stream = stream
    self.outputSchema = outputSchema
    self.citationFormat = citationFormat
    self.includeDomains = includeDomains
    self.excludeDomains = excludeDomains
    self.outputLength = outputLength
    self.files = files
  }

  enum CodingKeys: String, CodingKey {
    case input, model, stream, files
    case outputSchema = "output_schema"
    case citationFormat = "citation_format"
    case includeDomains = "include_domains"
    case excludeDomains = "exclude_domains"
    case outputLength = "output_length"
  }
}

public struct TavilyResearchTask: Decodable, Sendable {
  public let requestID: String
  public let createdAt: String?
  public let status: String
  public let input: String?
  public let model: String?
  public let responseTime: Double?

  enum CodingKeys: String, CodingKey {
    case status, input, model
    case requestID = "request_id"
    case createdAt = "created_at"
    case responseTime = "response_time"
  }
}

public struct TavilyResearchSource: Decodable, Equatable, Sendable {
  public let title: String?
  public let url: String
  public let favicon: String?
}

public enum TavilyResearchContent: Decodable, Equatable, Sendable {
  case text(String)
  case structured(TavilyJSONValue)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .text(string)
    } else {
      self = .structured(try container.decode(TavilyJSONValue.self))
    }
  }

  public var promptText: String {
    switch self {
    case .text(let value): value
    case .structured(let value): value.jsonString
    }
  }
}

public struct TavilyResearchCompleted: Decodable, Sendable {
  public let requestID: String
  public let createdAt: String?
  public let status: String
  public let content: TavilyResearchContent
  public let sources: [TavilyResearchSource]
  public let responseTime: Double?
  public let usage: TavilyUsage?

  enum CodingKeys: String, CodingKey {
    case status, content, sources, usage
    case requestID = "request_id"
    case createdAt = "created_at"
    case responseTime = "response_time"
  }
}

public enum TavilyResearchStatus: Sendable {
  case pending(requestID: String)
  case inProgress(requestID: String)
  case completed(TavilyResearchCompleted)
  case failed(requestID: String)
}

public struct TavilyResearchStreamChunk: Decodable, Sendable {
  public let id: String?
  public let object: String?
  public let model: String?
  public let created: Int?
  public let choices: [Choice]?
  public let error: String?

  public struct Choice: Decodable, Sendable {
    public let delta: TavilyJSONValue?
  }
}

public enum TavilyResearchStreamEvent: Sendable {
  case chunk(TavilyResearchStreamChunk)
  case failure(message: String)
  case done
}
