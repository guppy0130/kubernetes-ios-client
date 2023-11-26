//
//  ReplicaSets.swift
//  kubernetes
//
//  Created by Nick Yang on 2/18/24.
//

import OrderedCollections
import SwiftUI
import SwiftkubeModel
import os

@MainActor
class ReplicaSetsModel: ObservableObject {
  @Published var replicaSets: OrderedSet<apps.v1.ReplicaSet> = OrderedSet()
  @Published var replicasetPodMap: [String: OrderedSet<core.v1.Pod>] = [:]

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: NamespacesModel.self)
  )

  func load(client: ContextClient, namespace: String = "default", controllerName: String = "")
    async throws
  {
    if !client.context.has_auth() {
      Self.logger.notice("Attempted to fetch deployments without auth")
      return
    }
    let kClient = client.client
    // fetch rs for NS
    do {
      let replicasets = try await kClient.appsV1.replicaSets.list(in: .namespace(namespace))
      for replicaset in replicasets {
        if controllerName.isEmpty {
          self.replicaSets.append(replicaset)
          continue
        }
        for ownerRef in replicaset.metadata?.ownerReferences ?? [] {
          if ownerRef.name == controllerName {
            self.replicaSets.append(replicaset)
            break
          }
        }
      }
      Self.logger.trace("Got \(self.replicaSets.count) replicasets in namespace \(namespace)")
    } catch {
      Self.logger.error("Failed to fetch replicasets")
    }

    // cleanup
    try kClient.syncShutdown()
  }
}

struct ReplicaSetView: View {
  @State var replicaSet: apps.v1.ReplicaSet

  var body: some View {
    VStack {
      // healthy pod count
      Section("ReplicaSet Status") {
        HorizontalBarChartPercentage(
          resource: "Available Pods",
          used: Quantity(integerLiteral: Int(replicaSet.status?.availableReplicas ?? 0)),
          total: Quantity(integerLiteral: Int(replicaSet.status?.replicas ?? 1))
        )
      }
      // pod list?
      PodListView(
        namespace: replicaSet.metadata?.namespace ?? "default",
        controllerName: replicaSet.name ?? ""
      )
    }
    .navigationTitle(replicaSet.name ?? "Unknown Replicaset")
  }
}

struct ReplicaSetListView: View {
  @EnvironmentObject var context: Context
  @State var namespace: String = "default"
  @State var controllerName: String = ""
  @ObservedObject var replicaSetsModel: ReplicaSetsModel = ReplicaSetsModel()

  var body: some View {
    Section("ReplicaSets") {
      List {
        ForEach(replicaSetsModel.replicaSets) { replicaset in
          NavigationLink {
            ReplicaSetView(replicaSet: replicaset)
              .environmentObject(context)
          } label: {
            Label {
              Text(replicaset.metadata?.name ?? "Unknown replicaset")
            } icon: {
              if (replicaset.status?.availableReplicas ?? 0) == (replicaset.status?.replicas ?? 0) {
                Image(systemName: "circle.fill").foregroundStyle(.green)
              } else {
                Image(systemName: "exclamation.triangle.fill").foregroundStyle(.orange)
              }
            }
          }
        }
      }
    }
    .task {
      try? await replicaSetsModel.load(
        client: ContextClient(context: context),
        namespace: namespace,
        controllerName: controllerName
      )
    }
  }
}

#Preview("ReplicaSet") {
  let replicaSet = apps.v1.ReplicaSet(
    metadata: meta.v1.ObjectMeta(
      name: "my-replicaset-1",
      uid: "todo"
    ),
    spec: apps.v1.ReplicaSetSpec(
      selector: meta.v1.LabelSelector()
    ),
    status: apps.v1.ReplicaSetStatus(
      availableReplicas: 1,
      replicas: 1
    )
  )
  return NavigationStack {
    ReplicaSetView(replicaSet: replicaSet)
      .navigationTitle("ReplicaSets")
      .environment(
        Context(name: "default", url: URL(string: "https://example.com")!, namespace: "default"))
  }
}

#Preview("ReplicaSetListView") {
  return NavigationStack {
    ReplicaSetListView()
      .navigationTitle("ReplicaSetListView")
      .environment(
        Context(name: "default", url: URL(string: "https://example.com")!, namespace: "default"))
  }
}
