import Cocoa
import Foundation
import Speech

class AppDelegate: NSObject, NSApplicationDelegate, SFSpeechRecognizerDelegate {
    var window: NSWindow?
    var imageView1: NSImageView?
    var imageView2: NSImageView?
    var workItem: DispatchWorkItem?
    @IBOutlet var label: NSTextField!

    var recognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioEngine = AVAudioEngine()


    func addImage(_ imageWindowRect: NSRect, _ imageView: inout NSImageView?) {
        window = NSWindow(contentRect: imageWindowRect, styleMask: .borderless, backing: .buffered, defer: false)
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.level = .floating

        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        imageView = NSImageView(frame: imageWindowRect)
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.alphaValue = 0.3
        imageView?.animates = true

        window?.contentView = imageView

        window?.makeKeyAndOrderFront(nil)
        window?.ignoresMouseEvents = true
    }

    func redSquare(_ windowRect: NSRect) {
        if !windowCreated {
            window = NSWindow(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)
            windowCreated = true
            window?.backgroundColor = NSColor.clear
            window?.isOpaque = false
            window?.level = .floating
            window?.level = NSWindow.Level.mainMenu + 1
            window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window?.makeKeyAndOrderFront(nil)
            window?.ignoresMouseEvents = true
        } else {
            window?.setContentSize(windowRect.size)
            window?.setFrameOrigin(windowRect.origin)
        }
        let view = NSView(frame: NSRect())
        view.wantsLayer = true

        window?.contentView = view
    }

    static func runBashCommand(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]

        task.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        task.launch()
        task.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let error = String(data: errData, encoding: .utf8) {
            print(error)
            do {
                try error.write(toFile: "/tmp/heater.err", atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write to file: \(error)")
            }
        }
        if let output = String(data: outData, encoding: .utf8) {
            print(output)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    func enableClickCapture() {
        let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
            callback: { (tapProxy, eventType, event, refcon) -> Unmanaged<CGEvent>? in
                var location = event.location
                if let rect = app.windows.first?.contentView?.frame {
                    print(rect, location)
                    if NSPointInRect(location, rect) {
                        exit(0)
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
    @objc func screenParametersChanged(_ notification: Notification) {
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        var specialKey1PressCount = 1
        var specialKey2PressCount = 1
        var lastKeyPressTime: TimeInterval = 0
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)


        let screenRect = NSScreen.main!.frame
        var imageWindowHeight = 36.0
        var rect = NSMakeRect(115, screenRect.size.height - imageWindowHeight + 1, screenRect.size.width - 240, imageWindowHeight)
        if screenRect.size.width == 2560 {
            imageWindowHeight -= 10
            rect = NSMakeRect(115, screenRect.size.height - imageWindowHeight + 6, screenRect.size.width / 2, imageWindowHeight)
        }
        redSquare(rect)
        window?.contentView?.layer?.backgroundColor = NSColor.black.cgColor

        label = NSTextField(frame: NSRect(x: 0, y: -10, width: rect.size.width, height: imageWindowHeight))
        label.stringValue = ""
        label.isEditable = false
        label.isBezeled = false
        label.backgroundColor = NSColor.clear
        label.alignment = .right
        label.maximumNumberOfLines = 1
        label.cell?.font = NSFont.systemFont(ofSize: 14)
        label.cell?.lineBreakMode = .byTruncatingHead

        window?.contentView?.addSubview(label)

        enableClickCapture()
        label.stringValue = ""
        recognizer = SFSpeechRecognizer()

        do {
            try self.startRecording()
        } catch let error {
            print("There was a problem starting recording: \(error.localizedDescription)")
        }
    }

    func startRecording() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object")
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.label.stringValue = "\(result.bestTranscription.formattedString)"
                // print("Text \(result.bestTranscription.formattedString)")
            } else if let error = error {
                print("There was an error: \(error.localizedDescription)")
            }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("There was an issue with starting audio engine..")
        }
    }
}

var windowCreated = false
let app = NSApplication.shared
if let window = app.windows.first {
    window.close()
}
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
