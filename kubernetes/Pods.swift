//
//  Pods.swift
//  kubernetes
//
//  Created by Nick Yang on 2/18/24.
//

import OrderedCollections
import SwiftUI
import SwiftkubeClient
import SwiftkubeModel
import os

@MainActor
class PodsModel: ObservableObject {
  @Published var pods: OrderedSet<core.v1.Pod> = OrderedSet()

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
    // fetch pods
    do {
      let pods = try await kClient.pods.list(
        in: .namespace(namespace)
      )
      for pod in pods {
        if controllerName.isEmpty {
          self.pods.append(pod)
          continue
        }
        for ownerRef in pod.metadata?.ownerReferences ?? [] {
          if ownerRef.name == controllerName {
            self.pods.append(pod)
            break
          }
        }
      }
    } catch {
      Self.logger.error("Failed to fetch pods")
    }
    try kClient.syncShutdown()
  }
}

struct PodView: View {
  @State var pod: core.v1.Pod

  var body: some View {
    VStack {
      Text(
        "\(pod.status?.phase ?? "Unknown")"
          + (pod.status?.reason != nil ? " (\(pod.status?.reason ?? "Unknown")" : ""))
      if pod.status?.message != nil {
        Text((pod.status?.message)!)
      }
      List {
        Section("Containers") {
          ForEach(self.pod.status?.containerStatuses ?? [], id: \.name) { container in
            ContainerView(container: container)
          }
        }
      }
    }
    .navigationTitle(pod.name ?? "Unknown pod")
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Text("\(pod.status?.containerStatuses?.count ?? 0) containers")
      }
    }
  }
}

struct PodListView: View {
  @EnvironmentObject var context: Context
  @State var namespace: String = "default"
  @State var controllerName: String = ""
  @ObservedObject var podsModel: PodsModel = PodsModel()

  var body: some View {
    Section("Pods") {
      List {
        ForEach(self.podsModel.pods) { pod in
          NavigationLink {
            PodView(pod: pod)
          } label: {
            Text(pod.name ?? "Unknown pod name")
          }
        }
      }
    }
    .task {
      try? await self.podsModel.load(
        client: ContextClient(context: context),
        namespace: namespace,
        controllerName: controllerName
      )
    }
  }
}

#Preview {
  let pod = core.v1.Pod(
    metadata: meta.v1.ObjectMeta(
      name: "my-pod-9999"
    ),
    status: core.v1.PodStatus(
      containerStatuses: [
        core.v1.ContainerStatus(
          image: "image",
          imageID: "image-id",
          name: "container-1-name",
          ready: true,
          restartCount: 3,
          state: core.v1.ContainerState(
            running: core.v1.ContainerStateRunning(startedAt: Date())
          )
        ),
        core.v1.ContainerStatus(
          image: "image2",
          imageID: "image-id-2",
          name: "container-2-name",
          ready: false,
          restartCount: 4,
          state: core.v1.ContainerState(
            waiting: core.v1.ContainerStateWaiting(
              message: "Unable to connect",
              reason: "ImagePullBackOff"
            )
          )
        ),
        core.v1.ContainerStatus(
          image: "image3",
          imageID: "image-id-3",
          name: "container-3-name",
          ready: false,
          restartCount: 5,
          state: core.v1.ContainerState(
            terminated: core.v1.ContainerStateTerminated(
              exitCode: 1,
              finishedAt: Date(),
              message: "Out of memory",
              reason: "OOMKilled",
              signal: 137,
              startedAt: Date(timeIntervalSinceNow: TimeInterval(60))
            )
          )
        ),
      ],
      phase: "Ready"
    )
  )
  return NavigationStack {
    PodView(pod: pod)
  }
}
