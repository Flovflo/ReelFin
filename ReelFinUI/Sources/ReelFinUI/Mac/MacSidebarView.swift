#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacSidebarView: View {
    @Binding var selection: MacRootDestination?

    var body: some View {
        List(selection: $selection) {
            Section("Browse") {
                ForEach(MacRootDestination.browseDestinations) { destination in
                    MacSidebarRow(destination: destination)
                        .tag(Optional(destination))
                }
            }

            Section("Account") {
                ForEach(MacRootDestination.accountDestinations) { destination in
                    MacSidebarRow(destination: destination)
                        .tag(Optional(destination))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ReelFin")
    }
}

private struct MacSidebarRow: View {
    let destination: MacRootDestination

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title)
                    .lineLimit(1)

                Text(destination.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
