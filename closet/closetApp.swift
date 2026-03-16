//
//  closetApp.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import SwiftUI

@main
struct closetApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
        }
    }
}
