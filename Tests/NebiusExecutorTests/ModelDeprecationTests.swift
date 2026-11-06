// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

#if compiler(>=6.4)
  import Foundation
  @testable import NebiusForFoundationModels
  import Testing

  @Suite struct ModelDeprecationTests {
    @Test(arguments: Array(NebiusModelCatalog.removedModelReplacements.keys))
    func removedIDsStayOutOfCatalogButAllowExplicitDedicatedUse(_ id: String) throws {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      #expect(NebiusModelCatalog.model(id: id) == nil)
      let replacement = try #require(NebiusModelCatalog.removedModelReplacements[id])
      #expect(NebiusModelCatalog.model(id: replacement)?.languageModel != nil)
      let message = try #require(NebiusModelCatalog.removalMessage(for: id))
      #expect(message.contains(id))
      #expect(message.contains(replacement))
      #expect(message.contains("2026-11-09"))
      let configuration = NebiusModel.custom(id: id, capabilities: [.toolCalling])
      let adapter = NebiusLanguageModel(
        name: configuration, auth: .proxied(headers: [:]),
        baseURL: URL(string: "https://dedicated.example/v1")!)
      #expect(adapter.model.id == id)
      #expect(adapter.model.capabilities == [.toolCalling])
    }

    @Test func currentAndCustomModelsHaveNoDeprecationMessage() {
      #expect(NebiusModelCatalog.model(id: "moonshotai/Kimi-K3.1-Pro")?.deprecationMessage == nil)
      #expect(NebiusModelCatalog.model(id: "private/model")?.deprecationMessage == nil)
      #expect(NebiusModelCatalog.removalMessage(for: "moonshotai/Kimi-K3.1-Pro") == nil)
      #expect(NebiusModelCatalog.removalMessage(for: "private/model") == nil)
    }

    @Test func removedFastVariantIsReportedWithoutSilentSubstitution() {
      guard #available(macOS 27.0, iOS 27.0, *) else { return }
      let configuration = NebiusModel.custom(
        id: "moonshotai/Kimi-K3.1-Pro", fastVariantID: "zai-org/GLM-5.1",
        capabilities: .fullText)
      let adapter = NebiusLanguageModel(name: configuration, auth: .proxied(headers: [:]))
      #expect(adapter.model == configuration)
      #expect(NebiusModelCatalog.removalMessage(for: "zai-org/GLM-5.1")?.contains("zai-org/GLM-5.3") == true)
    }
  }
#endif
