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
  let deprecated: Bool?
  let regions: [Region]

  enum CodingKeys: String, CodingKey {
    case quantization, deprecated, regions
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
  case missingModelAlias(String)
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
    case .missingModelAlias(let id):
      "No typed NebiusModel alias for \(id). Add its name to UpdateNebiusModelCatalog.aliases before regenerating."
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
    "image2text": "imageToText",
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

  // Keep public alias spellings stable. Deprecation annotations follow the
  // provider snapshot so a future refresh also updates compiler warnings.
  private static let aliases = [
    "MiniMaxAI/MiniMax-M3": "minimaxM3",
    "MiniMaxAI/MiniMax-M3.1-Flash": "minimaxM31Flash",
    "NousResearch/Hermes-4-405B": "hermes4405B",
    "Qwen/Qwen3-235B-A22B-Instruct-2507": "qwen3235BInstruct2507",
    "Qwen/Qwen3-30B-A3B-Instruct-2507": "qwen330BInstruct2507",
    "Qwen/Qwen3.5-397B-A17B": "qwen35Large",
    "Qwen/Qwen3.8-27B": "qwen3827B",
    "deepseek-ai/DeepSeek-V4-Flash-0731": "deepSeekV4Flash0731",
    "deepseek-ai/DeepSeek-V4-Pro": "deepSeekV4Pro",
    "deepseek-ai/DeepSeek-V4-Pro-0813": "deepSeekV4Pro0813",
    "deepseek-ai/DeepSeek-V4.1-Flash": "deepSeekV41Flash",
    "deepseek-ai/DeepSeek-V4.1-Flash-1017": "deepSeekV41Flash1017",
    "google/gemma-3-27b-it": "gemma327B",
    "meta-models/muse-spark-open": "museSparkOpen",
    "moonshotai/Kimi-K2.6": "kimiK26",
    "moonshotai/Kimi-K2.7-Code": "kimiK27Code",
    "moonshotai/Kimi-K3": "kimiK3",
    "moonshotai/Kimi-K3.1-Pro": "kimiK31Pro",
    "nvidia/Nemotron-3.5-Super-VL": "nemotron35SuperVL",
    "nvidia/Nemotron-3_5-Lightning": "nemotron35Lightning",
    "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B": "nemotron3Nano30B",
    "nvidia/Nemotron-3-Ultra-550b-a55b": "nemotron3Ultra550B",
    "nvidia/nemotron-3-super-120b-a12b": "nemotron3Super120B",
    "openai/gpt-oss-120b": "gptOSS120B",
    "openbmb/MiniCPM-V-4_5": "miniCPMV45",
    "reflection/beam": "reflectionBeam",
    "zai-org/GLM-5.1": "glm51",
    "zai-org/GLM-5.2": "glm52",
    "zai-org/GLM-5.3": "glm53",
    "zai-org/GLM-5.3-Flash": "glm53Flash",
  ]

  // These original aliases used .fullText before the catalog generated them.
  // Preserve their behavior for existing callers, even where metadata differs.
  private static let fullTextAliases: Set<String> = [
    "MiniMaxAI/MiniMax-M3", "nvidia/Nemotron-3_5-Lightning",
    "openai/gpt-oss-120b",
  ]

  // Removed proactively before the 2026-11-09 Serverless shutdown. Keep this
  // independent of models_info: its deprecated flags omit seven affected IDs.
  // https://docs.tokenfactory.nebius.com/november-2026-deprecation-notice
  private static let removedModelReplacements = [
    "deepseek-ai/DeepSeek-V4-Pro": "deepseek-ai/DeepSeek-V4-Pro-0813",
    "deepseek-ai/DeepSeek-V4-Flash-0731": "deepseek-ai/DeepSeek-V4.1-Flash-1017",
    "deepseek-ai/DeepSeek-V4.1-Flash": "deepseek-ai/DeepSeek-V4.1-Flash-1017",
    "Qwen/Qwen3-235B-A22B-Instruct-2507": "Qwen/Qwen3-30B-A3B-Instruct-2507",
    "Qwen/Qwen3.5-397B-A17B": "Qwen/Qwen3.8-27B",
    "moonshotai/Kimi-K2.6": "moonshotai/Kimi-K3",
    "moonshotai/Kimi-K2.7-Code": "moonshotai/Kimi-K3",
    "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B": "nvidia/Nemotron-3_5-Lightning",
    "nvidia/nemotron-3-super-120b-a12b": "nvidia/Nemotron-3.5-Super-VL",
    "openbmb/MiniCPM-V-4_5": "nvidia/Nemotron-3.5-Super-VL",
    "zai-org/GLM-5.1": "zai-org/GLM-5.3",
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
      .filter { removedModelReplacements[$0.flavor.modelID] == nil }
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
    let renderedAliases = try entries.compactMap(renderAlias).joined(separator: "\n\n")
    let removedIDs = removedModelReplacements.keys.sorted()
    let renderedRemovals = removedIDs.map { id in
      "    \(swiftString(id)): \(swiftString(removedModelReplacements[id]!)),"
    }.joined(separator: "\n")
    let unavailableAliases = try removedIDs.map(renderUnavailableAlias).joined(separator: "\n\n")
    return """
      // This file is generated by `swift run UpdateNebiusModelCatalog`.
      // Do not edit it by hand.
      // Copyright 2026 BNC Consulting
      // SPDX-License-Identifier: Apache-2.0

      import Foundation

      /// The public Token Factory catalog with announced Serverless withdrawals excluded.
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

        // Migration metadata only; these IDs are never selectable catalog entries.
        static let removedModelReplacements: [String: String] = [
      \(renderedRemovals)
        ]

        static func removalMessage(for id: String) -> String? {
          guard let replacement = removedModelReplacements[id] else { return nil }
          return "\\(id) was removed from the package catalog ahead of the 2026-11-09 Serverless shutdown. "
            + "Use \\(replacement) for Serverless. Dedicated Endpoints are unaffected."
        }
      }

      // Typed constants for every generative model. Availability annotations
      // reflect the provider's deprecation flags in this snapshot.
      extension NebiusModel {
      \(renderedAliases)

        // Unavailable migration declarations provide Xcode errors and replacement fix-its.
      \(unavailableAliases)
      }

      """
  }

  private static func renderUnavailableAlias(_ id: String) throws -> String {
    guard let alias = aliases[id],
      let replacementID = removedModelReplacements[id],
      let replacementAlias = aliases[replacementID]
    else { throw GeneratorError.missingModelAlias(id) }
    let message = "\(id) was removed ahead of the 2026-11-09 Serverless shutdown. "
      + "Use .\(replacementAlias) (\(replacementID))."
    return """
        /// Removed from the selectable catalog; migrate to `.\(replacementAlias)`.
        @available(*, unavailable, renamed: \(swiftString(replacementAlias)), message: \(swiftString(message)))
        public static var \(alias): NebiusModel {
          fatalError("Removed model cannot be selected")
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
            capabilities: \(capabilities),
            isDeprecated: \(flavor.deprecated == true)
          )
      """
  }

  private static func renderAlias(_ entry: Entry) throws -> String? {
    let id = entry.flavor.modelID
    guard entry.flavor.modelType != "embedding" else { return nil }
    guard let alias = aliases[id] else { throw GeneratorError.missingModelAlias(id) }
    var lines = ["  /// \(id)"]
    if entry.flavor.deprecated == true {
      let message = "\(id) is deprecated in the public Token Factory catalog. "
        + "Choose a non-deprecated model from NebiusModelCatalog."
      lines.append("  @available(*, deprecated, message: \(swiftString(message)))")
    }
    let features = fullTextAliases.contains(id) ? ".fullText" : capabilities(for: entry)
    lines.append("  public static let \(alias) = NebiusModel(")
    lines.append("    modelID: \(swiftString(id)),")
    lines.append("    capabilities: \(features)")
    lines.append("  )")
    return lines.joined(separator: "\n")
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
