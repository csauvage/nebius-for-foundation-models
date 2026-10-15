// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct CatalogFamily: Decodable {
  let type: String
  let name: String
  let status: String
  let vendor: String
  let description: String
  let tags: [String]
  let useCases: [String]
  let flavors: [Flavor]

  enum CodingKeys: String, CodingKey {
    case type, name, status, vendor, description, tags, flavors
    case useCases = "use_cases"
  }
}

private struct Flavor: Decodable {
  let modelID: String
  let modelType: String
  let maxModelLength: Int
  let tokensPerSecond: Double?
  let inputPrice: Double
  let outputPrice: Double
  let quantization: String?
  let regions: [Region]

  enum CodingKeys: String, CodingKey {
    case quantization, regions
    case modelID = "model_id"
    case modelType = "model_type"
    case maxModelLength = "max_model_len"
    case tokensPerSecond = "tokens_per_second"
    case inputPrice = "input_price_per_million_tokens"
    case outputPrice = "output_price_per_million_tokens"
  }
}

private struct Region: Decodable {
  let name: String
}

private struct Entry {
  let family: CatalogFamily
  let flavor: Flavor
}

private enum GeneratorError: LocalizedError {
  case invalidArguments(String)
  case invalidResponse(Int)
  case unknownCatalogValue(field: String, value: String, modelID: String)
  case stale(URL)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message): message
    case .invalidResponse(let status): "Catalog request failed with HTTP \(status)."
    case .unknownCatalogValue(let field, let value, let modelID):
      "Unknown catalog \(field) value '\(value)' for \(modelID). "
        + "Add its NebiusCatalogModel enum case and generator mapping before regenerating."
    case .stale(let url):
      "The generated catalog differs from \(url.path). Run the updater without --check."
    }
  }
}

@main
private struct UpdateNebiusModelCatalog {
  static let publicCatalogURL = URL(
    string: "https://tokenfactory.nebius.com/api/public/models_info"
  )!

  // Explicit mappings keep generated Swift independent of the Foundation Models SDK.
  // New provider values must be reviewed alongside the public catalog enums.
  private static let useCaseCases = [
    "classification": "classification",
    "clustering": "clustering",
    "code": "code",
    "complex_writing": "complexWriting",
    "context_and_rag": "contextAndRAG",
    "dedicated-endpoint": "dedicatedEndpoint",
    "fine_tune": "fineTune",
    "function_calling": "functionCalling",
    "image": "image",
    "multilabel classification": "multilabelClassification",
    "multilingual": "multilingual",
    "pair classification": "pairClassification",
    "reasoning": "reasoning",
    "reranking": "reranking",
    "responses_api": "responsesAPI",
    "retrieval": "retrieval",
    "summarization": "summarization",
    "text": "text",
    "video": "video",
  ]

  private static let regionCases = [
    "eu-north1": "euNorth1",
    "eu-west2": "euWest2",
    "uk-south1": "ukSouth1",
    "us-central1": "usCentral1",
    "us-north1": "usNorth1",
  ]

  static func main() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var input: URL?
    var output =
      packageRoot
      .appendingPathComponent("Sources/NebiusForFoundationModels/Generated")
      .appendingPathComponent("NebiusModelCatalog.generated.swift")
    var snapshotDate = currentUTCDate()
    var checkOnly = false

    while !arguments.isEmpty {
      let argument = arguments.removeFirst()
      switch argument {
      case "--input":
        input = URL(fileURLWithPath: try value(after: argument, in: &arguments))
      case "--output":
        output = URL(fileURLWithPath: try value(after: argument, in: &arguments))
      case "--snapshot-date":
        snapshotDate = try value(after: argument, in: &arguments)
      case "--check":
        checkOnly = true
      case "--help", "-h":
        printUsage()
        return
      default:
        throw GeneratorError.invalidArguments("Unknown argument: \(argument)")
      }
    }

    let data = try await catalogData(input: input)
    let families = try JSONDecoder().decode([CatalogFamily].self, from: data)
    let entries =
      families
      .filter { $0.status == "active" }
      .flatMap { family in family.flavors.map { Entry(family: family, flavor: $0) } }
      .sorted { $0.flavor.modelID < $1.flavor.modelID }
    let source = try render(entries: entries, snapshotDate: snapshotDate)

    if checkOnly {
      guard let existing = try? String(contentsOf: output, encoding: .utf8), existing == source
      else {
        throw GeneratorError.stale(output)
      }
      print("Catalog is up to date: \(entries.count) models as of \(snapshotDate)")
      return
    }

    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try source.write(to: output, atomically: true, encoding: .utf8)
    print("Wrote \(entries.count) models to \(output.path)")
  }

  private static var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func value(after option: String, in arguments: inout [String]) throws -> String {
    guard !arguments.isEmpty else {
      throw GeneratorError.invalidArguments("Missing value after \(option)")
    }
    return arguments.removeFirst()
  }

  private static func catalogData(input: URL?) async throws -> Data {
    if let input { return try Data(contentsOf: input) }
    let (data, response) = try await URLSession.shared.data(from: publicCatalogURL)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw GeneratorError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return data
  }

  private static func currentUTCDate() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private static func render(entries: [Entry], snapshotDate: String) throws -> String {
    let renderedEntries = try entries.map(render).joined(separator: ",\n")
    return """
      // This file is generated by `swift run UpdateNebiusModelCatalog`.
      // Do not edit it by hand.
      // Copyright 2026 BNC Consulting
      // SPDX-License-Identifier: Apache-2.0

      import Foundation

      /// The public Token Factory catalog frozen for a package release.
      public enum NebiusModelCatalog {
        public static let snapshotDate = \(swiftString(snapshotDate))
        public static let sourceURL = URL(
          string: \(swiftString(publicCatalogURL.absoluteString))
        )!

        public static let all: [NebiusCatalogModel] = [
      \(renderedEntries)
        ]

        public static let textGeneration = all.filter { $0.modality == .textToText }
        public static let visionLanguage = all.filter { $0.modality == .imageToText }
        public static let embeddings = all.filter { $0.modality == .embedding }
        public static let generative = all.filter { $0.languageModel != nil }

        public static func model(id: String) -> NebiusCatalogModel? {
          all.first { $0.id == id }
        }
      }

      """
  }

  private static func render(_ entry: Entry) throws -> String {
    let family = entry.family
    let flavor = entry.flavor
    let modality =
      switch flavor.modelType {
      case "text2text": ".textToText"
      case "image2text": ".imageToText"
      case "embedding": ".embedding"
      default: ".textToText"
      }
    let capabilities = capabilities(for: entry)
    let speed = flavor.tokensPerSecond.map(number) ?? "nil"
    let quantization = flavor.quantization.map(swiftString) ?? "nil"
    let tags = swiftArray(family.tags)
    let useCases = try enumArray(
      family.useCases, cases: useCaseCases, field: "use_cases", modelID: flavor.modelID)
    let regions = try enumArray(
      flavor.regions.map(\.name), cases: regionCases, field: "regions", modelID: flavor.modelID)

    return """
          NebiusCatalogModel(
            id: \(swiftString(flavor.modelID)),
            name: \(swiftString(family.name)),
            vendor: \(swiftString(family.vendor)),
            modality: \(modality),
            description: \(swiftString(family.description)),
            contextWindow: \(integer(flavor.maxModelLength)),
            inputPricePerMillionTokens: \(number(flavor.inputPrice)),
            outputPricePerMillionTokens: \(number(flavor.outputPrice)),
            tokensPerSecond: \(speed),
            quantization: \(quantization),
            tags: \(tags),
            useCases: \(useCases),
            regions: \(regions),
            capabilities: \(capabilities)
          )
      """
  }

  private static func capabilities(for entry: Entry) -> String {
    let useCases = Set(entry.family.useCases)
    let tags = Set(entry.family.tags.map { $0.lowercased() })
    var values: [String] = []
    if entry.flavor.modelType == "image2text" || useCases.contains("image") {
      values.append(".vision")
    }
    if useCases.contains("function_calling") { values.append(".toolCalling") }
    if useCases.contains("reasoning") { values.append(".reasoning") }
    if tags.contains("json mode") { values.append(".structuredOutput") }
    return values.isEmpty ? "[]" : "[\(values.joined(separator: ", "))]"
  }

  private static func swiftString(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let data = try! encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  private static func swiftArray(_ values: [String]) -> String {
    "[\(values.map(swiftString).joined(separator: ", "))]"
  }

  private static func enumArray(
    _ values: [String], cases: [String: String], field: String, modelID: String
  ) throws -> String {
    let members = try values.map { value in
      guard let member = cases[value] else {
        throw GeneratorError.unknownCatalogValue(field: field, value: value, modelID: modelID)
      }
      return ".\(member)"
    }
    return "[\(members.joined(separator: ", "))]"
  }

  private static func integer(_ value: Int) -> String {
    let digits = String(value.magnitude)
    let grouped = digits.enumerated().map { index, digit in
      let separator = index > 0 && (digits.count - index).isMultiple(of: 3) ? "_" : ""
      return separator + String(digit)
    }.joined()
    return (value < 0 ? "-" : "") + grouped
  }

  private static func number(_ value: Double) -> String {
    String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private static func printUsage() {
    print(
      """
      Usage: swift run UpdateNebiusModelCatalog [options]

        --input <json>           Read a saved public models_info response.
        --output <swift>         Override the generated Swift file path.
        --snapshot-date <date>   Set the catalog date (YYYY-MM-DD).
        --check                  Fail instead of writing when output differs.
      """
    )
  }
}
