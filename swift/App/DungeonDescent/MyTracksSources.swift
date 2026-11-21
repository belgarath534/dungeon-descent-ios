import SwiftUI
import WebKit
#if os(iOS) && !targetEnvironment(macCatalyst)
import MediaPlayer
#endif

// The other places My Tracks can play from: YouTube links (through the web
// version's dungen-descent.org/yt.html page, which gives YouTube the referrer
// it wants), Apple Music (your library, through iOS's own music player, so the
// volume buttons work), and Dropbox / Google Drive share links, turned into
// direct downloads.

enum TrackLinks {
    /// The YouTube video id in a youtube.com or youtu.be link.
    static func youTubeID(_ u: URL) -> String? {
        guard let host = u.host?.lowercased() else { return nil }
        if host.contains("youtu.be") { return u.pathComponents.dropFirst().first }
        guard host.contains("youtube.com") else { return nil }
        if let v = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        // youtube.com/shorts/ID, /embed/ID, /live/ID
        let parts = u.pathComponents
        if parts.count >= 3, ["shorts", "embed", "live"].contains(parts[1]) { return parts[2] }
        return nil
    }

    /// Dropbox and Google Drive share pages, as direct downloads.
    static func direct(_ u: URL) -> URL {
        guard let host = u.host?.lowercased() else { return u }
        if host.contains("dropbox.com"), var c = URLComponents(url: u, resolvingAgainstBaseURL: false) {
            var items = (c.queryItems ?? []).filter { $0.name != "dl" && $0.name != "raw" }
            items.append(URLQueryItem(name: "raw", value: "1"))
            c.queryItems = items
            return c.url ?? u
        }
        if host.contains("drive.google.com") {
            let parts = u.pathComponents
            let id = parts.firstIndex(of: "d").flatMap { parts.indices.contains($0 + 1) ? parts[$0 + 1] : nil }
                ?? URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
            if let id { return URL(string: "https://drive.google.com/uc?export=download&id=\(id)") ?? u }
        }
        return u
    }
}

/// A hidden web page that plays a YouTube video's sound.
@MainActor
final class YouTubeTrack: NSObject {
    static let shared = YouTubeTrack()
    private var web: WKWebView?

    func play(id: String, label: String) {
        stopWeb()
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        w.alpha = 0.01
        w.isUserInteractionEnabled = false
        w.isAccessibilityElement = false
        w.accessibilityElementsHidden = true
        // It has to be on screen (in the window) to play.
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        window?.addSubview(w)
        let q = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        if let u = URL(string: "https://dungen-descent.org/yt.html?v=\(q)&autoplay=1&loop=1") { w.load(URLRequest(url: u)) }
        web = w
        AudioEngine.shared.playExternal(label: label) { [weak self] in self?.stopWeb() }
    }

    private func stopWeb() {
        web?.stopLoading()
        web?.loadHTMLString("", baseURL: nil)
        web?.removeFromSuperview()
        web = nil
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// Songs from your Apple Music library, played by iOS's own music player.
@MainActor
enum AppleMusicTrack {
    static var allowed: Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    static func ask() async -> Bool {
        if allowed { return true }
        return await withCheckedContinuation { c in
            MPMediaLibrary.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    static func play(persistentID: String, label: String) -> Bool {
        guard let pid = UInt64(persistentID) else { return false }
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
        guard let items = q.items, !items.isEmpty else { return false }
        let p = MPMusicPlayerController.applicationQueuePlayer
        p.setQueue(with: MPMediaItemCollection(items: items))
        p.repeatMode = .one
        p.play()
        AudioEngine.shared.playExternal(label: label) { p.stop() }
        return true
    }
}

/// iOS's song picker.
struct AppleMusicPicker: UIViewControllerRepresentable {
    let picked: ([MPMediaItem]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let p = MPMediaPickerController(mediaTypes: .music)
        p.allowsPickingMultipleItems = true
        p.showsCloudItems = true
        p.prompt = "Choose songs for My Tracks"
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let picked: ([MPMediaItem]) -> Void
        init(picked: @escaping ([MPMediaItem]) -> Void) { self.picked = picked }
        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems c: MPMediaItemCollection) {
            mediaPicker.dismiss(animated: true)
            picked(c.items)
        }
        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            mediaPicker.dismiss(animated: true)
            picked([])
        }
    }
}
#endif
