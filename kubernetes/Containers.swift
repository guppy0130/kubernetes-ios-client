//
//  Containers.swift
//  kubernetes
//
//  Created by Nick Yang on 5/5/24.
//

import SwiftUI
import SwiftkubeModel

struct ContainerView: View {
  @State var expanded: Bool = false
  @State var container: core.v1.ContainerStatus

  var body: some View {
    InfoPanel(expanded: $expanded) {
      Text(container.image)
    } header: {
      Label {
        Text(container.name)
      } icon: {
        if container.state?.running != nil {
          Image(systemName: "circle.fill").foregroundStyle(.green)
        } else if container.state?.waiting != nil {
          Image(systemName: "timer").foregroundStyle(.blue)
        } else if container.state?.terminated != nil {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
      }
    } leftTimer: {
      if container.state?.running?.startedAt != nil {
        // ok to lie to the user in the default case right!
        Text("Started")
        Text((container.state?.running?.startedAt)!, style: .relative)
      } else if container.state?.waiting != nil {
        Text("Waiting")
        Text(container.state?.waiting?.message ?? "")
      } else if container.state?.terminated != nil {
        Text("Terminated")
        Text(container.state?.terminated?.message ?? "")
      }
    } rightTimer: {
      Section("Restart Count") {
        Text(String(container.restartCount))
      }
    }
    .onAppear {
      expanded = !container.ready
    }
  }
}

#Preview {
  let container = core.v1.ContainerStatus(
    image: "image",
    imageID: "image-id",
    name: "container-1-name",
    ready: true,
    restartCount: 3,
    state: core.v1.ContainerState(
      running: core.v1.ContainerStateRunning(startedAt: Date())
    )
  )
  return NavigationStack {
    ContainerView(container: container)
  }
}
