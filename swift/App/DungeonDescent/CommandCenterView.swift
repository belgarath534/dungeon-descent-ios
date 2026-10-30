import SwiftUI
import Speech
import AVFoundation
import DungeonCore

/// #ov-command-center: type or speak commands to control the game.
struct CommandCenterView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var voice = VoiceCommand()
    @State private var cc = CommandCenter()
    @State private var input = ""
    @State private var lines: [CommandCenter.Line] = [
        .init(text: "Dungeon Descent Command Center v1.0", kind: .info),
        .init(text: "Type help to see all available commands.", kind: .info),
        .init(text: "──────────────────────────────", kind: .info),
    ]
    @FocusState private var focused: Bool

    private static let quick: [(String, String, String)] = [
        ("▶ AFK", "start afk", "Start AFK run"), ("⚒ Blacksmith", "go blacksmith", "Go to Blacksmith"),
        ("🗼 Spire", "go spire", "Go to Spire"), ("🔥 Daily", "claim daily", "Claim daily reward"),
        ("💰 Gold", "gold", "Check gold"), ("🧙 Create Character", "create character", "Create a new character"),
        ("📖 Chronicles", "go chronicles", "Go to Chronicles"), ("🎉 Events", "go events", "Check events"),
        ("❓ Help", "help", "Show help"),
    ]

    var body: some View {
        WebScreen {
            ScreenHeader(title: "⌨️ Command Center")
            Text("Type a command or tap the mic to speak. Type help to see all commands.")
                .font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x666666))
            HStack(spacing: 8) {
                TextField("Type a command...", text: $input)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(Theme.cinzel(13.6)).padding(12)
                    .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { execute() }
                    .accessibilityLabel("Command input")
                if voice.available {
                    Button(voice.listening ? "🔴" : "🎤") { voice.listening ? voice.stop() : voice.start { heard($0) } }
                        .padding(12).background(Color(hex: 0x0a0a0a))
                        .overlay(Rectangle().stroke(voice.listening ? Color(hex: 0xff4444) : Color(hex: 0x333333)))
                        .accessibilityLabel(voice.listening ? "Stop listening" : "Speak a command")
                }
                Button("Run ↵") { execute() }
                    .font(Theme.cinzel(11.5)).foregroundStyle(Theme.gold)
                    .padding(.vertical, 12).padding(.horizontal, 18)
                    .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Theme.gold))
                    .accessibilityLabel("Execute command")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            Text(l.text).font(.system(size: 12, design: .monospaced)).foregroundStyle(color(l.kind))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                    }
                    .padding(14)
                }
                .frame(minHeight: 120, maxHeight: 300)
                .background(Color(hex: 0x050505)).overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
                .onChange(of: lines.count) { n in withAnimation { proxy.scrollTo(n - 1, anchor: .bottom) } }
                .accessibilityLabel("Command output")
            }
            Text("QUICK COMMANDS").font(Theme.cinzel(9.3)).tracking(2.8).foregroundStyle(Color(hex: 0x555555)).padding(.top, 4)
            FlowRow(spacing: 6) {
                ForEach(Self.quick.indices, id: \.self) { i in
                    let q = Self.quick[i]
                    Button(q.0) { input = q.1; execute() }
                        .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                        .accessibilityLabel(q.2)
                }
            }
        }
        .onAppear {
            focused = true
            Feedback.announce("Command Center open. Type a command and press Run\(voice.available ? ", or tap the mic to speak" : ""). Type help to see all commands.", after: 0.4)
        }
        .onDisappear { voice.stop() }
    }

    private func color(_ k: CommandCenter.Kind) -> Color {
        switch k {
        case .cmd: return Theme.gold
        case .ok: return Color(hex: 0x44ff88)
        case .err: return Color(hex: 0xff5555)
        case .info: return Color(hex: 0x888888)
        }
    }

    private func heard(_ text: String?) {
        guard let text, !text.isEmpty else {
            lines.append(.init(text: "Did not catch that. Try typing instead.", kind: .err))
            Feedback.announce("Did not catch that.")
            return
        }
        lines.append(.init(text: "Heard: \"\(text)\"", kind: .info))
        input = text
        execute()
    }

    private func execute() {
        let raw = input
        input = ""
        let acct = CommandCenter.Account(gold: game.wallet.gold, characters: game.characters.count,
                                         fragments: jsParseInt(game.store.getItem("dd_soul_fragments")) ?? 0,
                                         coins: game.mysteryCoins)
        let r = cc.run(raw, account: acct, scheduled: CommandSchedule.shared.pending != nil)
        lines += r.lines
        if !r.spoken.isEmpty { Feedback.announce(r.spoken) }
        guard let action = r.action else { return }
        switch action {
        case .go(let dest):
            let screens: [String: Router.Screen] = ["blacksmith": .blacksmith, "spire": .spire, "chronicles": .chronicles,
                                                    "events": .events, "bestiary": .bestiary, "settings": .settings, "menu": .menu,
                                                    "highscore": .highscore, "hall of records": .records]
            if let s = screens[dest] { router.goTo(s) }
        case .afk: router.goTo(.afk)
        case .scheduleAFK(let at):
            CommandSchedule.shared.schedule(at) { [weak router] in
                router?.goTo(.afk)
                Feedback.announce("Scheduled AFK run starting now. Good morning, Descender.")
            }
        case .cancelSchedule: CommandSchedule.shared.cancel()
        case .daily:
            MainMenuView.openDailyOnAppear = true
            router.goTo(.menu)
        case .play(let track): Sound.track(track)
        case .stopMusic: Sound.stopMusic()
        case .redeem(let code): redeem(code)
        case .create(let ch, let afk):
            guard game.create(ch) else {
                lines.append(.init(text: "You already have \(GameData.maxCharacters) characters. Delete one first.", kind: .err))
                Feedback.announce("You already have the most characters you can have. Delete one first.")
                return
            }
            if afk {
                lines.append(.init(text: "\(ch.name) created! Launching AFK mode...", kind: .ok))
                Feedback.announce("\(ch.name) is ready. Launching Endless Descent.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { router.goTo(.afk) }
            } else {
                lines.append(.init(text: "\(ch.name) created and saved! Find them in your character list.", kind: .ok))
                Feedback.announce("\(ch.name) created and saved. You can find them in your character list.")
            }
        }
    }

    /// The same as Redeem Code in Void Mode.
    private func redeem(_ code: String) {
        if code == ShadowRealm.code {
            router.goTo(.shadowRealm)
            return
        }
        let out = RewardCodes.redeem(code, store: game.store)
        if out.gold > 0 { game.wallet.addGold(out.gold) }
        if out.coins > 0 { game.addMysteryCoins(out.coins) }
        if out.sword && !game.globalInventory.items.contains(where: { $0.id == "golden-sword" }) {
            game.globalInventory.add(RewardCodes.goldenSword)
        }
        lines.append(.init(text: out.message, kind: out.ok ? .ok : .err))
        Sound.sfx(out.ok ? "sfx-unlock" : "sfx-select")
        Feedback.announce(out.message)
    }
}

/// One scheduled AFK start (_ccScheduled). It goes off while the app is open.
final class CommandSchedule {
    static let shared = CommandSchedule()
    private(set) var pending: Date?
    private var timer: Timer?

    func schedule(_ at: Date, _ fire: @escaping () -> Void) {
        cancel()
        pending = at
        timer = Timer.scheduledTimer(withTimeInterval: max(1, at.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            self?.pending = nil
            self?.timer = nil
            fire()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }
}

/// The Command Center's mic: one spoken command, through iOS speech recognition.
@MainActor
final class VoiceCommand: ObservableObject {
    @Published var listening = false
    let available = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable ?? false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var done: ((String?) -> Void)?

    func start(_ done: @escaping (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    Feedback.announce("Voice commands need microphone and speech recognition permission. Enable it in your device Settings.")
                    return
                }
                self.begin(done)
            }
        }
    }

    private func begin(_ done: @escaping (String?) -> Void) {
        guard let recognizer, recognizer.isAvailable else { done(nil); return }
        self.done = done
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = false
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .mixWithOthers])
            engine.prepare()
            try engine.start()
        } catch {
            finish(nil)
            return
        }
        listening = true
        Feedback.announce("Listening. Speak your command.")
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result, result.isFinal { self.finish(result.bestTranscription.formattedString) }
                else if error != nil { self.finish(nil) }
            }
        }
        // One command: stop listening after six seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.listening == true { self?.request?.endAudio() }
        }
    }

    func stop() {
        guard listening else { return }
        request?.endAudio()
    }

    private func finish(_ text: String?) {
        guard listening || done != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        listening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let d = done
        done = nil
        d?(text)
    }
}
