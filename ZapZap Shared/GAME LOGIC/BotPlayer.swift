//
//  BotPlayer.swift
//  ZapZap
//
//  Created by apple on 09.10.2024.
//

import Foundation

class BotPlayer {
    weak var gameBoard: GameBoard?

    init(gameBoard: GameBoard) {
        self.gameBoard = gameBoard
    }

    func determineNextMove() -> (tilePosition: (x: Int, y: Int), rotationCount: Int)? {
        guard let originalBoard = gameBoard else { return nil }

        // Create a deep copy of the GameBoard
        let board = originalBoard.copy()

        var bestMove: (x: Int, y: Int)?
        var bestRotationCount: Int = 0
        var bestScore = 0

        // Iterate over every tile on the board
        // TODO: choose to skip some tiles depending on difficulty
        for x in 0..<board.width {
            for y in 0..<board.height {
                // Get the current tile
                guard let tile = board.connections.connections[x][y] else { continue }

                // Skip tiles that have single connections (1, 2, 4, 8) or full connections (15)
                if [1, 2, 4, 8, 15].contains(tile.connections) {
                    continue
                }

                // Simulate rotating this tile
                let originalConnections = board.connections.connections[x][y]?.connections
//                board.connections.connections[x][y]?.rotate()
                
                // Simulate rotating the tile up to 3 times
                for rotationCount in 1...3 {
                    // Rotate the tile
                    tile.rotate()

                    // Evaluate the current board state after rotation
                    let score = evaluateConnections(board: board)

                    // If this rotation is better than the previous best, save it
                    if score > bestScore {
                        bestScore = score
                        bestMove = (x, y)
                        bestRotationCount = rotationCount
                    }
                }
            }
        }

        // Return the best move and how many rotations are needed
        if let bestMove = bestMove {
            return (tilePosition: bestMove, rotationCount: bestRotationCount)
        } else {
            return nil
        }
    }

    private func evaluateConnections(board: GameBoard) -> Int {
        // Expand connections from the rightmost pin (simulate checkConnections)
        var score = 0
        let zap = board.checkConnections()
        if zap != 0 {
            // count the connected tiles and multiply by 2
            for j in 0..<board.height {
                for i in 0..<board.width {
                    if board.connectMarkings[i][j] == .ok {
                        score += 2
                    }
                }
            }
        } else {
            // if not connected, count the right connected tiles
            for j in 0..<board.height {
                for i in 0..<board.width {
                    if board.connectMarkings[i][j] == .right {
                        score += 1
                        // pin connecting tiles get bonus points
                        if i == board.width - 1 {
                            if board.connections.connections[i][j]!.hasConnection(direction: .right) {
                                score += 3
                            }
                        }
                    }
                }
            }
        }
        return score
    }
}
