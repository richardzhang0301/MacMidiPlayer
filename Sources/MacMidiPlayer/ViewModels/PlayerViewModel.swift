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
    var detectedStandards: Set<MIDIStandard> { midiEngine.detectedStandards }
    var trackInfos: [TrackInfo] { midiEngine.trackInfos }

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
        play()
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

    // MARK: - Instrument Change

    func changeInstrument(trackIndex: Int, bankMSB: UInt8, program: UInt8) {
        guard let infoIndex = midiEngine.trackInfos.firstIndex(where: { $0.id == trackIndex }) else { return }
        let channel = midiEngine.trackInfos[infoIndex].channel
        let endpoint = endpointForTrack(at: infoIndex)

        // Send Bank Select + Program Change immediately so the device switches now
        midiManager.sendBytes([0xB0 | channel, 0, bankMSB], toEndpoint: endpoint)
        midiManager.sendBytes([0xC0 | channel, program], toEndpoint: endpoint)

        // Update the sequence track so the change persists during playback
        midiEngine.updateTrackInstrument(trackIndex: trackIndex, bankMSB: bankMSB, program: program)
    }

    // MARK: - Per-Track Output

    func changeTrackOutput(trackIndex: Int, deviceID: MIDIUniqueID?) {
        guard let infoIndex = midiEngine.trackInfos.firstIndex(where: { $0.id == trackIndex }) else { return }
        let info = midiEngine.trackInfos[infoIndex]

        if let deviceID = deviceID,
           let dest = midiManager.availableDestinations.first(where: { $0.id == deviceID }) {
            // Register endpoint and set per-track destination
            midiEngine.registerTrackEndpoint(deviceID: deviceID, endpoint: dest.endpointRef)
            midiEngine.trackInfos[infoIndex].outputDeviceID = deviceID
            midiEngine.setTrackDestination(trackIndex: trackIndex, endpoint: dest.endpointRef)

            // Send Bank Select + Program Change to the new device so it plays the right sound
            let channel = info.channel
            midiManager.sendBytes([0xB0 | channel, 0, info.bankMSB], toEndpoint: dest.endpointRef)
            midiManager.sendBytes([0xC0 | channel, info.program], toEndpoint: dest.endpointRef)
        } else {
            // Revert to main output
            midiEngine.trackInfos[infoIndex].outputDeviceID = nil
            midiEngine.setTrackDestination(trackIndex: trackIndex, endpoint: midiEngine.destinationEndpoint)

            // Send Bank Select + Program Change to the main device
            let channel = info.channel
            midiManager.sendBytes([0xB0 | channel, 0, info.bankMSB], toEndpoint: midiEngine.destinationEndpoint)
            midiManager.sendBytes([0xC0 | channel, info.program], toEndpoint: midiEngine.destinationEndpoint)
        }
    }

    private func endpointForTrack(at infoIndex: Int) -> MIDIEndpointRef {
        let info = midiEngine.trackInfos[infoIndex]
        if let deviceID = info.outputDeviceID,
           let endpoint = midiEngine.trackEndpoints[deviceID] {
            return endpoint
        }
        return midiEngine.destinationEndpoint
    }
}
