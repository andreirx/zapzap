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
let tileSize: Float = 50.0

let needW = Float(boardWidth + 3) * tileSize
let needH = Float(boardHeight + 1) * tileSize

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
    var lastInput: CGPoint?
    
    // these are the correct texture positions (to be divided by 16.0) based on the connection code
    let grid_codep: [Float] = [
        0.0, 12.0, 15.0, 5.0, 14.0, 1.0, 4.0, 7.0, 13.0, 6.0, 2.0, 8.0, 3.0, 9.0, 10.0, 11.0
    ]

    init() {
        gameBoard = GameBoard(width: boardWidth, height: boardHeight)
        animationManager = AnimationManager(gameBoard: gameBoard!)
        self.lastInput = nil

        // Initialize tileQuads array with nil values
        self.tileQuads = Array(repeating: Array(repeating: nil, count: boardWidth + 2), count: boardHeight)

        // Create and configure the tiles
        createTiles()
    }

    func createTiles() {
        guard let gameBoard = gameBoard else { print("NO GAME BOARD? return");return }
        guard let renderer = renderer else { print("NO RENDERER? return");return }

        let textureUnitX: Float = 1.0 / 16.0
        let textureUnitY: Float = 1.0 / 8.0

        for i in 0..<boardWidth + 2 {
            for j in 0..<boardHeight {
                let textureX: Float
                let textureY: Float
                if i == 0 {
                    textureX = 12.0 / 16.0
                    textureY = 3.0 * textureUnitY
                } else if i == boardWidth + 1 {
                    textureX = 14.0 / 16.0
                    textureY = 3.0 * textureUnitY
                } else {
                    let gridIndex = Int(gameBoard.connections[i - 1][j]!.connections)
                    textureX = grid_codep[gridIndex] * textureUnitX
                    textureY = 1.0 * textureUnitY
                }

                let topLeftUV = SIMD2<Float>(textureX, textureY)
                let bottomRightUV = SIMD2<Float>(textureX + textureUnitX, textureY + textureUnitY)

                let quad = QuadMesh(device: renderer.device, size: tileSize, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
                quad.position = SIMD2<Float>(Float(i) * tileSize + tileSize / 2.0 - Float(boardWidth + 2) / 2.0 * tileSize,
                                             Float(j) * tileSize + tileSize / 2.0 - Float(boardHeight) / 2.0 * tileSize)
                quad.rotation = 0.0
                quad.scale = 1.0

                tileQuads[j][i] = quad
            }
        }
    }

    func update() {
        guard let renderer = renderer else { print("NO RENDERER? return");return }
        // move those animations
        animationManager?.updateAnimations()
        // check whether any of them are blocking
        // ...
        // check for input
        if self.lastInput != nil {
            let screenW = Float(renderer.view.drawableSize.width)
            let screenH = Float(renderer.view.drawableSize.height)
            let horizRatio = screenW / needW
            let vertRatio = screenH / needH
            var gameX: Float
            var gameY: Float
            if horizRatio < vertRatio {
                gameX = (Float(self.lastInput!.x) - (screenW / 2.0)) / horizRatio
                gameY = (Float(self.lastInput!.y) - (screenH / 2.0)) / horizRatio
            } else {
                gameX = (Float(self.lastInput!.x) - (screenW / 2.0)) / vertRatio
                gameY = (Float(self.lastInput!.y) - (screenH / 2.0)) / vertRatio
            }
            print("converting to game coordinates... (", gameX, ", ", gameY, ")")
            tileQuads[0][0]?.position = SIMD2<Float>(gameX, gameY)
            self.lastInput = nil
        }
        // Additional game update logic
        // ...
        // check connections
        gameBoard?.checkConnections()
    }

    func notifyInput(at point: CGPoint) {
        self.lastInput = CGPoint(x: point.x, y: point.y)
        print("got some input at ", self.lastInput!.x, self.lastInput!.y)
    }
}
