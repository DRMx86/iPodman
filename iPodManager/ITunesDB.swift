import Foundation

enum DBError: LocalizedError {
    case notFound, corrupt(String), unsupportedFormat(String), unsupportedChecksum(Int), readOnly

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No iTunesDB found. Select the iPod's root folder (the one containing iPod_Control) and make sure the iPod is in disk mode."
        case .corrupt(let s):
            return "The iPod database could not be read (\(s))."
        case .unsupportedFormat(let e):
            return "“.\(e)” isn’t supported by the iPod. Use MP3, M4A (AAC/ALAC), WAV or AIFF."
        case .readOnly:
            return "This iPod (nano 5th gen or newer) uses a compressed, signed database (iTunesCDB). It is opened read-only: you can browse and preview songs, not change them."
        case .unsupportedChecksum(let s):
            return "This iPod signs its database (scheme \(s)) and no checksum signer is installed, so nothing was changed. See the README."
        }
    }
}

// MARK: - Generic chunk tree (unknown bytes are preserved verbatim)

final class DBNode {
    var tag: String
    var header: Bytes
    var body: Bytes = []          // only used by "mhod"
    var children: [DBNode] = []

    init(tag: String, header: Bytes) { self.tag = tag; self.header = header }

    static func make(_ tag: String, headerSize: Int) -> DBNode {
        var h = Bytes(repeating: 0, count: headerSize)
        h.replaceSubrange(0..<4, with: Array(tag.utf8))
        h.put32(4, headerSize)
        return DBNode(tag: tag, header: h)
    }

    var isList: Bool { tag.hasPrefix("mhl") }
    var mhodType: Int { header.count >= 16 ? header.le32(12) : -1 }

    static func parse(_ d: Bytes, at o: Int) throws -> (DBNode, Int) {
        guard o + 12 <= d.count else { throw DBError.corrupt("truncated") }
        let tag = String(decoding: d[o..<o + 4], as: UTF8.self)
        let hsize = d.le32(o + 4), v = d.le32(o + 8)
        guard hsize >= 12, o + hsize <= d.count else { throw DBError.corrupt("bad header \(tag)") }
        let n = DBNode(tag: tag, header: Array(d[o..<o + hsize]))

        if tag == "mhod" {
            guard v >= hsize, o + v <= d.count else { throw DBError.corrupt("bad mhod") }
            n.body = Array(d[o + hsize..<o + v])
            return (n, o + v)
        }
        var p = o + hsize
        if n.isList {                         // list headers store a child COUNT at 0x08
            guard v >= 0, v < 1_000_000 else { throw DBError.corrupt("bad list") }
            for _ in 0..<v {
                let (c, e) = try parse(d, at: p)
                n.children.append(c); p = e
            }
            return (n, p)
        }
        guard v >= hsize, o + v <= d.count else { throw DBError.corrupt("bad size \(tag)") }
        while p < o + v {
            let (c, e) = try parse(d, at: p)
            n.children.append(c); p = e
        }
        return (n, o + v)
    }

    func serialize() -> Bytes {
        if tag == "mhod" {
            var out = header + body
            out.put32(8, out.count)
            return out
        }
        var h = header
        let kids = children.flatMap { $0.serialize() }
        if isList {
            h.put32(8, children.count)
            return h + kids
        }
        let mhods = children.filter { $0.tag == "mhod" }.count
        switch tag {
        case "mhit", "mhip": h.put32(12, mhods)
        case "mhyp":
            h.put32(12, mhods)
            h.put32(16, children.filter { $0.tag == "mhip" }.count)
        default: break
        }
        h.put32(8, h.count + kids.count)
        return h + kids
    }

    var stringValue: String? {
        guard tag == "mhod", mhodType >= 0, mhodType < 50, body.count >= 16 else { return nil }
        let enc = body.le32(0), len = body.le32(4)
        guard len >= 0, body.count >= 16 + len else { return nil }
        let data = Data(body[16..<16 + len])
        return String(data: data, encoding: enc == 2 ? .utf8 : .utf16LittleEndian)
    }

    static func stringMhod(type: Int, _ s: String) -> DBNode {
        let n = make("mhod", headerSize: 24)
        n.header.put32(12, type)
        let data = Bytes(s.data(using: .utf16LittleEndian) ?? Data())
        var b = Bytes(repeating: 0, count: 16)
        b.put32(0, 1); b.put32(4, data.count); b.put32(8, 1)
        n.body = b + data
        return n
    }
}

// MARK: - Models

struct Track: Identifiable, Hashable {
    var id: Int
    var title = "", artist = "", album = "", genre = ""
    var trackNumber = 0, year = 0, durationMs = 0, size = 0, bitrate = 0
    var location = ""

    init?(node: DBNode) {
        guard node.tag == "mhit", node.header.count >= 0x3C else { return nil }
        let h = node.header
        id = h.le32(0x10); size = h.le32(0x24); durationMs = h.le32(0x28)
        trackNumber = h.le32(0x2C); year = h.le32(0x34); bitrate = h.le32(0x38)
        for m in node.children where m.tag == "mhod" {
            guard let s = m.stringValue else { continue }
            switch m.mhodType {
            case 1: title = s
            case 2: location = s
            case 3: album = s
            case 4: artist = s
            case 5: genre = s
            default: break
            }
        }
    }
}

enum AudioFormat {
    case mp3, aac, wav, aiff

    init?(ext: String) {
        switch ext.lowercased() {
        case "mp3": self = .mp3
        case "m4a", "m4b": self = .aac
        case "wav": self = .wav
        case "aif", "aiff": self = .aiff
        default: return nil
        }
    }
    var marker: Int {
        switch self {
        case .mp3: return 0x4D50_3320   // "MP3 "
        case .aac: return 0x4D34_4120   // "M4A "
        case .wav: return 0x5741_5620   // "WAV "
        case .aiff: return 0x4149_4646  // "AIFF"
        }
    }
    var label: String {
        switch self {
        case .mp3: return "MPEG audio file"
        case .aac: return "AAC audio file"
        case .wav: return "WAV audio file"
        case .aiff: return "AIFF audio file"
        }
    }
}

// MARK: - Database

final class ITunesDatabase {
    let root: DBNode

    private(set) var readOnly = false

    init(bytes: Bytes) throws {
        guard bytes.count > 24, String(decoding: bytes[0..<4], as: UTF8.self) == "mhbd" else {
            throw DBError.corrupt("not an iTunesDB, \(bytes.count) bytes")
        }
        let hsize = bytes.le32(4)
        if hsize >= 12, bytes.count > hsize + 6, bytes[hsize] == 0x78 {
            // iTunesCDB: mhbd header followed by one zlib stream of the mhsd chunks
            let stream = Data(bytes[(hsize + 2)..<(bytes.count - 4)])   // skip zlib header + adler32
            guard let raw = try? (stream as NSData).decompressed(using: .zlib) else {
                throw DBError.corrupt("cannot decompress iTunesCDB")
            }
            let dec = Bytes(raw as Data)
            let node = DBNode(tag: "mhbd", header: Array(bytes[0..<hsize]))
            var p = 0
            while p < dec.count {
                let (c, e) = try DBNode.parse(dec, at: p)
                node.children.append(c); p = e
            }
            root = node
            readOnly = true
        } else {
            root = try DBNode.parse(bytes, at: 0).0
        }
    }

    static var macNow: Int { Int(Date().timeIntervalSince1970) + 2_082_844_800 }

    var hashingScheme: Int { root.header.count > 0x32 ? root.header.le16(0x30) : 0 }

    private func section(_ type: Int) -> DBNode? {
        root.children.first { $0.tag == "mhsd" && $0.header.le32(12) == type }?.children.first
    }
    var trackList: DBNode? { section(1) }
    var tracks: [Track] { (trackList?.children ?? []).compactMap { Track(node: $0) } }

    private var masterPlaylist: DBNode? {
        let all = (section(2)?.children ?? []).filter { $0.tag == "mhyp" }
        return all.first { $0.header.count > 0x14 && $0.header[0x14] == 1 } ?? all.first
    }

    private func node(for id: Int) -> DBNode? {
        trackList?.children.first { $0.tag == "mhit" && $0.header.le32(0x10) == id }
    }

    func nextID() -> Int {
        (trackList?.children.compactMap { $0.header.count > 0x14 ? $0.header.le32(0x10) : nil }.max() ?? 0) + 1
    }

    private func setString(_ n: DBNode, _ type: Int, _ v: String) {
        n.children.removeAll { $0.tag == "mhod" && $0.mhodType == type }
        if !v.isEmpty { n.children.append(.stringMhod(type: type, v)) }
    }

    func update(_ t: Track) {
        guard let n = node(for: t.id) else { return }
        setString(n, 1, t.title); setString(n, 3, t.album)
        setString(n, 4, t.artist); setString(n, 5, t.genre)
        n.header.put32(0x2C, t.trackNumber)
        n.header.put32(0x34, t.year)
    }

    func remove(id: Int) {
        trackList?.children.removeAll { $0.tag == "mhit" && $0.header.le32(0x10) == id }
        for sec in root.children where sec.tag == "mhsd" {
            for list in sec.children where list.tag == "mhlp" {
                for pl in list.children where pl.tag == "mhyp" {
                    pl.children.removeAll { $0.tag == "mhip" && $0.header.count > 0x1C && $0.header.le32(0x18) == id }
                }
            }
        }
    }

    @discardableResult
    func addTrack(_ m: SongMeta, format: AudioFormat, size: Int, location: String) -> Int? {
        guard let list = trackList else { return nil }
        let id = nextID()
        let hsize = max(list.children.first?.header.count ?? 0x274, 0x78)
        let n = DBNode.make("mhit", headerSize: hsize)
        func set(_ o: Int, _ v: Int) { if o + 4 <= hsize { n.header.put32(o, v) } }
        let now = Self.macNow
        set(0x10, id); set(0x14, 1); set(0x18, format.marker)
        n.header[0x1C] = format == .mp3 ? 1 : 0
        n.header[0x1D] = format == .mp3 ? 1 : 0
        set(0x20, now); set(0x24, size); set(0x28, m.durationMs)
        set(0x2C, m.trackNumber); set(0x34, m.year)
        set(0x38, m.bitrate); set(0x3C, m.sampleRate << 16)
        set(0x68, now)
        n.header.put64(0x70, UInt64.random(in: 1...UInt64.max))
        set(0xD0, 1) // media type: audio

        setString(n, 1, m.title); setString(n, 2, location)
        setString(n, 3, m.album); setString(n, 4, m.artist)
        setString(n, 5, m.genre); setString(n, 6, format.label)
        list.children.append(n)
        addToMaster(id)
        return id
    }

    private func addToMaster(_ trackID: Int) {
        guard let pl = masterPlaylist else { return }
        let items = pl.children.filter { $0.tag == "mhip" }
        let nextGroup = (items.map { $0.header.le32(0x14) }.max() ?? 0) + 1
        let ip = DBNode.make("mhip", headerSize: 0x4C)
        ip.header.put32(0x14, nextGroup)
        ip.header.put32(0x18, trackID)
        ip.header.put32(0x1C, Self.macNow)
        let pos = DBNode.make("mhod", headerSize: 24)
        pos.header.put32(12, 100)
        pos.body = Bytes(repeating: 0, count: 20)
        pos.body.put32(0, items.count + 1)
        ip.children = [pos]
        pl.children.append(ip)
    }

    func serialized(allowUnsigned: Bool) throws -> Bytes {
        guard !readOnly else { throw DBError.readOnly }
        var out = root.serialize()
        if hashingScheme != 0 {
            if let signer = Checksum.signer { try signer.sign(&out) }
            else if !allowUnsigned { throw DBError.unsupportedChecksum(hashingScheme) }
        }
        return out
    }
}
