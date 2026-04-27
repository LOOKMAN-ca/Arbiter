import SwiftUI

@main
struct ArbiterApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var engine   = OrchestrationEngine()
    @StateObject private var speech   = SpeechManager()
    @StateObject private var feedback = FeedbackManager()
    @StateObject private var fae      = FAEManager()

    @FocusedValue(\.arbiterActions) private var actions

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(speech)
                .environmentObject(feedback)
                .environmentObject(fae)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1050, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Arbiter Core") {
                Button("Execute Sequence") {
                    actions?.execute()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Validate Protocol") {
                    actions?.validate()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                Button("Abort All") {
                    actions?.abort()
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}
