//
//  GameManager.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif

import Foundation
import simd

let boardWidth = 10
let boardHeight = 10

enum GameScreen: Int {
    case loading = 0
    case mainMenu = 1
    case pauseMenu = 2
    case playing = 3
    case options = 4
}


class GameManager {
    // might or might not have
    var gameBoard: GameBoard?
    var renderer: Renderer?
    var animationManager: AnimationManager?
    var tileQuads: [[QuadMesh?]]
    var lastInput: CGPoint
    
    init() {
        gameBoard = GameBoard(width: boardWidth, height: boardHeight)
        animationManager = AnimationManager(gameBoard: gameBoard!)
        self.lastInput = CGPointZero

        // Initialize tileQuads array with nil values
        self.tileQuads = Array(repeating: Array(repeating: nil, count: boardWidth + 2), count: boardHeight)

        // Create and configure the tiles
        createTiles()
    }

    func createTiles() {
        guard let gameBoard = gameBoard else { print("NO GAME BOARD? return");return }
        guard let renderer = renderer else { print("NO RENDERER? return");return }

        let tileSize: Float = 50.0
        let textureUnitX: Float = 1.0 / 16.0
        let textureUnitY: Float = 1.0 / 8.0

        for i in 0..<boardWidth + 2 {
            for j in 0..<boardHeight {
                let textureX: Float
                if i == 0 {
                    textureX = 12.0 / 16.0
                } else if i == boardWidth + 1 {
                    textureX = 14.0 / 16.0
                } else {
                    textureX = Float(gameBoard.connections[i - 1][j]!.connections) * textureUnitX
                }

                let topLeftUV = SIMD2<Float>(textureX, 0)
                let bottomRightUV = SIMD2<Float>(textureX + textureUnitX, textureUnitY)

                let quad = QuadMesh(device: renderer.device, size: tileSize, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
                print("created quad for tile (", i-1, ", ", j, ")")
                quad.position = SIMD2<Float>(Float(i) * tileSize + tileSize / 2.0 - Float(boardWidth + 2) / 2.0 * tileSize,
                                             Float(j) * tileSize + tileSize / 2.0 - Float(boardHeight) / 2.0 * tileSize)
                quad.rotation = 0.0
                quad.scale = 1.0

                tileQuads[j][i] = quad
            }
        }
    }

    func update() {
        // move those animations
        animationManager?.updateAnimations()
        // check whether any of them are blocking
        // ...
        // Additional game update logic
        // ...
        // check connections
        gameBoard?.checkConnections()
    }

    func notifyInput(at point: CGPoint) {
        self.lastInput = CGPoint(x: point.x, y: point.y)
        print("got some input at ", self.lastInput.x, self.lastInput.y)
    }
}
