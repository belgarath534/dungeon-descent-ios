import SwiftUI
import UniformTypeIdentifiers

/// My Tracks (the web version's IndexedDB "dd_tracks"): audio files you
/// chose, copied into the app, and audio links, kept between launches.
@MainActor
final class MyTracks: ObservableObject {
    static let shared = MyTracks()

    struct Track: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        /// A file in the app's MyTracks folder, or a link.
        var file: String?
        var url: String?
    }

    @Published private(set) var tracks: [Track] = []

    private var folder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MyTracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var index: URL { folder.appendingPathComponent("tracks.json") }

    init() {
        if let d = try? Data(contentsOf: index), let v = try? JSONDecoder().decode([Track].self, from: d) { tracks = v }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(tracks) { try? d.write(to: index) }
    }

    func url(_ t: Track) -> URL? {
        if let f = t.file { return folder.appendingPathComponent(f) }
        return t.url.flatMap(URL.init(string:))
    }

    /// loadCustomTrackFile: copied in, so it still plays next time.
    func add(file picked: URL) -> Track? {
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        let id = "track-\(Int(Date().timeIntervalSince1970 * 1000))"
        let name = picked.deletingPathExtension().lastPathComponent
        let dest = folder.appendingPathComponent(id + "." + (picked.pathExtension.isEmpty ? "mp3" : picked.pathExtension))
        do { try FileManager.default.copyItem(at: picked, to: dest) } catch { return nil }
        let t = Track(id: id, name: name, file: dest.lastPathComponent, url: nil)
        tracks.append(t)
        save()
        return t
    }

    /// loadCustomTrackURL: a direct audio link. Nil and a reason when it can't be used.
    func add(link raw: String) -> (Track?, String?) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil else {
            return (nil, "Paste a full audio link starting with https://.")
        }
        if let h = u.host?.lowercased(), h.contains("youtube.com") || h.contains("youtu.be") {
            return (nil, "YouTube links can't be played in the iPhone app. Use a direct audio link or choose a file.")
        }
        let name = u.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Custom Track"
        let t = Track(id: "track-\(Int(Date().timeIntervalSince1970 * 1000))", name: name.isEmpty ? "Custom Track" : name, file: nil, url: s)
        tracks.append(t)
        save()
        return (t, nil)
    }

    func delete(_ t: Track) {
        if let f = t.file { try? FileManager.default.removeItem(at: folder.appendingPathComponent(f)) }
        tracks.removeAll { $0.id == t.id }
        save()
        if AudioEngine.shared.customLabel == t.name { AudioEngine.shared.stopCustom() }
    }
}

/// The music player's MY TRACKS section and CUSTOM TRACK controls.
struct MyTracksSection: View {
    @ObservedObject private var my = MyTracks.shared
    @State private var picking = false
    @State private var link = ""
    @State private var status = ""
    @State private var playing: String? = AudioEngine.shared.customLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MY TRACKS").font(Theme.cinzel(9.9)).tracking(2.5).foregroundStyle(Theme.goldDim)
                .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.borderDim).frame(height: 1)
            Text("Play your own music instead of the game soundtrack. Choose a file or paste a direct audio link; both are saved here.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            if my.tracks.isEmpty {
                Text("No saved tracks yet.").font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim).padding(.vertical, 4)
            }
            ForEach(my.tracks) { t in
                HStack(spacing: 8) {
                    Button("🎵 \(t.name)") { play(t) }
                        .font(Theme.cinzel(11)).foregroundStyle(playing == t.name ? Theme.gold : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).padding(.horizontal, 10)
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .accessibilityLabel("Play \(t.name)")
                    Button("✕") { my.delete(t); if playing == t.name { playing = nil } ; Feedback.announce("\(t.name) deleted.") }
                        .font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xc06060))
                        .padding(.vertical, 4).padding(.horizontal, 8).overlay(Rectangle().stroke(Color(hex: 0x6a2020)))
                        .accessibilityLabel("Delete \(t.name)")
                }
            }
            Button("📁 Choose Audio File") { picking = true }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Choose audio file from your device")
            HStack(spacing: 6) {
                TextField("Paste an audio link...", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(Theme.cinzel(11)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityLabel("Paste a direct audio link")
                Button("🔗 Load") { loadLink() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Load audio from link")
            }
            if !status.isEmpty { Text(status).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.gold) }
            if playing != nil {
                Button("■ Stop Custom Track") {
                    AudioEngine.shared.stopCustom()
                    playing = nil
                    status = ""
                    Feedback.announce("Custom track stopped. Game music resumed.")
                }
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xc06060)).frame(maxWidth: .infinity).padding(10)
                .overlay(Rectangle().stroke(Color(hex: 0x6a2020)))
                .accessibilityLabel("Stop custom track and return to game music")
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            guard case .success(let u) = result else { return }
            if let t = my.add(file: u) { play(t) } else { status = "✕ That file couldn't be loaded."; Feedback.announce("That file couldn't be loaded.") }
        }
    }

    private func play(_ t: MyTracks.Track) {
        guard let u = my.url(t) else { return }
        AudioEngine.shared.playCustom(u, label: t.name)
        playing = t.name
        let short = t.name.count > 40 ? String(t.name.prefix(40)) + "..." : t.name
        status = "▶ Now playing: \(short)"
        Feedback.announce("Custom track playing. \(short).")
    }

    private func loadLink() {
        let (t, problem) = my.add(link: link)
        if let problem { status = "✕ " + problem; Feedback.announce(problem); return }
        link = ""
        if let t { play(t) }
    }
}
