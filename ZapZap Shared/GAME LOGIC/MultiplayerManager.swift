//
//  MultiplayerManager.swift
//  ZapZap
//
//  Created by apple on 10.09.2024.
//

import Foundation
import GameKit
import GameplayKit

class MultiplayerManager: NSObject, GKMatchDelegate {
    var match: GKMatch?
    var gameBoard: GameBoard?

    func startMatchWithSeed() {
        // Host generates the seed
        let seed = UInt64.random(in: 0...UInt64.max)
        
        // Send the seed to the opponent
        sendSeed(seed: seed)

        // Initialize the game board with the seed
        // TODO actual code
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
