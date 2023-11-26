//
//  Namespaces.swift
//  kubernetes
//
//  Created by Nick Yang on 2/6/24.
//

import Charts
import Foundation
import OrderedCollections
import SwiftUI
import SwiftkubeModel
import os

extension core.v1.Namespace: Identifiable {
  public var id: String {
    (self.metadata?.uid)!
  }
}

@MainActor
class NamespacesModel: ObservableObject {
  @Published var namespaces: OrderedSet<core.v1.Namespace> = OrderedSet()
  @Published var quotas: [String: core.v1.ResourceQuotaStatus] = [:]

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: NamespacesModel.self)
  )

  func load(client: ContextClient) async throws {
    if !client.context.has_auth() {
      Self.logger.notice("Attempted to fetch namespaces without auth")
      return
    }
    let kClient = client.client

    // enumerate namespaces
    do {
      let namespaces = try await kClient.namespaces.list()
      self.namespaces.append(contentsOf: namespaces)
      Self.logger.trace("Got namespaces")
    } catch {
      Self.logger.error("Failed to list namespaces")
    }

    // enumerate resource quotas for the namespaces
    do {
      let quotas = try await kClient.resourceQuotas.list(in: .allNamespaces)
      for quota in quotas {
        // we can't assign this resource quota to a namespace if it doesn't have one
        if quota.metadata?.namespace ?? nil == nil {
          continue
        }
        self.quotas[quota.metadata!.namespace!] = quota.status
        Self.logger.trace("Got resource quota for namespace \(quota.metadata!.namespace!)")
      }
      Self.logger.trace("Got resource quotas")
    } catch {
      Self.logger.error("Failed to fetch resource quotas")
    }

    // cleanup
    try kClient.syncShutdown()
  }
}

struct ResourceQuotaView: View {
  @State var quotaStatus: core.v1.ResourceQuotaStatus
  @State private var resourceUsedTotalMap: [String: (Quantity, Quantity)] = [:]

  var body: some View {
    VStack {
      ForEach(Array(resourceUsedTotalMap.keys).sorted(by: { $0 < $1 }), id: \.self) { resource in
        HorizontalBarChartPercentage(
          resource: resource,
          used: resourceUsedTotalMap[resource]?.0 ?? Quantity(integerLiteral: 0),
          total: resourceUsedTotalMap[resource]?.1 ?? Quantity(integerLiteral: 0)
        )
      }
    }
    .onAppear {
      for (resource, used) in quotaStatus.used ?? [:] {
        resourceUsedTotalMap[resource] = (
          used, quotaStatus.hard?[resource] ?? Quantity(integerLiteral: 0)
        )
      }
    }
  }
}

struct NamespaceView: View {
  @EnvironmentObject var context: Context
  @State var namespace: core.v1.Namespace
  @State var quotaStatus: core.v1.ResourceQuotaStatus?

  var body: some View {
    List {
      // deployments, pods, etc.
      if quotaStatus != nil {
        Section("Resource Quotas") {
          ResourceQuotaView(quotaStatus: quotaStatus!)
            .environmentObject(context)
        }
      }
      NavigationLink {
        DeploymentListView(ns: namespace.metadata?.name ?? "")
          .environmentObject(context)
      } label: {
        Text("Deployments")
      }
    }.navigationTitle(namespace.metadata?.name ?? "Unknown namespace")
  }
}

struct NamespaceListView: View {
  @EnvironmentObject var context: Context
  @StateObject private var namespaces: NamespacesModel = NamespacesModel()

  var body: some View {
    List {
      ForEach(namespaces.namespaces) { ns in
        NavigationLink {
          NamespaceView(
            namespace: ns,
            quotaStatus: namespaces.quotas[ns.name ?? ""]
          )
          .environmentObject(context)
        } label: {
          Text(ns.metadata?.name ?? "??")
        }
      }
    }
    .navigationTitle("Namespaces")
    .task {
      try? await namespaces.load(client: ContextClient(context: context))
    }
    .refreshable {
      try? await namespaces.load(client: ContextClient(context: context))
    }
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Text("\(namespaces.namespaces.count) Namespaces")
      }
    }
  }
}

#Preview("NamespaceView") {
  let namespace = core.v1.Namespace(
    metadata: meta.v1.ObjectMeta(name: "default")
  )
  let quota = core.v1.ResourceQuotaStatus(
    hard: [
      "cpu": Quantity(integerLiteral: 1),
      "memory": Quantity("1Gi"),
      "ephemeral-storage": Quantity("5Gi"),
    ],
    used: [
      "cpu": Quantity("500m"),
      "memory": Quantity("0"),
      "ephemeral-storage": Quantity("375Mi"),
    ]
  )
  return NamespaceView(namespace: namespace, quotaStatus: quota)
}

#Preview("QuotaStatusView") {
  let quota = core.v1.ResourceQuotaStatus(
    hard: [
      "cpu": Quantity(integerLiteral: 1),
      "memory": Quantity("1Gi"),
      "ephemeral-storage": Quantity("5Gi"),
    ],
    used: [
      "cpu": Quantity("500m"),
      "memory": Quantity("0"),
      "ephemeral-storage": Quantity("375Mi"),
    ]
  )
  return ResourceQuotaView(quotaStatus: quota)
}
