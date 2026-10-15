import AVFoundation
import UIKit

/// Keeps Croc running while you switch to another app during a transfer.
///
/// iOS suspends apps shortly after they leave the foreground, which would drop a transfer
/// that is still waiting for the other side. Two things are used while a transfer runs:
///  - a background task (a few extra minutes at most), and
///  - an inaudible audio loop, which together with the "audio" background mode lets the app
///    stay alive for as long as the transfer does. This costs some battery and is meant for
///    sideloaded builds; the App Store would not accept it for a file-transfer app.
@MainActor
final class BackgroundKeepAlive {
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    func start(useAudio: Bool) {
        beginTask()
        if useAudio { startAudio() }
    }

    func stop() {
        player?.stop()
        player = nil
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        endTask()
    }

    // MARK: Background task

    private func beginTask() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "croc-transfer") { [weak self] in
            Task { @MainActor in self?.endTask() }
        }
    }

    private func endTask() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    // MARK: Silent audio

    private func startAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }

        guard player == nil, let player = try? AVAudioPlayer(data: Self.silentWAV()) else { return }
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
        self.player = player

        // Calls and alarms interrupt audio; pick it back up afterwards.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.player?.play()
            }
        }
    }

    /// One second of 16-bit mono silence as a WAV file, built in memory.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(sampleRate) * 2
        var data = Data()
        func append32(_ value: UInt32) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 4)) }
        func append16(_ value: UInt16) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 2)) }

        data.append(Data("RIFF".utf8)); append32(36 + dataSize)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8)); append32(16)
        append16(1); append16(1)                  // PCM, mono
        append32(sampleRate); append32(sampleRate * 2)
        append16(2); append16(16)                 // block align, bits per sample
        data.append(Data("data".utf8)); append32(dataSize)
        data.append(Data(count: Int(dataSize)))   // silence
        return data
    }
}
