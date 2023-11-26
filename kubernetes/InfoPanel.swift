//
//  InfoPanel.swift
//  kubernetes
//
//  Created by Nick Yang on 2/10/24.
//

import SwiftUI

struct InfoPanel<Header: View, Content: View, LeftTimer: View, RightTimer: View>: View {
  @Binding var expanded: Bool
  @ViewBuilder var content: () -> Content
  @ViewBuilder var header: () -> Header
  @ViewBuilder var leftTimer: () -> LeftTimer
  @ViewBuilder var rightTimer: () -> RightTimer

  var body: some View {
    Section(isExpanded: $expanded) {
      VStack(alignment: .leading) {
        content()
        HStack(alignment: .bottom) {
          VStack {
            leftTimer().frame(maxWidth: .infinity, alignment: .leading)
          }
          // .border(Color.red)
          VStack {
            rightTimer().frame(maxWidth: .infinity, alignment: .trailing)
          }
          // .border(Color.green)
        }
        .frame(maxWidth: .infinity)
        // .border(Color.yellow)
      }
    } header: {
      HStack {
        header()
        // not quite right
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity)
    .onTapGesture {
      expanded = !expanded
    }
    // .border(Color.black)
  }
}

#Preview {
  let b = Binding(get: { return true }, set: { _, _ in })
  return InfoPanel(expanded: b) {
    Text("Content")
  } header: {
    Text("Header")
  } leftTimer: {
    Text("Left")
    Text("More left")
  } rightTimer: {
    Text("Right")
  }
}
