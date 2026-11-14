import SwiftUI
import UIKit
import AVFoundation
import ImageIO

/// Reads cover art embedded in the audio file's own tags (ID3 / MP4) and caches small thumbnails.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()
    private var missing = Set<String>()

    func reset() { cache.removeAllObjects(); missing.removeAll() }

    func image(key: String, url: URL) async -> UIImage? {
        if let i = cache.object(forKey: key as NSString) { return i }
        if missing.contains(key) { return nil }
        guard let data = await Self.loadData(url) else { missing.insert(key); return nil }
        let img = await Task.detached { Self.thumbnail(data, 160) }.value
        if let img { cache.setObject(img, forKey: key as NSString) } else { missing.insert(key) }
        return img
    }

    nonisolated static func loadData(_ url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata),
              let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first
        else { return nil }
        if let d = try? await item.load(.dataValue) { return d }
        return (try? await item.load(.value)) as? Data
    }

    nonisolated static func thumbnail(_ data: Data, _ size: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ArtworkView: View {
    let track: Track
    let url: URL?
    var isCurrent = false
    var isPlaying = false
    var side: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }
            if isCurrent && isPlaying {
                ZStack { Color.black.opacity(0.4); Image(systemName: "waveform").foregroundStyle(.white) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: track.location) {
            guard let url else { return }
            image = await ArtworkCache.shared.image(key: track.location, url: url)
        }
    }
}
