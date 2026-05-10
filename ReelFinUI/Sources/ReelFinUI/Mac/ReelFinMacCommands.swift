#if targetEnvironment(macCatalyst)
import SwiftUI

public struct ReelFinMacCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandMenu("Navigate") {
            Button("Home") {
                MacRootCommandCenter.select(.home)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Library") {
                MacRootCommandCenter.select(.library)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Settings") {
                MacRootCommandCenter.select(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Refresh") {
                MacRootCommandCenter.refreshSelectedDestination()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
#endif
