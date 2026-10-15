// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Authentication sent by the Foundation Models adapter.
public enum NebiusAuth: Hashable, Sendable {
  /// Suitable for local development and simulators. Never ship an API key in
  /// an app bundle: it can be extracted by anyone who downloads the app.
  // Annotate the call site only; proxy-only clients produce no warning.
  #if NEBIUS_RELEASE_BUILD
    @available(
      *, deprecated,
      message:
        "Release build: direct Nebius API-key authentication. Never embed a provider key in a distributed app; use .proxied with your backend. User-supplied keys remain supported."
    )
  #endif
  case apiKey(String)

  /// Routes through a developer-controlled relay that injects the real Nebius
  /// credential. Headers can authorize the app or end user with that relay.
  case proxied(headers: [String: String])
}
