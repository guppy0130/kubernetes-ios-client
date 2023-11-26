//
//  kubernetesApp.swift
//  kubernetes
//
//  Created by Nick Yang on 11/25/23.
//

import SwiftData
import SwiftUI

@main
struct kubernetesApp: App {
  let modelContainer: ModelContainer

  init() {
    do {
      self.modelContainer = try ModelContainer(for: Context.self)
    } catch {
      fatalError("Could not initialize modelContainer")
    }
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ContextListView()
      }
    }
    .modelContainer(modelContainer)
  }
}

#if canImport(UIKit)
  import UIKit
  extension View {
    /// call this to hide the keyboard
    func hideKeyboard() {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }
#endif
