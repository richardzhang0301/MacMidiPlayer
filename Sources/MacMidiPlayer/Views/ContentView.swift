import CoreMIDI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = PlayerViewModel()
    @State private var isDragOver = false
    @State private var showTracks = false
    @State private var showBeats = false

    var body: some View {
        VStack(spacing: 16) {
            // Device Selection
            deviceSection

            Divider()

            // File Info
            fileSection

            Divider()

            // Transport Controls
            transportSection

            // MIDI Input Monitor
            if !viewModel.lastMIDIMessage.isEmpty {
                Divider()
                HStack {
                    Text("Last MIDI Input:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.lastMIDIMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Bottom bar: MIDI standards (left) and Tracks button (right)
            Divider()
            HStack {
                if !viewModel.detectedStandards.isEmpty {
                    MIDIStandardBar(standards: viewModel.detectedStandards)
                }
                Spacer()
                Button("Tracks") {
                    showTracks = true
                }
                .disabled(viewModel.trackInfos.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.pathExtension.lowercased() == "mid" || url.pathExtension.lowercased() == "midi" else { return }
                DispatchQueue.main.async {
                    viewModel.loadFile(url: url)
                }
            }
            return true
        }
        .border(isDragOver ? Color.accentColor : Color.clear, width: 2)
        .sheet(isPresented: $showTracks) {
            TracksView(viewModel: viewModel)
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Output Device:")
                    .frame(width: 110, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { viewModel.selectedOutputID },
                    set: { viewModel.selectOutput($0) }
                )) {
                    Text("None").tag(nil as MIDIUniqueID?)
                    ForEach(viewModel.availableDestinations) { dest in
                        Text(dest.name).tag(dest.id as MIDIUniqueID?)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Input Device:")
                    .frame(width: 110, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { viewModel.selectedInputID },
                    set: { viewModel.selectInput($0) }
                )) {
                    Text("None").tag(nil as MIDIUniqueID?)
                    ForEach(viewModel.availableSources) { source in
                        Text(source.name).tag(source.id as MIDIUniqueID?)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - File Section

    private var fileSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let fileName = viewModel.loadedFileName {
                        Text(fileName)
                            .font(.headline)
                        Text("Duration: \(formatPosition(viewModel.duration))\(showBeats ? " beats" : "")  |  Tempo: \(String(format: "%.0f", viewModel.tempo)) BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No file loaded")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Open File...") {
                    viewModel.openFile()
                }
            }
        }
    }

    // MARK: - Transport Section

    private var transportSection: some View {
        VStack(spacing: 10) {
            // Progress bar
            if viewModel.duration > 0 {
                Slider(
                    value: Binding(
                        get: { viewModel.currentPosition },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.duration, 1)
                )

                HStack {
                    Text(formatPosition(viewModel.currentPosition))
                        .font(.caption.monospaced())
                        .onTapGesture { showBeats.toggle() }
                    Spacer()
                    Text(formatPosition(viewModel.duration))
                        .font(.caption.monospaced())
                        .onTapGesture { showBeats.toggle() }
                }
            }

            // Buttons
            HStack(spacing: 20) {
                Button(action: { viewModel.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .disabled(viewModel.playbackState == .stopped)
                .keyboardShortcut(".", modifiers: .command)

                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .disabled(viewModel.loadedFileName == nil)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    // MARK: - Helpers

    private func formatPosition(_ beats: TimeInterval) -> String {
        if showBeats {
            return String(format: "%.1f", beats)
        }
        let seconds = beats * 60.0 / max(viewModel.tempo, 1)
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
