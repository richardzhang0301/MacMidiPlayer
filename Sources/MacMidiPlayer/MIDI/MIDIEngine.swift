import AudioToolbox
import CoreMIDI
import Foundation

final class MIDIEngine: ObservableObject {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var tempo: Double = 120.0
    @Published var loadedFileName: String?
    @Published var detectedStandards: Set<MIDIStandard> = []
    @Published var trackInfos: [TrackInfo] = []

    private var musicSequence: MusicSequence?
    private var musicPlayer: MusicPlayer?
    private var positionTimer: Timer?
    private(set) var destinationEndpoint: MIDIEndpointRef = 0

    init() {
        createPlayer()
    }

    deinit {
        stop()
        if let player = musicPlayer {
            DisposeMusicPlayer(player)
        }
        if let seq = musicSequence {
            DisposeMusicSequence(seq)
        }
    }

    // MARK: - Setup

    private func createPlayer() {
        var player: MusicPlayer?
        let status = NewMusicPlayer(&player)
        guard status == noErr, let player = player else {
            print("Failed to create MusicPlayer: \(status)")
            return
        }
        self.musicPlayer = player
    }

    // MARK: - File Loading

    func loadFile(url: URL) -> Bool {
        // Clean up existing sequence
        if let player = musicPlayer {
            MusicPlayerStop(player)
        }
        if let oldSeq = musicSequence {
            if let player = musicPlayer {
                MusicPlayerSetSequence(player, nil)
            }
            DisposeMusicSequence(oldSeq)
            musicSequence = nil
        }

        var seq: MusicSequence?
        var status = NewMusicSequence(&seq)
        guard status == noErr, let seq = seq else {
            print("Failed to create MusicSequence: \(status)")
            return false
        }

        status = MusicSequenceFileLoad(seq, url as CFURL, .midiType, .smf_ChannelsToTracks)
        guard status == noErr else {
            print("Failed to load MIDI file: \(status)")
            DisposeMusicSequence(seq)
            return false
        }

        self.musicSequence = seq
        self.loadedFileName = url.lastPathComponent
        self.detectedStandards = MIDIStandardDetector.detect(from: url)

        // Set destination endpoint if one is selected
        if destinationEndpoint != 0 {
            applyDestination(to: seq)
        }

        // Get duration
        self.duration = getSequenceDuration(seq)
        self.currentPosition = 0

        // Extract tempo
        self.tempo = getSequenceTempo(seq)

        // Assign sequence to player
        if let player = musicPlayer {
            MusicPlayerSetSequence(player, seq)
            MusicPlayerPreroll(player)
        }

        self.playbackState = .stopped
        self.trackInfos = extractTrackInfos(from: seq)

        return true
    }

    // MARK: - Destination

    func setDestination(_ endpoint: MIDIEndpointRef) {
        destinationEndpoint = endpoint
        if let seq = musicSequence {
            applyDestination(to: seq)
        }
    }

    private func applyDestination(to seq: MusicSequence) {
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            if let track = track {
                MusicTrackSetDestMIDIEndpoint(track, destinationEndpoint)
            }
        }
    }

    // MARK: - Playback Control

    func play() {
        guard let player = musicPlayer, musicSequence != nil else { return }

        if playbackState == .paused {
            // Resume from current position
        } else if playbackState == .stopped {
            MusicPlayerSetTime(player, 0)
        }

        let status = MusicPlayerStart(player)
        guard status == noErr else {
            print("Failed to start playback: \(status)")
            return
        }

        playbackState = .playing
        startPositionTimer()
    }

    func pause() {
        guard let player = musicPlayer else { return }
        MusicPlayerStop(player)
        playbackState = .paused
        stopPositionTimer()
        updatePosition()
    }

    func stop() {
        guard let player = musicPlayer else { return }
        MusicPlayerStop(player)
        MusicPlayerSetTime(player, 0)
        playbackState = .stopped
        currentPosition = 0
        stopPositionTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player = musicPlayer else { return }
        MusicPlayerSetTime(player, time)
        currentPosition = time
    }

    // MARK: - Position Tracking

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func updatePosition() {
        guard let player = musicPlayer else { return }
        var time: MusicTimeStamp = 0
        MusicPlayerGetTime(player, &time)
        DispatchQueue.main.async { [self] in
            self.currentPosition = time

            // Check if playback finished
            if self.playbackState == .playing && time >= self.duration {
                self.stop()
            }
        }
    }

    // MARK: - Sequence Info

    private func getSequenceDuration(_ seq: MusicSequence) -> TimeInterval {
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        var maxDuration: MusicTimeStamp = 0

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            guard let track = track else { continue }

            var trackLength: MusicTimeStamp = 0
            var size = UInt32(MemoryLayout<MusicTimeStamp>.size)
            MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &size)
            maxDuration = max(maxDuration, trackLength)
        }

        return maxDuration
    }

    // MARK: - Track Info

    private func extractTrackInfos(from seq: MusicSequence) -> [TrackInfo] {
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        var infos: [TrackInfo] = []

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            guard let track = track else { continue }

            var channel: UInt8 = 0
            var bankMSB: UInt8 = 0
            var program: UInt8 = 0
            var noteCount: Int = 0
            var foundChannel = false

            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            guard let iterator = iterator else { continue }

            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

            while hasEvent.boolValue {
                var timestamp: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventDataSize: UInt32 = 0

                MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)

                if eventType == kMusicEventType_MIDINoteMessage {
                    let noteMsg = eventData!.assumingMemoryBound(to: MIDINoteMessage.self)
                    if !foundChannel {
                        channel = noteMsg.pointee.channel
                        foundChannel = true
                    }
                    noteCount += 1
                } else if eventType == kMusicEventType_MIDIChannelMessage {
                    let chanMsg = eventData!.assumingMemoryBound(to: MIDIChannelMessage.self)
                    let status = chanMsg.pointee.status
                    let msgType = status & 0xF0
                    if !foundChannel {
                        channel = status & 0x0F
                        foundChannel = true
                    }
                    if msgType == 0xC0 {
                        program = chanMsg.pointee.data1
                    } else if msgType == 0xB0 && chanMsg.pointee.data1 == 0 {
                        bankMSB = chanMsg.pointee.data2
                    }
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }

            DisposeMusicEventIterator(iterator)

            if noteCount > 0 {
                infos.append(TrackInfo(
                    id: Int(i),
                    channel: channel,
                    bankMSB: bankMSB,
                    program: program,
                    noteCount: noteCount
                ))
            }
        }

        return infos
    }

    // MARK: - Instrument Change

    func updateTrackInstrument(trackIndex: Int, bankMSB: UInt8, program: UInt8) {
        guard let seq = musicSequence else { return }
        var track: MusicTrack?
        MusicSequenceGetIndTrack(seq, UInt32(trackIndex), &track)
        guard let track = track else { return }

        // Find the channel from the track info
        guard let info = trackInfos.first(where: { $0.id == trackIndex }) else { return }
        let channel = info.channel

        // Remove existing bank select (CC 0) and program change events
        var iterator: MusicEventIterator?
        NewMusicEventIterator(track, &iterator)
        guard let iterator = iterator else { return }

        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

        while hasEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_MIDIChannelMessage {
                let chanMsg = eventData!.assumingMemoryBound(to: MIDIChannelMessage.self)
                let msgType = chanMsg.pointee.status & 0xF0
                let msgChan = chanMsg.pointee.status & 0x0F
                if msgChan == channel {
                    if msgType == 0xC0 || (msgType == 0xB0 && chanMsg.pointee.data1 == 0) {
                        MusicEventIteratorDeleteEvent(iterator)
                        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
                        continue
                    }
                }
            }

            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }

        DisposeMusicEventIterator(iterator)

        // Insert new bank select and program change at timestamp 0
        var bankMsg = MIDIChannelMessage(status: 0xB0 | channel, data1: 0, data2: bankMSB, reserved: 0)
        MusicTrackNewMIDIChannelEvent(track, 0, &bankMsg)

        var progMsg = MIDIChannelMessage(status: 0xC0 | channel, data1: program, data2: 0, reserved: 0)
        MusicTrackNewMIDIChannelEvent(track, 0, &progMsg)

        // Update local state
        if let idx = trackInfos.firstIndex(where: { $0.id == trackIndex }) {
            trackInfos[idx].bankMSB = bankMSB
            trackInfos[idx].program = program
        }
    }

    private func getSequenceTempo(_ seq: MusicSequence) -> Double {
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(seq, &tempoTrack)
        guard let tempoTrack = tempoTrack else { return 120.0 }

        var iterator: MusicEventIterator?
        NewMusicEventIterator(tempoTrack, &iterator)
        guard let iterator = iterator else { return 120.0 }

        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

        while hasEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_ExtendedTempo {
                let tempoData = eventData!.assumingMemoryBound(to: ExtendedTempoEvent.self)
                DisposeMusicEventIterator(iterator)
                return tempoData.pointee.bpm
            }

            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }

        DisposeMusicEventIterator(iterator)
        return 120.0
    }
}
