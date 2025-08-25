//
//  maderuApp.swift
//  maderu
//
//  Created by 新村彰啓 on 8/25/25.
//

import SwiftUI

@main
struct maderuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open on External Display") {
                    openOnExternalDisplay()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
    
    func openOnExternalDisplay() {
        if let screen = NSScreen.screens.first(where: { !$0.isMainScreen }) {
            if let window = NSApplication.shared.windows.first {
                window.setFrame(screen.frame, display: true)
                window.toggleFullScreen(nil)
            }
        } else {
            if let window = NSApplication.shared.windows.first {
                window.toggleFullScreen(nil)
            }
        }
    }
}

extension NSScreen {
    var isMainScreen: Bool {
        return self == NSScreen.main
    }
}
