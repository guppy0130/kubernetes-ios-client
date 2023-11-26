//
//  KubeConfig.swift
//  kubernetes
//
//  Created by Nick Yang on 11/25/23.
//

import AsyncHTTPClient
import CryptoKit
import NIOSSL
import SwiftData
import SwiftUI
import SwiftkubeClient

// TODO: make this support other auth methods and be less shitty by subclassing
// for the auth methods
@Model
class Context: ObservableObject {
  var name: String
  var server: URL
  // it's really just a _starting_ namespace
  var namespace: String
  // if we want these to be persisted in SwiftData, read as bytes
  var serverCABytes: [UInt8]?
  var clientCABytes: [UInt8]?
  var clientKeyBytes: [UInt8]?

  var serverCA: NIOSSLCertificate? {
    if self.serverCABytes == nil {
      return nil
    }
    do {
      return try NIOSSLCertificate(bytes: self.serverCABytes!, format: .pem)
    } catch NIOSSLError.failedToLoadCertificate {
      fatalError("can't read \(serverCABytes!)")
    } catch {
      fatalError("\(error)")
    }
  }

  var clientCA: NIOSSLCertificate? {
    if self.clientCABytes == nil {
      return nil
    }
    do {
      return try NIOSSLCertificate(bytes: self.clientCABytes!, format: .pem)
    } catch NIOSSLError.failedToLoadCertificate {
      fatalError("Can't read \(clientCABytes!)")
    } catch {
      fatalError("\(error)")
    }
  }

  var clientKey: NIOSSLPrivateKey? {
    if self.clientKeyBytes == nil {
      return nil
    }
    do {
      return try NIOSSLPrivateKey(bytes: self.clientKeyBytes!, format: .pem)
    } catch NIOSSLError.failedToLoadPrivateKey {
      fatalError("Can't read private key \(clientKeyBytes!)")
    } catch {
      fatalError("\(error)")
    }
  }

  init(name: String, url: URL, namespace: String = "default") {
    self.name = name
    self.server = url
    self.namespace = namespace
  }

  // where url is a String
  init(name: String, string: String, namespace: String = "default") throws {
    self.name = name
    self.namespace = namespace
    if let parsed_url = URL(string: string) {
      self.server = parsed_url
    } else {
      throw URLError(.badURL)
    }
  }

  /// if it can auth
  func has_auth() -> Bool {
    return self.clientCA != nil && self.clientKey != nil
  }
}

class ContextClient {
  var context: Context

  init(context: Context) {
    self.context = context
  }

  var client: KubernetesClient {
    let auth = KubernetesClientAuthentication.x509(
      clientCertificate: context.clientCA!,
      clientKey: context.clientKey!
    )
    let timeout = HTTPClient.Configuration.Timeout.init(
      connect: .seconds(1), read: .seconds(10)
    )
    let redirect = HTTPClient.Configuration.RedirectConfiguration.follow(
      max: 5, allowCycles: false
    )
    let config = KubernetesClientConfig(
      masterURL: context.server,
      namespace: context.namespace,
      authentication: auth,
      trustRoots: NIOSSLTrustRoots.certificates([context.serverCA!]),
      insecureSkipTLSVerify: false,
      timeout: timeout,
      redirectConfiguration: redirect
    )
    return KubernetesClient(config: config)
  }
}

struct ContextCertDetails: View {
  @Environment(\.editMode) private var editMode
  @Environment(\.modelContext) private var modelContext
  @Bindable var kubeConfig: Context
  @State private var serverCAFileImporter: Bool = false
  @State private var clientCertFileImporter: Bool = false
  @State private var clientKeyFileImporter: Bool = false
  @State private var filePickerPresented: Bool = false

  var body: some View {
    VStack {
      Form {
        Section("Details") {
          LabeledContent("Cluster Name") {
            if editMode?.wrappedValue.isEditing == true {
              TextField("Cluster Name", text: $kubeConfig.name)
                .multilineTextAlignment(.trailing)
            } else {
              Text(kubeConfig.name)
            }

          }
          LabeledContent("Server URL") {
            if editMode?.wrappedValue.isEditing == true {
              TextField(
                "Server URL",
                value: $kubeConfig.server,
                format: .url.port(.always)
              )
              .multilineTextAlignment(.trailing)
              .keyboardType(.URL)
              .textInputAutocapitalization(.never)
            } else {
              Text(kubeConfig.server.formatted(.url.port(.always)))
            }
          }
          LabeledContent("Namespace") {
            if editMode?.wrappedValue.isEditing == true {
              TextField("Namespace", text: $kubeConfig.namespace)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
            } else {
              Text(kubeConfig.namespace)
            }

          }
          LabeledContent("CA Cert") {
            HStack {
              Text(kubeConfig.serverCA?.description ?? "")
                .multilineTextAlignment(.trailing)
              if editMode?.wrappedValue.isEditing == true {
                Button(action: {
                  serverCAFileImporter = true
                  filePickerPresented = true
                }) {
                  Label("Import", systemImage: "square.and.arrow.down")
                }
              }
            }
          }
        }

        Section("Authentication") {
          LabeledContent("Client Cert") {
            HStack {
              Text(kubeConfig.clientCA?.description ?? "")
                .multilineTextAlignment(.trailing)
              if editMode?.wrappedValue.isEditing == true {
                Button(action: {
                  clientCertFileImporter = true
                  filePickerPresented = true
                }) {
                  Label("Import", systemImage: "square.and.arrow.down")
                }
              }
            }
          }
          LabeledContent("Client Key") {
            HStack {
              Text(kubeConfig.clientKey == nil ? "" : "Private key loaded")
                .multilineTextAlignment(.trailing)
              if editMode?.wrappedValue.isEditing == true {
                Button(action: {
                  clientKeyFileImporter = true
                  filePickerPresented = true
                }) {
                  Label("Import", systemImage: "square.and.arrow.down")
                }
              }
            }
          }
        }
      }.toolbar {
        EditButton()
      }.fileImporter(
        isPresented: $filePickerPresented,
        allowedContentTypes: [.content, .x509Certificate]
      ) {
        switch $0 {
        case .success(let url):
          do {
            if !url.startAccessingSecurityScopedResource() {
              // what should we do if we can't read the file?
              fatalError("Unable to access \(url)")
            }
            let s = (try String(contentsOf: url))
            let bytes = Array(s.utf8)
            if serverCAFileImporter {
              kubeConfig.serverCABytes = bytes
              serverCAFileImporter = false
            } else if clientCertFileImporter {
              kubeConfig.clientCABytes = bytes
              clientCertFileImporter = false
            } else if clientKeyFileImporter {
              kubeConfig.clientKeyBytes = bytes
              clientKeyFileImporter = false
            } else {
              fatalError("What are you importing??")
            }
            url.stopAccessingSecurityScopedResource()
          } catch {
            fatalError("Failed to read \(url): \(error)")
          }
        case .failure(let error):
          fatalError(error.localizedDescription)
        }
      }
    }.onTapGesture {
      hideKeyboard()
    }
  }
}

#Preview {
  let kubeConfig = Context(name: "chicago", url: URL(string: "https://192.168.1.69:6443")!)
  return ContextCertDetails(kubeConfig: kubeConfig)
}
