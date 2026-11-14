import AVFoundation

@MainActor
final class Preview: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    private var queue: [Track] = []
    private var urlFor: (@MainActor (Track) -> URL?)?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private var index: Int? { queue.firstIndex { $0.id == current?.id } }
    var hasNext: Bool { index.map { $0 + 1 < queue.count } ?? false }
    var hasPrevious: Bool { index.map { $0 > 0 } ?? false }

    /// Starts `t` (or toggles pause if it is already the current song).
    func play(_ t: Track, in queue: [Track], urlFor: @escaping @MainActor (Track) -> URL?) {
        if current?.id == t.id, player != nil { togglePlayPause(); return }
        self.queue = queue
        self.urlFor = urlFor
        start(t)
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play() }
        isPlaying.toggle()
    }

    func next() {
        guard let i = index, i + 1 < queue.count else { return }
        start(queue[i + 1])
    }

    func previous() {
        guard let i = index else { return }
        if position > 3 || i == 0 { seek(0) } else { start(queue[i - 1]) }
    }

    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func stop() {
        teardown()
        current = nil; isPlaying = false; position = 0; duration = 0; queue = []
    }

    // MARK: Private

    private func start(_ t: Track) {
        guard let url = urlFor?(t) else { stop(); return }
        teardown()
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
            Task { @MainActor in self?.advance() }
        }
        p.play(); isPlaying = true

        if t.durationMs == 0 {
            Task {
                if let d = try? await item.asset.load(.duration), d.seconds.isFinite { self.duration = d.seconds }
            }
        }
    }

    private func advance() {
        if hasNext { next() }
        else { isPlaying = false; player?.seek(to: .zero); position = 0 }
    }

    private func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        player?.pause()
        player = nil; timeObserver = nil; endObserver = nil
    }
}
