import AVFoundation
import CoreMedia

struct SongMeta {
    var title = "", artist = "", album = "", genre = ""
    var year = 0, durationMs = 0, bitrate = 0, sampleRate = 44100, trackNumber = 0
}

enum MetadataReader {
    static func read(_ url: URL) async -> SongMeta {
        var m = SongMeta()
        m.title = url.deletingPathExtension().lastPathComponent
        let asset = AVURLAsset(url: url)

        if let d = try? await asset.load(.duration), d.seconds.isFinite {
            m.durationMs = Int(d.seconds * 1000)
        }
        if let items = try? await asset.load(.commonMetadata) {
            func str(_ id: AVMetadataIdentifier) async -> String? {
                guard let it = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
                return try? await it.load(.stringValue)
            }
            if let s = await str(.commonIdentifierTitle), !s.isEmpty { m.title = s }
            if let s = await str(.commonIdentifierArtist) { m.artist = s }
            if let s = await str(.commonIdentifierAlbumName) { m.album = s }
            if let s = await str(.commonIdentifierCreationDate), let y = Int(s.prefix(4)) { m.year = y }
        }
        if let t = try? await asset.loadTracks(withMediaType: .audio).first {
            if let r = try? await t.load(.estimatedDataRate) { m.bitrate = Int(r / 1000) }
            if let fds = try? await t.load(.formatDescriptions), let fd = fds.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                m.sampleRate = Int(asbd.mSampleRate)
            }
        }
        return m
    }
}
