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
    
    var errorMsg: String = ""
    
    var match: GKMatch?
    var gameBoard: GameBoard?
    
    func isHost() -> Bool {
        guard let match = self.match else { return false }
        // The player with the lowest index in the match's player array is considered the host
        if let firstPlayer = match.players.first {
            return GKLocalPlayer.local == firstPlayer
        }
        return false
    }

    // MARK: - GKMatchmakerViewControllerDelegate methods

    // Called when a match is found
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(true)
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
        viewController.dismiss(true)
        print("Player cancelled matchmaking")
    }

    // Called when matchmaking fails due to an error
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        viewController.dismiss(true)
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
