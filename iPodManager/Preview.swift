import AVFoundation

@MainActor
final class Preview: ObservableObject {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(_ t: Track, url: URL) {
        if current?.id == t.id, let p = player {
            if isPlaying { p.pause() } else { p.play() }
            isPlaying.toggle()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p; current = t
        duration = Double(t.durationMs) / 1000; position = 0

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let s = time.seconds
            Task { @MainActor in self?.position = s.isFinite ? s : 0 }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.position = 0
            }
        }
        p.play(); isPlaying = true
    }

    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func stop() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        player?.pause()
        player = nil; timeObserver = nil; endObserver = nil
        current = nil; isPlaying = false; position = 0
    }
}
