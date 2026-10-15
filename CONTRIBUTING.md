# Contributing

This package tracks three moving surfaces: Apple's Foundation Models protocols, Nebius Token Factory's OpenAI-compatible API, and Tavily's retrieval and research APIs.

Before opening a pull request:

1. Run `swift run NebiusAPITests`.
2. Run `swift run TavilyAPITests`.
3. Build the package with the latest Xcode 27 beta or release.
   Run `swift test --filter StreamingUsageTests` on macOS 27 for executor changes.
4. Test text streaming, structured output and tool calling against a currently available Token Factory model.
5. For Tavily changes, test only the affected endpoint with a development account and verify cost, cancellation, response limits, and error handling.
6. Never commit API keys, prompts from real users, retrieved private content, or production response payloads.

The GitHub Actions workflow runs both protocol suites and verifies the committed model catalog snapshot. Before a release, also run the executor suite with Xcode 27 and macOS 27; the protocol CI job alone does not validate the OS 27 adapter.

Nebius Chat and its app-specific tests are maintained separately and excluded from the public repository. If both `Examples/NebiusChat/App` and `Tests/NebiusChatTests` exist locally, SwiftPM also enables their targets; run `swift run NebiusChatTests` when changing shared app behavior. A clean package checkout does not require these directories.

Tavily request and response types should follow the official OpenAPI document. Keep model-controlled tool arguments small; spending controls, domain restrictions, crawl limits, and output limits belong in application-owned configuration. Add credential-free fixtures for every new field or event shape.

Model constants should only be added when their ID and capabilities have been checked against `GET /v1/models?verbose=true`. Prefer custom model construction over speculative constants.
