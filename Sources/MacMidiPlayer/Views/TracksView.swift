import SwiftUI

struct TracksView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var rows: [TrackRow] = []

    struct TrackRow: Identifiable {
        let id: Int
        let channel: UInt8
        let noteCount: Int
        let originalProgram: UInt8
        let originalBank: UInt8
        var bankText: String
        var programText: String
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Tracks")
                .font(.headline)

            if rows.isEmpty {
                Text("No tracks found")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                // Header
                HStack(spacing: 0) {
                    Text("Ch").frame(width: 30, alignment: .center)
                    Text("Instrument").frame(minWidth: 160, alignment: .leading).padding(.leading, 8)
                    Text("Notes").frame(width: 50, alignment: .center)
                    Text("Bank").frame(width: 50, alignment: .center)
                    Text("Prog").frame(width: 50, alignment: .center)
                    Spacer().frame(width: 50)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)

                Divider()

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rows.indices, id: \.self) { index in
                            trackRow(index: index)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 500, maxWidth: 500, minHeight: 300, maxHeight: 500)
        .onAppear { loadRows() }
    }

    private func trackRow(index: Int) -> some View {
        let row = rows[index]
        let programNum = UInt8(row.programText) ?? row.originalProgram
        let bankNum = UInt8(row.bankText) ?? row.originalBank
        let instrumentName = GM2Instruments.name(forProgram: programNum, bank: bankNum)

        return HStack(spacing: 0) {
            Text("\(row.channel + 1)")
                .frame(width: 30, alignment: .center)
                .font(.caption.monospaced())

            Text(instrumentName)
                .frame(minWidth: 160, alignment: .leading)
                .padding(.leading, 8)
                .font(.caption)
                .lineLimit(1)

            Text("\(row.noteCount)")
                .frame(width: 50, alignment: .center)
                .font(.caption.monospaced())
                .foregroundStyle(row.noteCount > 0 ? .green : .secondary)

            TextField("0", text: $rows[index].bankText)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)

            TextField("0", text: $rows[index].programText)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)

            Button("Set") {
                applyChange(index: index)
            }
            .font(.caption)
            .frame(width: 50)
            .disabled(!isValid(row: rows[index]))
        }
    }

    private func isValid(row: TrackRow) -> Bool {
        guard let bank = UInt8(row.bankText), let prog = UInt8(row.programText) else { return false }
        return prog <= 127 && bank <= 127
    }

    private func applyChange(index: Int) {
        let row = rows[index]
        guard let bank = UInt8(row.bankText), let prog = UInt8(row.programText) else { return }
        viewModel.changeInstrument(trackIndex: row.id, bankMSB: bank, program: prog)
    }

    private func loadRows() {
        rows = viewModel.trackInfos.map { info in
            TrackRow(
                id: info.id,
                channel: info.channel,
                noteCount: info.noteCount,
                originalProgram: info.program,
                originalBank: info.bankMSB,
                bankText: "\(info.bankMSB)",
                programText: "\(info.program)"
            )
        }
    }
}
