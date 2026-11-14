import Foundation

/// iPod Classic (6G/7G) rejects an iTunesDB that lacks a valid "hash58" signature
/// (header field `hashing_scheme` == 1). Implement a signer and assign it to
/// `Checksum.signer` at launch (see README). Until then writes are refused
/// unless the user enables the experimental "write unsigned" option.
protocol DBSigner {
    func sign(_ db: inout Bytes) throws
}

enum Checksum {
    static var signer: DBSigner? = nil
}
