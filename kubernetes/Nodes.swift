//
//  Nodes.swift
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

extension core.v1.Node: Identifiable {
  public var id: String {
    (self.metadata?.uid)!
  }
}

@MainActor
class NodeModel: ObservableObject {
  @Published var nodes: OrderedSet<core.v1.Node> = OrderedSet()
  @Published var events: [core.v1.Node: OrderedSet<core.v1.Event>] = [:]

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: NamespacesModel.self)
  )

  func load(client: ContextClient) async throws {
    if !client.context.has_auth() {
      Self.logger.notice("Attempted to fetch nodes without auth")
      return
    }
    let kClient = client.client
    self.nodes = []

    // get list of nodes
    do {
      let nodes = try await kClient.nodes.list()
      self.nodes.append(contentsOf: nodes)
      Self.logger.trace("Got nodes")
    } catch {
      Self.logger.error("Unable to get nodes: \(error)")
    }

    // get events for the nodes
    // https://github.com/swiftkube/model/issues/11
    do {
      let events = try await kClient.events.list()
      for e in events {
        for node in self.nodes {
          if e.involvedObject.kind == "Node" && e.involvedObject.name == node.name {
            self.events[node, default: OrderedSet()].append(e)
          }
        }
      }
      Self.logger.trace("Got events")
    } catch {
      Self.logger.error("Unable to get node events: \(error)")
    }
    try kClient.syncShutdown()
  }
}

// this is pretty suspicious, but it should be sufficient on a per-node instance
extension core.v1.NodeCondition: Identifiable {
  public var id: String {
    self.type
  }
}

extension core.v1.NodeCondition {
  public func desirableState() -> Bool {
    switch self.type {
    case "MemoryPressure", "DiskPressure", "PIDPressure", "NetworkUnavailable":
      return self.status == "False"
    case "Ready":
      return self.status == "True"
    default:
      // suspect
      return true
    }
  }
}

// assuming keys are unique per node
extension core.v1.Taint: Identifiable {
  public var id: String {
    // node.kubernetes.io/unreachable:{NoExecute,NoSchedule}
    self.key + self.effect
  }
}

extension core.v1.Event: Identifiable {
  public var id: String {
    self.metadata.uid!
  }
}

struct NodeConditionView: View {
  @State var condition: core.v1.NodeCondition
  @State var expanded: Bool = false

  var body: some View {
    InfoPanel(expanded: $expanded) {
      Text(condition.message ?? "")
    } header: {
      Label {
        Text(condition.type)
      } icon: {
        Image(
          systemName: condition.desirableState() ? "circle.fill" : "exclamationmark.triangle.fill"
        ).foregroundStyle(condition.desirableState() ? Color.green : Color.red)
      }
    } leftTimer: {
      Section("Last Heartbeat") {
        Text(condition.lastHeartbeatTime ?? Date(timeIntervalSince1970: 0), style: .relative)
      }
    } rightTimer: {
      Section("Last Transition") {
        Text(condition.lastTransitionTime ?? Date(timeIntervalSince1970: 0), style: .relative)
      }
    }
    .onAppear {
      expanded = !condition.desirableState()
    }
  }
}

struct EventView: View {
  @State var event: core.v1.Event
  @State var expanded: Bool = false

  var body: some View {
    InfoPanel(expanded: $expanded) {
      Text(event.message ?? "No message from cluster")
    } header: {
      Label {
        Text(event.reason ?? "")
      } icon: {
        Image(systemName: event.type == "Warning" ? "exclamationmark.triangle.fill" : "circle.fill")
          .foregroundStyle(event.type == "Warning" ? Color.orange : Color.green)
      }
    } leftTimer: {
      Section("First seen") {
        Text(event.firstTimestamp ?? Date(timeIntervalSince1970: 0), style: .relative)
      }
    } rightTimer: {
      Section("Last seen") {
        Text(event.lastTimestamp ?? Date(timeIntervalSince1970: 0), style: .relative)
      }
    }
    .onAppear {
      expanded = event.type == "Warning"
    }
  }
}

struct TaintView: View {
  @State var taint: core.v1.Taint
  @State var expanded: Bool = false
  @State var color: Color = Color.red
  @State var helperText: String = ""

  var body: some View {
    InfoPanel(expanded: $expanded) {
      // if the value is true then that's useless; omit it
      Text(helperText)
      if taint.value != nil && taint.value != "true" {
        Text("Value: \(taint.value!)")
      }
    } header: {
      Label {
        Text("\(taint.key) (\(taint.effect))")
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(color)
      }
    } leftTimer: {
      if taint.timeAdded != nil {
        Section("Added") {
          Text(taint.timeAdded!, style: .relative)
        }
      } else {
        EmptyView()
      }
    } rightTimer: {
      EmptyView()
    }
    .onAppear {
      expanded = (taint.value != nil && taint.value != "true") || taint.timeAdded != nil
      switch taint.effect {
      case "NoExecute":
        do {
          color = Color.red
          helperText = "Pods will be evicted from this node unless tolerated"
        }
      case "NoSchedule":
        do {
          color = Color.orange
          helperText = "No new pods will be scheduled on this node"
        }
      case "PreferNoSchedule":
        do {
          color = Color.yellow
          helperText = "Pods will avoid getting scheduled on this node"
        }
      default: color = Color.yellow
      }
    }
  }
}

struct chartFormattedData: Identifiable {
  var name: String
  var capacity: Quantity

  public var id: String {
    return self.name
  }
}

struct ResourceView: View {
  @State var capacity: [String: Quantity]
  @State var allocatable: [String: Quantity]
  @State private var resourceFreeMap: [String: (Quantity, Quantity)] = [:]

  var body: some View {
    VStack {
      // sort the keys in alpha order so it's consistent
      ForEach(Array(resourceFreeMap.keys).sorted(by: { $0 < $1 }), id: \.self) { resource in
        HorizontalBarChartPercentage(
          resource: resource,
          free: resourceFreeMap[resource]?.0 ?? Quantity(integerLiteral: 0),
          total: resourceFreeMap[resource]?.1 ?? Quantity(integerLiteral: 1)
        )
      }
    }
    .onAppear {
      for (name, cap) in capacity {
        // don't parse resources without capacity
        if cap.getValue() ?? 0 == 0 {
          continue
        }
        resourceFreeMap[name] = (allocatable[name] ?? Quantity(integerLiteral: 0), cap)
      }
    }
  }
}

struct NodeView: View {
  @State var node: core.v1.Node
  @State var events: OrderedSet<core.v1.Event>

  var body: some View {
    List {
      if node.status != nil && node.status?.capacity != nil {
        Section("Resources") {
          ResourceView(
            capacity: node.status!.capacity ?? Dictionary(),
            allocatable: node.status!.allocatable ?? Dictionary()
          )
        }
      }
      Section("Status") {
        ForEach(node.status?.conditions ?? []) { c in
          NodeConditionView(condition: c)
        }
      }
      if node.spec?.taints?.count ?? 0 > 0 {
        Section("Taints") {
          ForEach(node.spec?.taints ?? []) { taint in
            TaintView(taint: taint)
          }
        }
      }
      if events.count > 0 {
        Section("Events") {
          ForEach(events) { event in
            EventView(event: event)
          }
        }
      }
    }.navigationTitle(node.metadata?.name ?? "Unknown kubelet name")
  }
}

struct NodeListView: View {
  @EnvironmentObject var context: Context
  @StateObject private var nodes: NodeModel = NodeModel()
  @State private var node_ready_hashmap: [String: Bool] = Dictionary()

  var body: some View {
    List {
      ForEach(nodes.nodes) { node in
        NavigationLink {
          NodeView(node: node, events: nodes.events[node] ?? [])
        } label: {
          Label {
            Text(node.name ?? "Unknown node name")
          } icon: {
            if node_ready_hashmap[node.name!] ?? false {
              Image(systemName: "circle.fill").foregroundStyle(Color.green)
            } else {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            }
          }
        }
      }
    }
    .navigationTitle("Nodes")
    .task {
      try? await nodes.load(client: ContextClient(context: context))
      for node in nodes.nodes {
        for condition in node.status?.conditions ?? [] {
          if condition.type == "Ready" {
            node_ready_hashmap[node.name!] = condition.status == "True"
          }
        }
      }
    }
    .refreshable {
      try? await nodes.load(client: ContextClient(context: context))
      for node in nodes.nodes {
        for condition in node.status?.conditions ?? [] {
          if condition.type == "Ready" {
            node_ready_hashmap[node.name!] = condition.status == "True"
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Text("\(nodes.nodes.count) Nodes")
      }
    }
  }
}

#Preview("NodeView") {
  let condition = core.v1.NodeCondition(
    lastHeartbeatTime: Date(),
    lastTransitionTime: Date(),
    message: "kubelet has disk pressure",
    reason: "KubeletHasDiskPressure",
    status: "True",
    type: "DiskPressure"
  )
  let capacity = [
    "cpu": Quantity(6),
    "hugepages-2Mi": Quantity(0),
    "hugepages-1Gi": Quantity(0),
    "ephemeral-storage": Quantity("11218472Ki"),
    "memory": Quantity("10173648Ki"),
    "pods": Quantity(110),
  ]
  let allocatable = [
    "cpu": Quantity(6),
    "hugepages-2Mi": Quantity(0),
    "hugepages-1Gi": Quantity(0),
    "ephemeral-storage": Quantity(10_913_329_554),
    "memory": Quantity("10173648Ki"),
    "pods": Quantity(110),
  ]
  let node = core.v1.Node(
    metadata: meta.v1.ObjectMeta(name: "kubelet-1"),
    spec: core.v1.NodeSpec(
      taints: [
        core.v1.Taint(
          effect: "NoSchedule",
          key: "node.kubernetes.io/disk-pressure"
        )
      ]
    ),
    status: core.v1.NodeStatus(
      allocatable: allocatable,
      capacity: capacity,
      conditions: [condition]
    )
  )
  var events = OrderedSet<core.v1.Event>()
  events.append(
    core.v1.Event(
      metadata: meta.v1.ObjectMeta(name: "kubelet-1.hash", uid: UUID().uuidString),
      involvedObject: core.v1.ObjectReference(name: "kubelet-1"),
      reason: "FreeDiskSpaceFailed",
      type: "Warning"
    )
  )
  return NodeView(node: node, events: events)
}

#Preview("Condition") {
  let condition = core.v1.NodeCondition(
    lastHeartbeatTime: Date(),
    lastTransitionTime: Date(),
    message: "kubelet has disk pressure",
    reason: "KubeletHasDiskPressure",
    status: "True",
    type: "DiskPressure"
  )
  return NodeConditionView(condition: condition)
}
