//
//  ContentView.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        Group {
            MainTabView()
        }
        .task {
            await appViewModel.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await appViewModel.handleSceneBecameActive()
            }
        }
    }
}

struct ClosetRootPreview: View {
    var body: some View {
        ContentView()
    }
}

#Preview {
    ClosetRootPreview()
}
