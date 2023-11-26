//
//  Deployments.swift
//  kubernetes
//
//  Created by Nick Yang on 2/17/24.
//

import Charts
import OrderedCollections
import SwiftUI
import SwiftkubeModel
import os

extension apps.v1.Deployment: Identifiable {
  public var id: String {
    (self.metadata?.uid)!
  }
}

extension apps.v1.ReplicaSet: Identifiable {
  public var id: String {
    (self.metadata?.uid)!
  }
}

extension core.v1.Pod: Identifiable {
  public var id: String {
    (self.metadata?.uid)!
  }
}

@MainActor
class DeploymentsModel: ObservableObject {
  @Published var namespaceDeploymentMap: [String: OrderedSet<apps.v1.Deployment>] = [:]

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: NamespacesModel.self)
  )

  func load(client: ContextClient, namespace: String = "default") async throws {
    if !client.context.has_auth() {
      Self.logger.notice("Attempted to fetch deployments without auth")
      return
    }
    let kClient = client.client

    // fetch deployments for NS
    do {
      let deployments = try await kClient.appsV1.deployments.list(in: .namespace(namespace))
      var deploymentCounter = 0
      for deployment in deployments {
        let ns = deployment.metadata?.namespace ?? ""
        if ns.isEmpty {
          Self.logger.warning(
            "Ignoring \(deployment.metadata?.name ?? "") because no namespace associated with it")
          continue
        }
        namespaceDeploymentMap[ns, default: OrderedSet()].append(deployment)
        deploymentCounter += 1
      }
      Self.logger.trace("Got \(deploymentCounter) deployments in namespace \(namespace)")
    } catch {
      Self.logger.error("Failed to fetch deployments")
    }

    // cleanup
    try kClient.syncShutdown()
  }
}

struct DeploymentView: View {
  @EnvironmentObject var context: Context
  @State var namespace: String = "default"
  @State var deployment: apps.v1.Deployment

  var body: some View {
    VStack {
      // status
      HorizontalBarChartPercentage(
        resource:
          "Availability: \(deployment.status?.availableReplicas ?? 0)/\(deployment.status?.replicas ?? 0)",
        used: Quantity(integerLiteral: Int(deployment.status?.availableReplicas ?? 0)),
        total: Quantity(integerLiteral: Int(deployment.status?.replicas ?? 1))
      )
      HorizontalBarChartPercentage(
        resource: "Readiness: \(deployment.status?.readyReplicas ?? 0)",
        used: Quantity(integerLiteral: Int(deployment.status?.readyReplicas ?? 0)),
        total: Quantity(integerLiteral: Int(deployment.status?.replicas ?? 1))
      )
      HorizontalBarChartPercentage(
        resource: "Updated: \(deployment.status?.updatedReplicas ?? 0)",
        used: Quantity(integerLiteral: Int(deployment.status?.updatedReplicas ?? 0)),
        total: Quantity(integerLiteral: Int(deployment.status?.replicas ?? 1))
      )
      ReplicaSetListView(
        namespace: namespace,
        controllerName: deployment.name ?? ""
      )
      .environmentObject(context)
    }
    .navigationTitle(deployment.metadata?.name ?? "Deployment")
  }
}

struct DeploymentListView: View {
  @EnvironmentObject var context: Context
  @State var ns: String
  @ObservedObject private var deployments: DeploymentsModel = DeploymentsModel()

  var body: some View {
    List {
      ForEach(deployments.namespaceDeploymentMap[ns] ?? []) { deployment in
        NavigationLink {
          DeploymentView(
            namespace: ns,
            deployment: deployment
          )
          .environmentObject(context)
        } label: {
          Label {
            Text(deployment.metadata?.name ?? "Deployment without a name??")
          } icon: {
            if (deployment.status?.availableReplicas ?? 0) != (deployment.status?.replicas ?? 0) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            } else {
              Image(systemName: "circle.fill")
                .foregroundStyle(.green)
            }
          }
        }
      }
    }
    .navigationTitle("Deployments")
    .task {
      try? await deployments.load(client: ContextClient(context: context), namespace: ns)
    }
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Text("\(deployments.namespaceDeploymentMap[ns]?.count ?? 0) Deployments")
      }
    }
  }
}

#Preview("DeploymentView") {
  let deployment = apps.v1.Deployment(
    metadata: meta.v1.ObjectMeta(
      name: "my-deployment",
      namespace: "default"
    ),
    spec: apps.v1.DeploymentSpec(
      selector: meta.v1.LabelSelector(),
      template: core.v1.PodTemplateSpec()
    ),
    status: apps.v1.DeploymentStatus(
      availableReplicas: 0,
      readyReplicas: 1,
      replicas: 2,
      unavailableReplicas: 1,
      updatedReplicas: 1
    )
  )
  return NavigationStack {
    DeploymentView(
      namespace: "default",
      deployment: deployment
    )
  }.environmentObject(
    Context(name: "test", url: URL(string: "http://example.com")!, namespace: "default"))
}
