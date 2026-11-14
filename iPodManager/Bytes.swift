import Foundation

typealias Bytes = [UInt8]

extension Array where Element == UInt8 {
    func le16(_ o: Int) -> Int { Int(self[o]) | (Int(self[o + 1]) << 8) }
    func le32(_ o: Int) -> Int {
        let a = Int(self[o]), b = Int(self[o + 1]) << 8
        let c = Int(self[o + 2]) << 16, d = Int(self[o + 3]) << 24
        return a | b | c | d
    }
    mutating func put16(_ o: Int, _ v: Int) {
        for i in 0..<2 { self[o + i] = UInt8((v >> (8 * i)) & 0xFF) }
    }
    mutating func put32(_ o: Int, _ v: Int) {
        for i in 0..<4 { self[o + i] = UInt8((v >> (8 * i)) & 0xFF) }
    }
    mutating func put64(_ o: Int, _ v: UInt64) {
        for i in 0..<8 { self[o + i] = UInt8((v >> UInt64(8 * i)) & 0xFF) }
    }
}
