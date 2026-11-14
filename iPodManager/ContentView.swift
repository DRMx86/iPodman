import SwiftUI
import UniformTypeIdentifiers

private enum ImportMode { case folder, songs }

struct ContentView: View {
    @StateObject private var lib = IPodLibrary()
    @StateObject private var preview = Preview()
    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var editing: Track?
    @State private var deleting: Track?
    @State private var search = ""

    private var filtered: [Track] {
        guard !search.isEmpty else { return lib.tracks }
        return lib.tracks.filter {
            [$0.title, $0.artist, $0.album].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if lib.isConnected { songList } else { emptyState }
            }
            .navigationTitle(lib.isConnected ? lib.deviceName : "iPod Manager")
            .toolbar { if lib.isConnected { toolbarContent } }
            .safeAreaInset(edge: .bottom) { if preview.current != nil { miniPlayer } }
            .overlay { if lib.busy { busyOverlay } }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importMode == .folder ? [.folder] : [.audio],
            allowsMultipleSelection: importMode == .songs
        ) { result in
            switch result {
            case .success(let urls):
                if importMode == .folder, let u = urls.first { lib.connect(u) }
                else if importMode == .songs { Task { await lib.addSongs(urls) } }
            case .failure(let e):
                lib.errorMessage = e.localizedDescription
            }
        }
        .sheet(item: $editing) { t in
            EditSheet(track: t) { lib.update($0) }
        }
        .confirmationDialog(
            "Delete from iPod?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { t in
            Button("Delete “\(t.title)”", role: .destructive) {
                if preview.current?.id == t.id { preview.stop() }
                lib.delete(t)
            }
        } message: { _ in Text("The file is removed from the iPod.") }
        .alert("Error",
               isPresented: Binding(get: { lib.errorMessage != nil }, set: { if !$0 { lib.errorMessage = nil } }),
               actions: { Button("OK", role: .cancel) {} },
               message: { Text(lib.errorMessage ?? "") })
    }

    private func pick(_ m: ImportMode) { importMode = m; showImporter = true }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "ipod").font(.system(size: 64, weight: .thin)).foregroundStyle(.secondary)
            Text("Connect your iPod").font(.title2.weight(.semibold))
            Text("Put the iPod in disk mode, plug it in, then choose its root folder in Files.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { pick(.folder) } label: {
                Label("Choose iPod", systemImage: "externaldrive").frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
    }

    private var songList: some View {
        List {
            ForEach(filtered) { t in
                TrackRow(track: t, isCurrent: preview.current?.id == t.id, isPlaying: preview.isPlaying)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let u = lib.url(for: t) { preview.toggle(t, url: u) }
                        else { lib.errorMessage = "Can’t find the audio file for this song." }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = t } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
                    }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Search songs")
        .overlay {
            if lib.tracks.isEmpty {
                Text("No songs on this iPod").foregroundStyle(.secondary)
            }
        }
        .refreshable { try? lib.reload() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Toggle("Write without checksum (experimental)", isOn: $lib.allowUnsigned)
                Button("Reload") { try? lib.reload() }
                Button("Disconnect", role: .destructive) { preview.stop(); lib.disconnect() }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { pick(.songs) } label: { Image(systemName: "plus") }
        }
    }

    private var miniPlayer: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(preview.current?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(preview.current?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { if let t = preview.current, let u = lib.url(for: t) { preview.toggle(t, url: u) } } label: {
                    Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { preview.stop() } label: { Image(systemName: "xmark").font(.callout) }
                    .foregroundStyle(.secondary).padding(.leading, 8)
            }
            Slider(value: Binding(get: { preview.position }, set: { preview.seek($0) }),
                   in: 0...max(preview.duration, 1))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var busyOverlay: some View {
        ProgressView("Working…")
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 44, height: 44)
                Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? "Untitled" : track.title).lineLimit(1)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(duration).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var duration: String {
        let s = track.durationMs / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct EditSheet: View {
    @State private var track: Track
    let onSave: (Track) -> Void
    @Environment(\.dismiss) private var dismiss

    init(track: Track, onSave: @escaping (Track) -> Void) {
        _track = State(initialValue: track)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $track.title)
                    TextField("Artist", text: $track.artist)
                    TextField("Album", text: $track.album)
                    TextField("Genre", text: $track.genre)
                }
                Section {
                    TextField("Track number", value: $track.trackNumber, format: .number).keyboardType(.numberPad)
                    TextField("Year", value: $track.year, format: .number.grouping(.never)).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(track); dismiss() }.disabled(track.title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
