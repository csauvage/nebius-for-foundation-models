// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

#if compiler(>=6.4)
  import Foundation
  import FoundationModels
  import NebiusForFoundationModels

  @available(macOS 27.0, *)
  @main
  struct NebiusExample {
    static func main() async throws {
      let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
      guard !prompt.isEmpty else {
        print("Usage: NEBIUS_API_KEY=<key> swift run NebiusExample <prompt>")
        return
      }

      let model = NebiusLanguageModel(
        name: .nemotron35Lightning,
        auth: .apiKey(ProcessInfo.processInfo.environment["NEBIUS_API_KEY"] ?? "")
      )
      let session = LanguageModelSession(model: model)
      let stream = session.streamResponse(to: prompt)
      for try await snapshot in stream {
        print(snapshot.content)
      }
    }
  }
#else
  @main
  struct NebiusExample {
    static func main() {
      print("NebiusExample requires Xcode 27 and the macOS 27 SDK.")
    }
  }
#endif
