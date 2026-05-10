#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacRootShellView: View {
    @SceneStorage("reelfin.mac.selectedDestination") private var selectedDestinationRawValue = MacRootDestination.home.rawValue
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isSidebarVisible = true
    @State private var refreshCounts: [MacRootDestination: Int] = [:]

    let dependencies: ReelFinDependencies
    let onSignOut: () -> Void

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(selection: selectedDestinationBinding)
        } detail: {
            MacDestinationDetailView(
                destination: selectedDestination,
                refreshID: refreshCounts[selectedDestination, default: 0],
                dependencies: dependencies,
                onSignOut: onSignOut,
                onToggleSidebar: toggleSidebar,
                onRefresh: refreshSelectedDestination
            )
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .reelFinMacSelectDestination)) { notification in
            guard
                let rawValue = notification.userInfo?[MacRootCommandCenter.destinationUserInfoKey] as? String,
                let destination = MacRootDestination(rawValue: rawValue)
            else {
                return
            }

            selectedDestinationRawValue = destination.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .reelFinMacRefreshSelectedDestination)) { _ in
            refreshSelectedDestination()
        }
    }

    private var selectedDestination: MacRootDestination {
        MacRootDestination(rawValue: selectedDestinationRawValue) ?? .home
    }

    private var selectedDestinationBinding: Binding<MacRootDestination?> {
        Binding {
            selectedDestination
        } set: { destination in
            guard let destination else { return }
            selectedDestinationRawValue = destination.rawValue
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSidebarVisible.toggle()
            columnVisibility = isSidebarVisible ? .all : .detailOnly
        }
    }

    private func refreshSelectedDestination() {
        refreshCounts[selectedDestination, default: 0] += 1
    }
}
#endif
