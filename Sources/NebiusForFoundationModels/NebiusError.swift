// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum NebiusError: LocalizedError, Sendable {
  case missingCredential
  case unsupportedSamplingMode(String)
  case invalidUsage

  public var errorDescription: String? {
    switch self {
    case .missingCredential:
      "The Nebius API key is empty. Use a development key or configure a production proxy."
    case .unsupportedSamplingMode(let description):
      "Unsupported sampling mode: \(description)"
    case .invalidUsage:
      "The model provider returned inconsistent token usage. Please retry the request."
    }
  }
}
