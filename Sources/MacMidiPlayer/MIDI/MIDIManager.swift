import CoreMIDI
import Foundation
import Combine

final class MIDIManager: ObservableObject {
    @Published var availableSources: [MIDIDeviceInfo] = []
    @Published var availableDestinations: [MIDIDeviceInfo] = []

    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var connectedSource: MIDIEndpointRef = 0

    var onMIDIReceived: (([UInt8]) -> Void)?

    init() {
        setupClient()
        refreshDeviceLists()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Setup

    private func setupClient() {
        let status = MIDIClientCreateWithBlock("MacMidiPlayer" as CFString, &client) { [weak self] notification in
            let messageID = notification.pointee.messageID
            if messageID == .msgObjectAdded || messageID == .msgObjectRemoved {
                DispatchQueue.main.async {
                    self?.refreshDeviceLists()
                }
            }
        }
        guard status == noErr else {
            print("Failed to create MIDI client: \(status)")
            return
        }

        let inputStatus = MIDIInputPortCreateWithProtocol(
            client,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIInput(eventList)
        }
        if inputStatus != noErr {
            print("Failed to create input port: \(inputStatus)")
        }

        let outputStatus = MIDIOutputPortCreate(
            client,
            "Output" as CFString,
            &outputPort
        )
        if outputStatus != noErr {
            print("Failed to create output port: \(outputStatus)")
        }
    }

    // MARK: - Device Enumeration

    func refreshDeviceLists() {
        availableSources = enumerateSources()
        availableDestinations = enumerateDestinations()
    }

    private func enumerateSources() -> [MIDIDeviceInfo] {
        var sources: [MIDIDeviceInfo] = []
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            if let info = deviceInfo(for: endpoint) {
                sources.append(info)
            }
        }
        return sources
    }

    private func enumerateDestinations() -> [MIDIDeviceInfo] {
        var destinations: [MIDIDeviceInfo] = []
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            if let info = deviceInfo(for: endpoint) {
                destinations.append(info)
            }
        }
        return destinations
    }

    private func deviceInfo(for endpoint: MIDIEndpointRef) -> MIDIDeviceInfo? {
        guard endpoint != 0 else { return nil }
        var uniqueID: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

        var nameRef: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef)
        let name = (nameRef?.takeRetainedValue() as String?) ?? "Unknown"

        return MIDIDeviceInfo(id: uniqueID, name: name, endpointRef: endpoint)
    }

    // MARK: - Input Connection

    func connectInput(source: MIDIDeviceInfo?) {
        // Disconnect previous
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
            connectedSource = 0
        }

        guard let source = source else { return }
        let status = MIDIPortConnectSource(inputPort, source.endpointRef, nil)
        if status == noErr {
            connectedSource = source.endpointRef
        } else {
            print("Failed to connect input source: \(status)")
        }
    }

    // MARK: - Output

    func send(bytes: [UInt8], to destination: MIDIDeviceInfo) {
        guard outputPort != 0 else { return }
        let packetListSize = MemoryLayout<MIDIPacketList>.size + bytes.count
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, packetListSize, packet, 0, bytes.count, bytes)
        MIDISend(outputPort, destination.endpointRef, &packetList)
    }

    // MARK: - MIDI Input Handling

    private func handleMIDIInput(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        let eventList = eventListPtr.pointee
        var packet = eventList.packet
        for _ in 0..<eventList.numPackets {
            let words = Mirror(reflecting: packet.words).children.map { $0.value as! UInt32 }
            let wordCount = Int(packet.wordCount)
            var bytes: [UInt8] = []
            for i in 0..<wordCount {
                let word = words[i]
                bytes.append(UInt8((word >> 16) & 0xFF))
                bytes.append(UInt8((word >> 8) & 0xFF))
                bytes.append(UInt8(word & 0xFF))
            }
            if !bytes.isEmpty {
                onMIDIReceived?(bytes)
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }
}
