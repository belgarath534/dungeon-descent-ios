import SwiftUI
import UniformTypeIdentifiers

/// My Tracks (the web version's IndexedDB "dd_tracks"): audio files you
/// chose, copied into the app; audio links, downloaded once and kept (Dropbox
/// and Google Drive share links work too); YouTube links; and songs from your
/// Apple Music library. All kept between launches.
@MainActor
final class MyTracks: ObservableObject {
    static let shared = MyTracks()

    struct Track: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        /// A file in the app's MyTracks folder, or a link.
        var file: String?
        var url: String?
        /// nil for files and audio links; "youtube" or "applemusic".
        var kind: String? = nil
        /// An Apple Music song's library id.
        var persistentID: String? = nil
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

    /// YouTube links (YouTubeTrack in MyTracksSources.swift); off for now.
    static let youTube = false

    /// loadCustomTrackURL: a direct audio link. Nil and a reason when it can't be used.
    func add(link raw: String) -> (Track?, String?) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil else {
            return (nil, "Paste a full audio link starting with https://.")
        }
        let id = "track-\(Int(Date().timeIntervalSince1970 * 1000))"
        if let yt = TrackLinks.youTubeID(u) {
            // Off for now: playing YouTube's audio without its video is
            // against YouTube's terms, and App Review can reject it (5.2.3).
            guard Self.youTube else {
                return (nil, "YouTube links can't be played. Use an audio file, a song from Apple Music, or a direct audio link.")
            }
            let t = Track(id: id, name: "YouTube \(yt)", file: nil, url: s, kind: "youtube")
            tracks.append(t)
            save()
            return (t, nil)
        }
        let direct = TrackLinks.direct(u)
        let name = u.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Custom Track"
        let t = Track(id: id, name: name.isEmpty || name == "view" ? "Custom Track" : name, file: nil, url: direct.absoluteString)
        tracks.append(t)
        save()
        download(t, from: direct)
        return (t, nil)
    }

    /// Links are downloaded once, so they play without the internet later
    /// (the web version streamed them every time).
    private func download(_ t: Track, from u: URL) {
        Task {
            guard let (tmp, resp) = try? await URLSession.shared.download(from: u),
                  ((resp as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return }
            let ext = resp.suggestedFilename.map { ($0 as NSString).pathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "mp3"
            let dest = folder.appendingPathComponent(t.id + "." + ext)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil,
                  let i = tracks.firstIndex(where: { $0.id == t.id }) else { return }
            tracks[i].file = dest.lastPathComponent
            save()
        }
    }

    /// Songs picked from Apple Music.
    func add(songs: [(id: String, title: String)]) -> [Track] {
        let base = Int(Date().timeIntervalSince1970 * 1000)
        let new = songs.enumerated().map { i, song in
            Track(id: "track-\(base + i)", name: song.title, file: nil, url: nil, kind: "applemusic", persistentID: song.id)
        }
        tracks += new
        save()
        return new
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
    @State private var pickingMusic = false
    @State private var link = ""
    @State private var status = ""
    @State private var playing: String? = AudioEngine.shared.customLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MY TRACKS").font(Theme.cinzel(9.9)).tracking(2.5).foregroundStyle(Theme.goldDim)
                .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.borderDim).frame(height: 1)
            Text("Play your own music instead of the game soundtrack: a file, a song from Apple Music, or a link (audio, Dropbox or Google Drive). They're saved here.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            if my.tracks.isEmpty {
                Text("No saved tracks yet.").font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim).padding(.vertical, 4)
            }
            ForEach(my.tracks) { t in
                HStack(spacing: 8) {
                    Button("🎵 \(t.name)" as String) { play(t) }
                        .font(Theme.cinzel(11)).foregroundStyle(playing == t.name ? Theme.gold : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).padding(.horizontal, 10)
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .accessibilityLabel("Play \(t.name)" as String)
                    Button("✕") { my.delete(t); if playing == t.name { playing = nil } ; Feedback.announce("\(t.name) deleted.") }
                        .font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xc06060))
                        .padding(.vertical, 4).padding(.horizontal, 8).overlay(Rectangle().stroke(Color(hex: 0x6a2020)))
                        .accessibilityLabel("Delete \(t.name)" as String)
                }
            }
            Button("📁 Choose Audio File") { picking = true }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Choose audio file from your device")
            #if os(iOS) && !targetEnvironment(macCatalyst)
            Button("🎧 Choose from Apple Music") { chooseMusic() }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Choose songs from your Apple Music library")
            #endif
            HStack(spacing: 6) {
                TextField("Paste an audio link...", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(Theme.cinzel(11)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityLabel("Paste an audio, Dropbox or Google Drive link")
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
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .sheet(isPresented: $pickingMusic) {
            AppleMusicPicker { items in
                pickingMusic = false
                let songs = items.map { (id: String($0.persistentID), title: $0.title ?? "Apple Music song") }
                guard !songs.isEmpty else { return }
                let added = my.add(songs: songs)
                Feedback.announce("\(added.count) song\(added.count == 1 ? "" : "s") added to My Tracks.")
                if let first = added.first { play(first) }
            }
            .ignoresSafeArea()
        }
        #endif
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            guard case .success(let u) = result else { return }
            if let t = my.add(file: u) { play(t) } else { status = "✕ That file couldn't be loaded."; Feedback.announce("That file couldn't be loaded.") }
        }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func chooseMusic() {
        Task {
            if await AppleMusicTrack.ask() { pickingMusic = true }
            else {
                status = "✕ Dungeon Descent can't see your music library. Allow it in the Settings app."
                Feedback.announce("Dungeon Descent can't see your music library. Allow Media and Apple Music for Dungeon Descent in the Settings app.")
            }
        }
    }
    #endif

    private func play(_ t: MyTracks.Track) {
        switch t.kind {
        case "youtube":
            guard MyTracks.youTube else {
                status = "✕ YouTube links can't be played anymore. Delete this one and add a file or an Apple Music song."
                Feedback.announce("YouTube links can't be played anymore. Delete this one and add a file or an Apple Music song.")
                return
            }
            guard let s = t.url, let u = URL(string: s), let id = TrackLinks.youTubeID(u) else { return }
            YouTubeTrack.shared.play(id: id, label: t.name)
        case "applemusic":
            #if os(iOS) && !targetEnvironment(macCatalyst)
            guard let pid = t.persistentID, AppleMusicTrack.play(persistentID: pid, label: t.name) else {
                status = "✕ That song isn't in your library anymore."
                Feedback.announce("That song isn't in your library anymore.")
                return
            }
            #else
            return
            #endif
        default:
            guard let u = my.url(t) else { return }
            AudioEngine.shared.playCustom(u, label: t.name)
        }
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
