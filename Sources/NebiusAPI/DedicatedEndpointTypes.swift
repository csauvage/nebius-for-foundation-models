// Copyright 2026 BNC Consulting
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct EndpointScaling: Codable, Equatable, Sendable {
  public var minReplicas: Int
  public var maxReplicas: Int
  public init(minReplicas: Int, maxReplicas: Int) {
    self.minReplicas = minReplicas
    self.maxReplicas = maxReplicas
  }
  public var isValid: Bool { minReplicas >= 1 && maxReplicas >= minReplicas }
}

public struct EndpointDeployment: Codable, Equatable, Sendable {
  public let readyReplicas: Int
  // Strings preserve new server states without making the whole list undecodable.
  public let status: String
  public let readiness: String
  public init(readyReplicas: Int, status: String, readiness: String) {
    self.readyReplicas = readyReplicas
    self.status = status
    self.readiness = readiness
  }
}

public struct DedicatedEndpoint: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let description: String
  public let enabled: Bool
  public let routingKey: String
  public let modelName: String
  public let flavorName: String
  public let region: String
  public let gpuType: String
  public let gpuCount: Int
  public let scaling: EndpointScaling
  public let deployment: EndpointDeployment
  public let createdAt: String

  public init(
    id: String, name: String, description: String, enabled: Bool, routingKey: String,
    modelName: String, flavorName: String, region: String, gpuType: String, gpuCount: Int,
    scaling: EndpointScaling, deployment: EndpointDeployment, createdAt: String
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.enabled = enabled
    self.routingKey = routingKey
    self.modelName = modelName
    self.flavorName = flavorName
    self.region = region
    self.gpuType = gpuType
    self.gpuCount = gpuCount
    self.scaling = scaling
    self.deployment = deployment
    self.createdAt = createdAt
  }
}

public struct DedicatedEndpointTemplate: Codable, Equatable, Sendable, Identifiable {
  public let name: String
  public let type: String
  public let metadata: JSONValue
  public let flavors: [String: EndpointFlavor]
  public var id: String { name }
}

public struct EndpointFlavor: Codable, Equatable, Sendable {
  public let availableConfigurations: EndpointConfigurations
}

public struct EndpointConfigurations: Codable, Equatable, Sendable {
  public let gpuConfigurations: [String: EndpointGPUConfiguration]
}

public struct EndpointGPUConfiguration: Codable, Equatable, Sendable {
  public let allowedRegions: [String]
  public let allowedGpuCounts: [Int]
  public let maxReplicasAllowed: Int
}

public struct DedicatedEndpointCreateRequest: Encodable, Equatable, Sendable {
  public var name: String
  public var description: String
  public let modelName: String
  public let flavorName: String
  public let gpuType: String
  public let region: String
  public let gpuCount: Int
  public var scaling: EndpointScaling

  public init(
    name: String, description: String = "", modelName: String, flavorName: String,
    gpuType: String, region: String, gpuCount: Int, scaling: EndpointScaling
  ) {
    self.name = name
    self.description = description
    self.modelName = modelName
    self.flavorName = flavorName
    self.gpuType = gpuType
    self.region = region
    self.gpuCount = gpuCount
    self.scaling = scaling
  }

  public func isSupported(by templates: [DedicatedEndpointTemplate]) -> Bool {
    guard
      let config = templates.first(where: { $0.name == modelName })?
        .flavors[flavorName]?.availableConfigurations.gpuConfigurations[gpuType]
    else { return false }
    return config.allowedRegions.contains(region) && config.allowedGpuCounts.contains(gpuCount)
      && scaling.isValid && scaling.maxReplicas <= config.maxReplicasAllowed
  }
}

/// Nil fields are omitted from PATCH. Region and model cannot be changed here.
public struct DedicatedEndpointUpdateRequest: Encodable, Equatable, Sendable {
  public var name: String?
  public var description: String?
  public var enabled: Bool?
  public var scaling: EndpointScaling?

  public init(
    name: String? = nil, description: String? = nil, enabled: Bool? = nil,
    scaling: EndpointScaling? = nil
  ) {
    self.name = name
    self.description = description
    self.enabled = enabled
    self.scaling = scaling
  }
}

public enum DedicatedEndpointAPIError: Error, Sendable {
  case directAPIKeyRequired
  case invalidRequest
  case invalidResponse
  case httpError(statusCode: Int, detail: JSONValue?)
}
