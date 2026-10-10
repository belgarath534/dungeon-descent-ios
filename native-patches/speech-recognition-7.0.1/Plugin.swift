import Foundation
import Capacitor
import Speech

@objc(SpeechRecognition)
public class SpeechRecognition: CAPPlugin {

    let defaultMatches = 5
    let messageMissingPermission = "Missing permission"
    let messageAccessDenied = "User denied access to speech recognition"
    let messageRestricted = "Speech recognition restricted on this device"
    let messageNotDetermined = "Speech recognition not determined on this device"
    let messageAccessDeniedMicrophone = "User denied access to microphone"
    let messageOngoing = "Ongoing speech recognition"
    let messageUnknown = "Unknown error occured"

    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    @objc func available(_ call: CAPPluginCall) {
        guard let recognizer = SFSpeechRecognizer() else {
            call.resolve([
                "available": false
            ])
            return
        }
        call.resolve([
            "available": recognizer.isAvailable
        ])
    }

    @objc func start(_ call: CAPPluginCall) {
        if let engine = self.audioEngine, engine.isRunning {
            call.reject(self.messageOngoing)
            return
        }

        let status: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        if status != SFSpeechRecognizerAuthorizationStatus.authorized {
            call.reject(self.messageMissingPermission)
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if !granted {
                call.reject(self.messageAccessDeniedMicrophone)
                return
            }

            let language: String = call.getString("language") ?? "en-US"
            let maxResults: Int = call.getInt("maxResults") ?? self.defaultMatches
            let partialResults: Bool = call.getBool("partialResults") ?? false

            // Crash fix: the old session's callback can still fire after a new
            // session starts and used to clear the new session's request, so a
            // forced unwrap of it crashed the app. Each session now keeps its
            // own engine and request and only ever cleans up its own.
            if let oldTask = self.recognitionTask {
                self.recognitionTask = nil
                oldTask.cancel()
            }
            if let oldEngine = self.audioEngine {
                oldEngine.stop()
                oldEngine.inputNode.removeTap(onBus: 0)
            }

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = partialResults
            self.audioEngine = engine
            self.recognitionRequest = request

            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
                call.reject(self.messageUnknown)
                return
            }
            self.speechRecognizer = recognizer

            let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.playAndRecord, options: AVAudioSession.CategoryOptions.defaultToSpeaker)
                try audioSession.setMode(AVAudioSession.Mode.default)
                do {
                    try audioSession.setActive(true, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation)
                } catch {
                      call.reject("Microphone is already in use by another application.")
                      return
                }
            } catch {

            }

            let inputNode: AVAudioInputNode = engine.inputNode
            let format: AVAudioFormat = inputNode.outputFormat(forBus: 0)
            // A microphone format of 0 Hz (for example during a phone call)
            // makes installTap throw and crash the app, so stop here instead.
            if format.sampleRate <= 0 || format.channelCount == 0 {
                call.reject("Microphone is not available right now.")
                return
            }

            var finished = false
            let finish = {
                if finished { return }
                finished = true
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
                if self.audioEngine === engine {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.notifyListeners("listeningState", data: ["status": "stopped"])
                }
            }

            self.recognitionTask = recognizer.recognitionTask(with: request, resultHandler: { (result, error) in
                DispatchQueue.main.async {
                    if let result = result {
                        let resultArray: NSMutableArray = NSMutableArray()
                        var counter: Int = 0

                        for transcription: SFTranscription in result.transcriptions {
                            if maxResults > 0 && counter < maxResults {
                                resultArray.add(transcription.formattedString)
                            }
                            counter+=1
                        }

                        if partialResults {
                            self.notifyListeners("partialResults", data: ["matches": resultArray])
                        } else {
                            call.resolve([
                                "matches": resultArray
                            ])
                        }

                        if result.isFinal {
                            finish()
                        }
                    }

                    if let error = error {
                        finish()
                        call.reject(error.localizedDescription)
                    }
                }
            })

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
                request.append(buffer)
            }

            engine.prepare()
            do {
                try engine.start()
                self.notifyListeners("listeningState", data: ["status": "started"])
                if partialResults {
                    call.resolve()
                }
            } catch {
                finish()
                call.reject(self.messageUnknown)
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
            if let engine = self.audioEngine, engine.isRunning {
                engine.stop()
                self.recognitionRequest?.endAudio()
                self.notifyListeners("listeningState", data: ["status": "stopped"])
            }
            call.resolve()
        }
    }

    @objc func isListening(_ call: CAPPluginCall) {
        let isListening = self.audioEngine?.isRunning ?? false
        call.resolve([
            "listening": isListening
        ])
    }

    @objc func getSupportedLanguages(_ call: CAPPluginCall) {
        let supportedLanguages: Set<Locale>! = SFSpeechRecognizer.supportedLocales() as Set<Locale>
        let languagesArr: NSMutableArray = NSMutableArray()

        for lang: Locale in supportedLanguages {
            languagesArr.add(lang.identifier)
        }

        call.resolve([
            "languages": languagesArr
        ])
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        let status: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        let permission: String
        switch status {
        case .authorized:
            permission = "granted"
        case .denied, .restricted:
            permission = "denied"
        case .notDetermined:
            permission = "prompt"
        @unknown default:
            permission = "prompt"
        }
        call.resolve(["speechRecognition": permission])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        SFSpeechRecognizer.requestAuthorization { (status: SFSpeechRecognizerAuthorizationStatus) in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    AVAudioSession.sharedInstance().requestRecordPermission { (granted: Bool) in
                        if granted {
                            call.resolve(["speechRecognition": "granted"])
                        } else {
                            call.resolve(["speechRecognition": "denied"])
                        }
                    }
                    break
                case .denied, .restricted, .notDetermined:
                    self.checkPermissions(call)
                    break
                @unknown default:
                    self.checkPermissions(call)
                }
            }
        }
    }
}
