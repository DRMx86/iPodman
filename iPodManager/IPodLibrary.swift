import Foundation

@MainActor
final class IPodLibrary: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName = ""
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var allowUnsigned = UserDefaults.standard.bool(forKey: "allowUnsigned") {
        didSet { UserDefaults.standard.set(allowUnsigned, forKey: "allowUnsigned") }
    }

    private(set) var root: URL?
    private var db: ITunesDatabase?
    private var scoped = false
    private let fm = FileManager.default
    private let bookmarkKey = "ipodBookmark"

    private var dbURL: URL? {
        guard let root else { return nil }
        let dir = root.appendingPathComponent("iPod_Control/iTunes")
        let cdb = dir.appendingPathComponent("iTunesCDB")      // nano 5G+ keep the real library here
        return fm.fileExists(atPath: cdb.path) ? cdb : dir.appendingPathComponent("iTunesDB")
    }
    var isReadOnly: Bool { db?.readOnly ?? false }

    init() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            connect(url, silent: true)
        }
    }

    // MARK: Connection

    func connect(_ url: URL, silent: Bool = false) {
        release()
        scoped = url.startAccessingSecurityScopedResource()
        root = url
        do {
            try reload()
            isConnected = true
            deviceName = url.lastPathComponent
            if isReadOnly { errorMessage = DBError.readOnly.errorDescription }
            if let b = try? url.bookmarkData() { UserDefaults.standard.set(b, forKey: bookmarkKey) }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
            release()
        }
    }

    func disconnect() {
        release()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private func release() {
        if scoped { root?.stopAccessingSecurityScopedResource() }
        scoped = false; root = nil; db = nil; tracks = []; isConnected = false
    }

    func reload() throws {
        guard let url = dbURL, fm.fileExists(atPath: url.path) else { throw DBError.notFound }
        db = try ITunesDatabase(bytes: Bytes(try Data(contentsOf: url)))
        refresh()
    }

    private func refresh() {
        tracks = (db?.tracks ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func url(for t: Track) -> URL? {
        guard let root else { return nil }
        let rel = t.location.split(separator: ":").joined(separator: "/")
        return rel.isEmpty ? nil : root.appendingPathComponent(rel)
    }

    // MARK: Persistence

    private func save() throws {
        guard let db, let url = dbURL else { return }
        let out = try db.serialized(allowUnsigned: allowUnsigned)
        let backup = url.appendingPathExtension("bak")      // original kept once
        if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        try Data(out).write(to: url)
    }

    // MARK: Operations

    func addSongs(_ urls: [URL]) async {
        guard let root, let db else { return }
        busy = true
        defer { busy = false }
        var copied: [URL] = []
        var failures: [String] = []

        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let format = AudioFormat(ext: url.pathExtension) else {
                    throw DBError.unsupportedFormat(url.pathExtension)
                }
                let meta = await MetadataReader.read(url)
                let (dest, loc) = try newDestination(root: root, ext: url.pathExtension.lowercased())
                try fm.copyItem(at: url, to: dest)
                copied.append(dest)
                let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                db.addTrack(meta, format: format, size: size, location: loc)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !copied.isEmpty {
            do { try save() } catch {
                copied.forEach { try? fm.removeItem(at: $0) }
                try? reload()
                errorMessage = error.localizedDescription
                return
            }
        }
        refresh()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    func update(_ t: Track) {
        db?.update(t)
        do { try save(); refresh() } catch { errorMessage = error.localizedDescription; try? reload() }
    }

    func delete(_ t: Track) {
        let file = url(for: t)
        db?.remove(id: t.id)
        do {
            try save()
            if let file { try? fm.removeItem(at: file) }
            refresh()
        } catch { errorMessage = error.localizedDescription; try? reload() }
    }

    private func newDestination(root: URL, ext: String) throws -> (URL, String) {
        let music = root.appendingPathComponent("iPod_Control/Music")
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for _ in 0..<50 {
            let folder = String(format: "F%02d", Int.random(in: 0..<50))
            let name = String((0..<4).map { _ in letters.randomElement()! }) + "." + ext
            let dir = music.appendingPathComponent(folder)
            let file = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) { continue }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return (file, ":iPod_Control:Music:\(folder):\(name)")
        }
        throw DBError.corrupt("no free file name")
    }
}
