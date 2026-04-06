import SwiftUI

struct MIDIStandardBadge: View {
    let standard: MIDIStandard

    var body: some View {
        Text(standard.rawValue)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(standard.color)
            )
    }
}

struct MIDIStandardBar: View {
    let standards: Set<MIDIStandard>

    private var sorted: [MIDIStandard] {
        MIDIStandard.allCases.filter { std in
            guard standards.contains(std) else { return false }
            // XG is a superset of GM — hide GM when XG is present
            if std == .gm && standards.contains(.xg) { return false }
            return true
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sorted, id: \.self) { std in
                MIDIStandardBadge(standard: std)
            }
        }
    }
}
