import Combine
import CoreMIDI
import Foundation
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var midiManager: MIDIManager
    @Published var midiEngine: MIDIEngine

    @Published var selectedInputID: MIDIUniqueID? = nil
    @Published var selectedOutputID: MIDIUniqueID? = nil

    @Published var lastMIDIMessage: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        let manager = MIDIManager()
        let engine = MIDIEngine()
        self.midiManager = manager
        self.midiEngine = engine

        setupBindings()

        manager.onMIDIReceived = { [weak self] bytes in
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            DispatchQueue.main.async {
                self?.lastMIDIMessage = hex
            }
        }
    }

    private func setupBindings() {
        // Forward MIDIManager published changes
        midiManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Forward MIDIEngine published changes
        midiEngine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    var availableSources: [MIDIDeviceInfo] { midiManager.availableSources }
    var availableDestinations: [MIDIDeviceInfo] { midiManager.availableDestinations }
    var playbackState: PlaybackState { midiEngine.playbackState }
    var currentPosition: TimeInterval { midiEngine.currentPosition }
    var duration: TimeInterval { midiEngine.duration }
    var loadedFileName: String? { midiEngine.loadedFileName }
    var tempo: Double { midiEngine.tempo }

    // MARK: - Input Selection

    func selectInput(_ id: MIDIUniqueID?) {
        selectedInputID = id
        let source = midiManager.availableSources.first { $0.id == id }
        midiManager.connectInput(source: source)
    }

    // MARK: - Output Selection

    func selectOutput(_ id: MIDIUniqueID?) {
        selectedOutputID = id
        if let dest = midiManager.availableDestinations.first(where: { $0.id == id }) {
            midiEngine.setDestination(dest.endpointRef)
        }
    }

    // MARK: - File Loading

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url: url)
    }

    func loadFile(url: URL) {
        let _ = midiEngine.loadFile(url: url)
    }

    // MARK: - Transport

    func play() {
        midiEngine.play()
    }

    func pause() {
        midiEngine.pause()
    }

    func stop() {
        midiEngine.stop()
    }

    func togglePlayPause() {
        switch midiEngine.playbackState {
        case .playing:
            pause()
        case .paused, .stopped:
            play()
        }
    }

    func seek(to time: TimeInterval) {
        midiEngine.seek(to: time)
    }
}
