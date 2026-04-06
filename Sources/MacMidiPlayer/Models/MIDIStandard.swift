import SwiftUI

enum MIDIStandard: String, CaseIterable {
    case gm = "GM"
    case gm2 = "GM2"
    case gs = "GS"
    case xg = "XG"
    case mt32 = "MT-32"

    var color: Color {
        switch self {
        case .gm:   return .blue
        case .gm2:  return .cyan
        case .gs:   return .orange
        case .xg:   return .green
        case .mt32: return .purple
        }
    }
}

struct MIDIStandardDetector {
    // SysEx data payloads (without F0 prefix and F7 suffix)
    // GM System On: F0 7E 7F 09 01 F7
    private static let gmData: [UInt8] = [0x7E, 0x7F, 0x09, 0x01]
    // GM2 System On: F0 7E 7F 09 03 F7
    private static let gm2Data: [UInt8] = [0x7E, 0x7F, 0x09, 0x03]
    // GS Reset: F0 41 10 42 12 40 00 7F 00 41 F7
    private static let gsData: [UInt8] = [0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7F, 0x00, 0x41]
    // XG System On: F0 43 10 4C 00 00 7E 00 F7
    private static let xgData: [UInt8] = [0x43, 0x10, 0x4C, 0x00, 0x00, 0x7E, 0x00]
    // MT-32: Roland SysEx with MT-32 device ID 0x16
    private static let mt32Data: [UInt8] = [0x41, 0x10, 0x16]

    static func detect(from fileURL: URL) -> Set<MIDIStandard> {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let bytes = [UInt8](data)
        var standards = Set<MIDIStandard>()

        var i = 0
        while i < bytes.count {
            guard bytes[i] == 0xF0 else { i += 1; continue }

            // Try matching at both possible offsets:
            // 1) i+1: raw SysEx (data directly after F0)
            // 2) after variable-length quantity: SMF format (F0 + length + data)
            let rawStart = i + 1
            let smfStart = skipVariableLength(bytes, from: i + 1)

            for dataStart in [rawStart, smfStart] {
                if matchesAt(bytes, offset: dataStart, pattern: xgData) {
                    standards.insert(.xg)
                }
                if matchesAt(bytes, offset: dataStart, pattern: gsData) {
                    standards.insert(.gs)
                }
                if matchesAt(bytes, offset: dataStart, pattern: gm2Data) {
                    standards.insert(.gm2)
                } else if matchesAt(bytes, offset: dataStart, pattern: gmData) {
                    standards.insert(.gm)
                }
                if matchesAt(bytes, offset: dataStart, pattern: mt32Data) {
                    standards.insert(.mt32)
                }
            }

            i += 1
        }

        return standards
    }

    /// Skip a MIDI variable-length quantity starting at `from`.
    /// Returns the index of the first byte after the variable-length value.
    private static func skipVariableLength(_ bytes: [UInt8], from: Int) -> Int {
        var pos = from
        while pos < bytes.count && bytes[pos] & 0x80 != 0 {
            pos += 1
        }
        if pos < bytes.count {
            pos += 1
        }
        return pos
    }

    private static func matchesAt(_ bytes: [UInt8], offset: Int, pattern: [UInt8]) -> Bool {
        guard offset + pattern.count <= bytes.count else { return false }
        for j in 0..<pattern.count {
            if bytes[offset + j] != pattern[j] { return false }
        }
        return true
    }
}
