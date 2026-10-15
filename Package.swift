// swift-tools-version: 6.2
import Foundation
import PackageDescription

let package = Package(
  name: "NebiusForFoundationModels",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .visionOS(.v1),
    .watchOS(.v10),
  ],
  products: [
    .library(
      name: "NebiusForFoundationModels",
      targets: ["NebiusForFoundationModels"]
    ),
    .library(name: "TavilyAPI", targets: ["TavilyAPI"]),
    .library(
      name: "TavilyForFoundationModels",
      targets: ["TavilyForFoundationModels"]
    ),
  ],
  targets: [
    // Kept independent from FoundationModels so the HTTP protocol can be
    // tested with stable SDKs while Apple's server-side API is in beta.
    .target(
      name: "NebiusAPI",
      swiftSettings: [.define("NEBIUS_RELEASE_BUILD", .when(configuration: .release))]
    ),
    .target(
      name: "NebiusForFoundationModels",
      dependencies: ["NebiusAPI"],
      swiftSettings: [.define("NEBIUS_RELEASE_BUILD", .when(configuration: .release))]
    ),
    // Tavily's REST client remains independent from FoundationModels so every
    // endpoint can be tested without a recent Apple SDK or live credentials.
    .target(
      name: "TavilyAPI",
      swiftSettings: [.define("NEBIUS_RELEASE_BUILD", .when(configuration: .release))]
    ),
    .target(
      name: "TavilyForFoundationModels",
      dependencies: ["TavilyAPI"]
    ),
    .executableTarget(
      name: "NebiusExample",
      dependencies: ["NebiusForFoundationModels"],
      path: "Examples/NebiusExample"
    ),
    .executableTarget(
      name: "TavilyExample",
      dependencies: ["NebiusForFoundationModels", "TavilyForFoundationModels"],
      path: "Examples/TavilyExample"
    ),
    .executableTarget(
      name: "NebiusAPITests",
      dependencies: ["NebiusAPI", "NebiusForFoundationModels"],
      path: "Tests/NebiusAPITests"
    ),
    .testTarget(
      name: "NebiusExecutorTests",
      dependencies: ["NebiusAPI", "NebiusForFoundationModels"]
    ),
    .executableTarget(
      name: "TavilyAPITests",
      dependencies: ["TavilyAPI", "TavilyForFoundationModels"],
      path: "Tests/TavilyAPITests"
    ),
    .executableTarget(
      name: "UpdateNebiusModelCatalog",
      path: "Tools/UpdateNebiusModelCatalog"
    ),
  ],
  swiftLanguageModes: [.v6]
)

// Nebius Chat is maintained locally and excluded from the public package.
// Keep its test harness available when both local source directories exist.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
if FileManager.default.fileExists(
  atPath: packageDirectory.appendingPathComponent("Examples/NebiusChat/App").path
), FileManager.default.fileExists(
  atPath: packageDirectory.appendingPathComponent("Tests/NebiusChatTests").path
) {
  package.targets += [
    // Shared demo state is tested without UI, credentials, or the OS 27 runtime.
    .target(
      name: "NebiusChatCore",
      dependencies: ["NebiusAPI", "NebiusForFoundationModels", "TavilyForFoundationModels"],
      path: "Examples/NebiusChat/App",
      exclude: [
        "NebiusChatApp.swift", "Composition", "DesignTokens", "Views",
        "Extensions/Color+Hex.swift", "Extensions/Color+Adaptive.swift",
        "Services/FoundationModelsChatService.swift", "Services/SponsoredAccessManager.swift",
        "ViewModels/AppViewModel.swift",
        "Info.plist", "NebiusChat.entitlements", "NebiusChat-macOS.entitlements", "Icon.icon",
        "Assets.xcassets", "Resources",
      ]
    ),
    .executableTarget(
      name: "NebiusChatTests",
      dependencies: ["NebiusChatCore", "NebiusForFoundationModels", "TavilyForFoundationModels"],
      path: "Tests/NebiusChatTests"
    ),
  ]
}
