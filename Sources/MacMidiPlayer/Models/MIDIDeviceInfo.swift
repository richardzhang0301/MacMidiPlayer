import CoreMIDI
import Foundation

struct MIDIDeviceInfo: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
    let endpointRef: MIDIEndpointRef

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MIDIDeviceInfo, rhs: MIDIDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}
