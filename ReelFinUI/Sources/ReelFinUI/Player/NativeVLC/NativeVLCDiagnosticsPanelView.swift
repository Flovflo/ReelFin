import SwiftUI

struct NativeVLCDiagnosticsPanelView: View {
    let rows: [String]
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(indexedRows, id: \.offset) { row in
                Text(row.line)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(16)
        .reelFinGlassRoundedRect(
            cornerRadius: 18,
            tint: Color.black.opacity(0.34),
            stroke: Color.white.opacity(0.12),
            shadowOpacity: 0.2,
            shadowRadius: 18,
            shadowYOffset: 10
        )
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }

    private var indexedRows: [(offset: Int, line: String)] {
        rows.enumerated().map { ($0.offset, $0.element) }
    }
}
