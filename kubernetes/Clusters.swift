//
//  ContentView.swift
//  kubernetes
//
//  Created by Nick Yang on 11/25/23.
//

//import Charts
import NIOSSL
import SwiftData
import SwiftUI
import SwiftkubeClient
import SwiftkubeModel
import os

extension meta.v1.ObjectMeta: @retroactive Identifiable {
  public var id: String? {
    self.uid
  }
}

/// the contextview gives you a view into the context (cluster + namespace) resources
struct ContextView: View {
  @State var context: Context

  var body: some View {
    VStack {
      NavigationLink {
        ContextCertDetails(kubeConfig: context)
      } label: {
        Text("Connection details").frame(maxWidth: .infinity)
      }.buttonStyle(.bordered)
      Spacer()
      Divider()
      List {
        // namespaces
        NavigationLink {
          NamespaceListView().environmentObject(context)
        } label: {
          Text("Namespaces")
        }
        NavigationLink {
          NodeListView().environmentObject(context)
        } label: {
          Text("Nodes")
        }
      }
    }
    .navigationTitle(context.name)
  }
}

struct ContextListView: View {
  @Environment(\.editMode) private var editMode
  @Environment(\.modelContext) private var modelContext
  @Query var contexts: [Context]

  var body: some View {
    VStack {
      List {
        ForEach(contexts) { context in
          NavigationLink {
            ContextView(context: context)
          } label: {
            Text(context.name)
          }
        }.onDelete(perform: { indexSet in
          deleteContext(at: indexSet)
        })
        // TODO: implement rearrange
      }
    }
    .navigationTitle("Contexts")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        EditButton()
      }
      // forcing the button to be bottom trailing
      ToolbarItem(placement: .bottomBar) {
        Spacer()
      }
      ToolbarItem(placement: .bottomBar) {
        Button(action: {
          let k = Context(
            name: "new context",
            url: URL(string: "https://example.com")!
          )
          modelContext.insert(k)
        }) {
          Label("New context", systemImage: "plus").frame(maxWidth: .infinity)
        }
      }
    }
  }

  func deleteContext(at offsets: IndexSet) {
    for offset in offsets {
      let context = contexts[offset]
      modelContext.delete(context)
    }
  }
}

#Preview("ContextView") {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: Context.self, configurations: config)
  let kContext = Context(name: "chicago", url: URL(string: "https://example.com")!)
  container.mainContext.insert(kContext)

  return ContextView(context: kContext).modelContainer(container)
}

#Preview("ContextListView") {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: Context.self, configurations: config)
  let kContext = Context(name: "chicago", url: URL(string: "https://example.com")!)
  container.mainContext.insert(kContext)

  return ContextListView().modelContainer(container)
}
