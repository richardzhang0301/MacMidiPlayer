import Foundation

struct TrackInfo: Identifiable {
    let id: Int          // track index
    var channel: UInt8
    var bankMSB: UInt8
    var program: UInt8
    var noteCount: Int

    var instrumentName: String {
        GM2Instruments.name(forProgram: program, bank: bankMSB)
    }
}
