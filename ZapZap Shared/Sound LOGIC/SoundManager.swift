//
//  SoundManager.swift
//  ZapZap
//
//  Created by apple on 07.08.2024.
//

import Foundation
import AVFoundation


class SoundManager: NSObject {
    static let shared = SoundManager()

    private var backgroundMusicPlayer: AVAudioPlayer?
    private var isSoundEffectsEnabled: Bool = true
    private var isBackgroundMusicEnabled: Bool = true
    private var activeSoundEffectPlayers: [AVAudioPlayer] = []

    private override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #endif
    }

    // MARK: - Background Music
/*
 "Itty Bitty 8 Bit" Kevin MacLeod (incompetech.com)
 Licensed under Creative Commons: By Attribution 4.0 License
 http://creativecommons.org/licenses/by/4.0/
*/
/*
 "8bit Dungeon Level" Kevin MacLeod (incompetech.com)
 Licensed under Creative Commons: By Attribution 4.0 License
 http://creativecommons.org/licenses/by/4.0/
*/
    func playBackgroundMusic(filename: String, fileExtension: String = "mp3") {
        guard isBackgroundMusicEnabled else { return }
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        guard !audioSession.isOtherAudioPlaying else {
            print("Other audio is playing, not playing background music.")
            return
        }
        #endif

        if let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) {
            do {
                backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
                backgroundMusicPlayer?.numberOfLoops = -1 // Loop indefinitely
                backgroundMusicPlayer?.play()
            } catch {
                print("Could not create audio player for background music: \(error)")
            }
        } else {
            print("Could not find file: \(filename).\(fileExtension)")
        }
    }

    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
        backgroundMusicPlayer = nil
    }

    func toggleBackgroundMusic() {
        if isBackgroundMusicEnabled {
            stopBackgroundMusic()
        } else {
            playBackgroundMusic(filename: "IttyBitty") // Provide your background music file name
        }
        isBackgroundMusicEnabled.toggle()
    }

    // MARK: - Sound Effects

    func playSoundEffect(filename: String, fileExtension: String = "wav") {
        guard let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            print("Could not find file: \(filename).\(fileExtension)")
            return
        }
        var player: AVAudioPlayer?

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            player!.delegate = self
            activeSoundEffectPlayers.append(player!)
        } catch {
            print("Could not create audio player: \(error)")
        }
    }

    func toggleSoundEffects() {
        isSoundEffectsEnabled.toggle()
    }
}

// MARK: - AVAudioPlayerDelegate
extension SoundManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Remove the player from the list once it finishes playing
        if let index = activeSoundEffectPlayers.firstIndex(of: player) {
            activeSoundEffectPlayers.remove(at: index)
        }
    }
}
