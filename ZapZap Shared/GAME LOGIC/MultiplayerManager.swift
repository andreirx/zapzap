//
//  MultiplayerManager.swift
//  ZapZap
//
//  Created by apple on 10.09.2024.
//

import Foundation
import GameKit
import GameplayKit

class MultiplayerManager: NSObject, GKMatchmakerViewControllerDelegate, GKMatchDelegate {

    // error messages get written into the multiStatusMesh every time they change
    var errorMsg: String = "" {
        didSet {
            Renderer.updateText(mesh: &multiStatusMesh, onLayer: renderer!.multiplayerButtonsLayer, withText: errorMsg, fontSize: 32, color: Color.yellow, size: CGSize(width: 512, height: 512))
            multiStatusMesh?.position = SIMD2<Float>(0.0, 1.0 * tileSize)
        }
    }
    var playerName: String = "not authenticated" {
        didSet {
            Renderer.updateText(mesh: &playerMesh, onLayer: renderer!.multiplayerButtonsLayer, withText: "Hello, \(playerName)", fontSize: 32, color: Color.white, size: CGSize(width: 256, height: 64))
            playerMesh?.position = SIMD2<Float>(1.0 * tileSize, -boardH / 2.0 + tileSize * 3.25)
        }
    }
    
    var multiStatusMesh: TextQuadMesh? = nil
    var playerMesh: TextQuadMesh? = nil

    var match: GKMatch?

    var gameBoard: GameBoard?
    var renderer: Renderer?
    
    func updateStatusMesh() {
        // create text meshes for keeping score
        var text = errorMsg
        let font = Font.systemFont(ofSize: 32)

        if (renderer != nil) {
            if renderer!.multiplayerButtonsLayer != nil {
                renderer!.multiplayerButtonsLayer.meshes.removeAll { $0 === multiStatusMesh }
            }
        }

        let textSize = CGSize(width: 512, height: 512)
        multiStatusMesh = TextQuadMesh(text: text, font: font, color: Color.yellow, size: textSize)
        multiStatusMesh?.position = SIMD2<Float>(0.0, 1.0 * tileSize)
        
        if (renderer != nil) {
            if renderer!.multiplayerButtonsLayer != nil {
                renderer!.multiplayerButtonsLayer.meshes.append(multiStatusMesh!)
            }
        }
    }
    
    func isHost() -> Bool {
        guard let match = self.match else { return false }
        // The player with the lowest index in the match's player array is considered the host
        if let firstPlayer = match.players.first {
            return GKLocalPlayer.local == firstPlayer
        }
        return false
    }

    // MARK: - local player authentication and related stuff

    // Call this to authenticate the player
    func authenticatePlayer() {
        let localPlayer = GKLocalPlayer.local
        
        localPlayer.authenticateHandler = { viewController, error in
            if let vc = viewController {
                // Present the Game Center login view controller
                if let rootVC = self.renderer?.viewController {
                    #if os(iOS)
                    // iOS: Present the view controller with animation
                    rootVC.present(vc, animated: true, completion: nil)
                    #elseif os(macOS)
                    // macOS: Present the view controller with a custom animator
                    rootVC.present(vc, animator: CustomAnimator())
                    #endif
                }
            } else if localPlayer.isAuthenticated {
                print("Player authenticated with Game Center. Name: \(localPlayer.displayName)")
                // Now you can use the player's display name
                self.playerAuthenticated()
            } else {
                if let error = error {
                    self.errorMsg = "Game Center authentication failed: \(error.localizedDescription)"
                    print(self.errorMsg)
                } else {
                    self.errorMsg = "Game Center is not available."
                    print(self.errorMsg)
                }
            }
        }
    }

    // Called when the player is authenticated
    func playerAuthenticated() {
        playerName = GKLocalPlayer.local.displayName
        print("Hello, \(playerName)")
        // Here you can update the UI or notify the game that the player is authenticated.
        // For example, pass this information to your game screens or store it for future use
    }

    // MARK: - GKMatchmakerViewControllerDelegate methods

    // Present the Game Center matchmaking UI
    func presentGameCenterMatchmaking() {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        // Create and configure the matchmaking UI
        let matchmakerVC = GKMatchmakerViewController(matchRequest: request)
        matchmakerVC?.matchmakerDelegate = self // Set self as the delegate

        // Present the matchmaking UI (handled by Game Center)
        if let rootVC = renderer?.viewController {
            #if os(iOS)
            // iOS: Present with animation
            rootVC.present(matchmakerVC!, animated: true, completion: nil)
            #elseif os(macOS)
            // macOS: Present with a custom animator
            rootVC.present(matchmakerVC!, animator: CustomAnimator())
            #endif
        }
    }

    // Called when a match is found
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        #if os(iOS)
        viewController.dismiss(animated: true, completion: nil)
        #elseif os(macOS)
        viewController.dismiss(nil)
        #endif
        
        self.match = match
        match.delegate = self

        print("Match found: \(match)")
        if match.expectedPlayerCount == 0 {
            startMatchWithSeed()
        } else {
            print("Waiting for other players to join...")
        }
    }

    // Called when matchmaking is cancelled by the user
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        #if os(iOS)
        viewController.dismiss(animated: true, completion: nil)
        #elseif os(macOS)
        viewController.dismiss(nil)
        #endif
        self.errorMsg = "Player cancelled matchmaking"
        print(self.errorMsg)
    }

    // Called when matchmaking fails due to an error
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        #if os(iOS)
        viewController.dismiss(animated: true, completion: nil)
        #elseif os(macOS)
        viewController.dismiss(nil)
        #endif
        showError(error: error)
    }

    // Show errors based on the situation
    func showError(error: Error) {
        // Handle known GKError codes
        if let gkError = error as? GKError {
            switch gkError.code {
            case .notAuthenticated:
                errorMsg = "You are not signed into Game Center."
            case .communicationsFailure:
                errorMsg = "Network is unavailable. Please check your internet connection."
            case .connectionTimeout:
                errorMsg = "Matchmaking timed out."
            case .cancelled:
                errorMsg = "Matchmaking was cancelled."
            case .notAuthorized:
                errorMsg = "You are not authorized to do this."
            default:
                errorMsg = "An unknown error occurred: \(gkError.localizedDescription)"
            }
        } else {
            errorMsg = "An unknown error occurred: \(error.localizedDescription)"
        }
    }
    
    // MARK: start game, send, receive data

    func startMatchWithSeed() {
        if isHost() {
            print("You are the host! Generating seed...")
            let seed = UInt64.random(in: 0...UInt64.max)
            sendSeed(seed: seed)
            // Initialize game board with seed
            // TODO actual code
        } else {
            print("You are the guest! Waiting for host's seed...")
            // TODO actual code
            errorMsg = "Waiting for the other player..."
            // or just wait
        }
    }

    // send the entire board to the other player for verification
    func sendBoardState() {
        guard let match = self.match else { return }
        
        do {
            // Encode the board connections
            let boardData = try JSONEncoder().encode(gameBoard?.connections)
            
            // Send with a "GBRD" identifier
            var messageData = Data("GBRD".utf8)
            messageData.append(boardData)
            
            try match.sendData(toAllPlayers: messageData, with: .reliable)
        } catch {
            print("Error sending board state: \(error)")
        }
    }

    // send seed to the other player at the stert of a match
    func sendSeed(seed: UInt64) {
        guard let match = self.match else { return }
        
        // Combine the identifier "SEED" with the seed value
        var seedData = Data("SEED".utf8)
        let seedBytes = withUnsafeBytes(of: seed) { Data($0) }
        seedData.append(seedBytes)
        
        do {
            try match.sendData(toAllPlayers: seedData, with: .reliable)
        } catch {
            print("Error sending seed: \(error)")
        }
    }

    // send move to the other player
    func sendTileTap(x: Int, y: Int) {
        guard let match = self.match else { return }
        
        // Combine the identifier "TAP@" with the coordinates
        var tapData = Data("TAP@".utf8)
        let coordinates = "\(x),\(y)".data(using: .utf8)!
        tapData.append(coordinates)
        
        do {
            try match.sendData(toAllPlayers: tapData, with: .reliable)
        } catch {
            print("Error sending tap: \(error)")
        }
    }

    // Handle receiving the seed from the opponent
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        // Convert the first few bytes to a string to determine the message type
        let messageType = String(data: data.prefix(4), encoding: .utf8)
        
        if messageType == "SEED" {
            // Handle receiving the seed
            let seedData = data.dropFirst(4)
            let seed: UInt64 = seedData.withUnsafeBytes { $0.load(as: UInt64.self) }
            
            // Initialize the board with the received seed
            // TODO actual code

            print("Received seed: \(seed)")
        } else if messageType == "TAP@" {
            // Handle receiving a tap
            let tapData = data.dropFirst(4)
            if let tapString = String(data: tapData, encoding: .utf8) {
                let coordinates = tapString.split(separator: ",").map { Int($0) ?? 0 }
                let x = coordinates[0]
                let y = coordinates[1]
                
                // Update the game board with the received tap
                print("Received tap at (\(x), \(y))")
                // TODO actual code
            }
        }else if messageType == "GBRD" {
            // Handle receiving board state
            let boardData = data.dropFirst(4) // "GBRD" is 4 bytes
            do {
                let boardConnections = try JSONDecoder().decode(BoardConnections.self, from: boardData)
                
                // compare the game board with the received state
                // TODO actual code
                print("Received full board state")
            } catch {
                print("Error decoding board state: \(error)")
            }
        }

        print("DEBUG multiplayer received: ", data)
    }
}


// MARK: custom animator for macOS GameScreen popups

#if os(macOS)
import Cocoa

class CustomAnimator: NSObject, NSViewControllerPresentationAnimator {
    func animatePresentation(of viewController: NSViewController, from fromViewController: NSViewController) {
        fromViewController.view.addSubview(viewController.view)
        viewController.view.frame = fromViewController.view.bounds
        viewController.view.alphaValue = 0.0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            viewController.view.animator().alphaValue = 1.0
        })
    }

    func animateDismissal(of viewController: NSViewController, from fromViewController: NSViewController) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            viewController.view.animator().alphaValue = 0.0
        }, completionHandler: {
            viewController.view.removeFromSuperview()
        })
    }
}
#endif
