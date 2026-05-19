import AppKit
import SwiftUI

@main
struct JMUCoursePlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PlanStore()

    var body: some Scene {
        WindowGroup("JMU Course Planner") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    await store.load()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Save Plan") {
                    store.saveCurrentPlan()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Export PDF") {
                    store.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
