import SwiftUI

struct TVTopNavigationItem: View {
    @FocusState private var isFocused: Bool

    let destination: TVRootDestination
    let isSelected: Bool
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(destination.title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, 24)
        .frame(height: ReelFinTheme.tvTopNavigationItemHeight)
        .frame(minWidth: destination == .search ? 170 : 210)
        .background(backgroundShape)
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.035 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.18 : 0.08), radius: isFocused ? 16 : 8, x: 0, y: isFocused ? 10 : 4)
        .focusable(true, interactions: .activate)
        .focused(focusedDestination, equals: destination)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRepresentation {
            Button(destination.title, action: action)
        }
    }

    private var labelColor: Color {
        isSelected || isFocused ? Color.black.opacity(0.92) : Color.white.opacity(0.96)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if isSelected || isFocused {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.96 : 0.88))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.28 : 0.14), lineWidth: 1)
                }
        }
    }
}
