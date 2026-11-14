import SwiftUI

/// Full-screen player, shown as a sheet: swipe down or tap the chevron to minimize.
struct NowPlayingView: View {
    @ObservedObject var preview: Preview
    let url: (Track) -> URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var backdrop: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if let t = preview.current {
                    VStack(spacing: 0) {
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                                    .frame(width: 44, height: 44, alignment: .leading)
                            }
                            Spacer()
                        }
                        Spacer(minLength: 8)
                        ArtworkView(track: t, url: url(t), side: min(geo.size.width - 56, geo.size.height * 0.44),
                                    pixels: 900, corner: 14)
                            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                            .scaleEffect(preview.isPlaying ? 1 : 0.86)
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: preview.isPlaying)
                        Spacer(minLength: 24)
                        titleBlock(t)
                        scrubber.padding(.top, 20)
                        controls.padding(.top, 20)
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: preview.current == nil) { gone in if gone { dismiss() } }
        .task(id: preview.current?.location) {
            guard let t = preview.current, let u = url(t) else { backdrop = nil; return }
            backdrop = await ArtworkCache.shared.image(key: t.location, url: u, pixels: 160)
        }
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            if let backdrop {
                Image(uiImage: backdrop).resizable().scaledToFill().blur(radius: 70).opacity(0.55)
            }
        }
        .ignoresSafeArea()
    }

    private func titleBlock(_ t: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.title.isEmpty ? "Untitled" : t.title).font(.title3.weight(.bold)).lineLimit(1)
            Text(t.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
            if !t.album.isEmpty { Text(t.album).font(.footnote).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { scrubbing ? scrub : preview.position }, set: { scrub = $0 }),
                in: 0...max(preview.duration, 1),
                onEditingChanged: { editing in
                    if editing { scrub = preview.position; scrubbing = true }
                    else { preview.seek(scrub); scrubbing = false }
                }
            )
            .tint(.primary)
            HStack {
                Text(fmt(scrubbing ? scrub : preview.position))
                Spacer()
                Text("-" + fmt(max(preview.duration - (scrubbing ? scrub : preview.position), 0)))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 48) {
            Button { preview.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 30)) }
            Button { preview.togglePlayPause() } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 52))
                    .frame(width: 60)
            }
            Button { preview.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)) }
                .disabled(!preview.hasNext)
        }
        .foregroundStyle(.primary)
    }

    private func fmt(_ s: Double) -> String {
        let n = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}
