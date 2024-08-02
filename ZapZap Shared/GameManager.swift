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

let boardWidth = 12
let boardHeight = 12
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
    
    var scoreLeftMesh: TextQuadMesh? = nil
    var scoreRightMesh: TextQuadMesh? = nil
    
    // these are the correct texture positions (to be divided by 16.0) based on the connection code
    let grid_codep: [Float] = [
        0.0, 12.0, 15.0, 5.0, 14.0, 1.0, 4.0, 7.0, 13.0, 6.0, 2.0, 8.0, 3.0, 9.0, 10.0, 11.0
    ]

    init() {
        // TODO: fix the missing links do not leave it magic like this
        gameBoard = GameBoard(width: boardWidth, height: boardHeight, missingLinks: 5)
        self.lastInput = nil

        // Initialize tileQuads array with nil values
        self.tileQuads = Array(repeating: Array(repeating: nil, count: boardWidth + 2), count: boardHeight)

        // create the animationManager
        animationManager = AnimationManager(gameManager: self)

        // Create and configure the tiles
        createTiles()
    }
    
    func getTextureX(gridConnections: Int) -> Float {
        let textureUnitX: Float = 1.0 / 16.0
        return grid_codep[gridConnections] * textureUnitX
    }
    
    func createNewTileQuad(i: Int, j: Int) -> QuadMesh? {
        guard let gameBoard = gameBoard else { return nil }
        guard let renderer = renderer else { return nil }
        if i < 0 || i >= boardWidth + 2 || j < 0 || j >= boardHeight {
            return nil
        }
        
        let textureUnitX: Float = 1.0 / 16.0
        let textureUnitY: Float = 1.0 / 8.0

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
            textureX = getTextureX(gridConnections: gridIndex)
            textureY = 1.0 * textureUnitY
            print ("created new quad mesh based on gbc ", Int(gameBoard.connections[i - 1][j]!.connections), "at ", i, j)
        }

        let topLeftUV = SIMD2<Float>(textureX, textureY)
        let bottomRightUV = SIMD2<Float>(textureX + textureUnitX, textureY + textureUnitY)

        let quad = QuadMesh(device: renderer.device, size: tileSize, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
        quad.position = SIMD2<Float>(Float(i) * tileSize + tileSize / 2.0 - Float(boardWidth + 2) / 2.0 * tileSize,
                                     Float(j) * tileSize + tileSize / 2.0 - Float(boardHeight) / 2.0 * tileSize)
        quad.rotation = 0.0
        quad.scale = 1.0
        
        return quad
    }

    func createTiles() {
        guard let gameBoard = gameBoard else { return }
        guard let renderer = renderer else { return }

        let textureUnitX: Float = 1.0 / 16.0
        let textureUnitY: Float = 1.0 / 8.0

        for i in 0..<boardWidth + 2 {
            for j in 0..<boardHeight {
                tileQuads[j][i] = createNewTileQuad(i: i, j: j)
            }
        }

        // create text meshes for keeping score
        var text = "INDIGO\n0 points"
        let font = Font.systemFont(ofSize: 32)
//        let color = Color.magenta
        let textSize = CGSize(width: 256, height: 128)
        scoreLeftMesh = TextQuadMesh(device: renderer.device, text: text, font: font, color: Color.magenta, size: textSize)
        scoreLeftMesh?.position = SIMD2<Float>(-needW / 2.0 - tileSize * 3.0, -needH / 2.0 + tileSize * 2.0)
        text = "ORANGE\n0 points"
        scoreRightMesh = TextQuadMesh(device: renderer.device, text: text, font: font, color: Color.orange, size: textSize)
        scoreRightMesh?.position = SIMD2<Float>(needW / 2.0 + tileSize * 3.0, -needH / 2.0 + tileSize * 2.0)
    }

    func update() {
        guard let renderer = renderer else { print("NO RENDERER? return");return }
        // ...
        // check for input
        if self.lastInput != nil {
            // converting from screen coordinates to game coordinates
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
            // and then convert to tile coordinates to check if the user is interacting with the board
            let quadX = Int(round((gameX + needW / 2.0) / tileSize) - 1)
            let quadY = Int(round((gameY + needH / 2.0) / tileSize) - 1)
            if quadX >= 0 && quadX < boardWidth + 2 && quadY >= 0 && quadY < boardWidth {
//                tileQuads[quadY][quadX]?.position = SIMD2<Float>(gameX, gameY)
                if quadX >= 1 && quadX < boardWidth + 1 {
                    print ("hit the board at ", quadX - 1, quadY)
                    gameBoard?.connections[quadX - 1][quadY]?.rotate()
                    let newQuad = createNewTileQuad(i: quadX, j: quadY)
                    tileQuads[quadY][quadX] = newQuad
                    let animation = RotateAnimation(quad: newQuad!, duration: 1, tilePosition: (x: quadX - 1, y: quadY), objectsLayer: renderer.objectsLayer, effectsLayer: renderer.effectsLayer)
                    animationManager?.addAnimation(animation)

                    Particle.attractor = scoreLeftMesh!.position
                    let particleAnimation = ParticleAnimation(speedLimit: 20.0, width: 4.0, color: .red, count: 100, duration: 10.0, tilePosition: (x: quadX - 1, y: quadY), effectsLayer: renderer.effectsLayer)
                    animationManager?.addAnimation(particleAnimation)
                }
            }
            self.lastInput = nil
        }
        // move those animations
        animationManager?.updateAnimations()
        // check whether any of them are blocking
        // Additional game update logic
        // ...
        // check connections - NOT HERE NOT ANYMORE - only check when an animation starts or finishes
        // gameBoard?.checkConnections()
    }

    func remakeElectricArcs(forMarker: Connection, withColor: SegmentColor, po2: Int, andWidth: Float) {
        guard let gameBoard = gameBoard, let renderer = renderer else { return }

        // Recreate arcs based on connections
        for y in 0..<gameBoard.height {
            // check leftmost connections with the pins
            if forMarker == gameBoard.connectMarkings[0][y] {
                if let tile = gameBoard.connections[0][y] {
                    if tile.hasConnection(direction: .left) {
                        let start = tileQuads[y][0]!.position
                        let end = tileQuads[y][1]!.position
                        let arc = ElectricArcMesh(device: renderer.device, startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                        renderer.effectsLayer.meshes.append(arc)
                    }
                }
            }
            // check rightmost connections with the pins
            if forMarker == gameBoard.connectMarkings[gameBoard.width - 1][y] {
                if let tile = gameBoard.connections[gameBoard.width - 1][y] {
                    if tile.hasConnection(direction: .right) {
                        let start = tileQuads[y][gameBoard.width]!.position
                        let end = tileQuads[y][gameBoard.width + 1]!.position
                        let arc = ElectricArcMesh(device: renderer.device, startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                        renderer.effectsLayer.meshes.append(arc)
                    }
                }
            }
            // check the rest of the table
            for x in 0..<gameBoard.width {
                if let tile = gameBoard.connections[x][y] {
                    if forMarker == gameBoard.connectMarkings[x][y] {
                        // For each connection direction, create an arc if connected
                        // right-to-left
                        if tile.hasConnection(direction: .right), x < gameBoard.width - 1 {
                            if let rightTile = gameBoard.connections[x + 1][y], rightTile.hasConnection(direction: .left) {
                                let start = tileQuads[y][x + 1]!.position
                                let end = tileQuads[y][x + 2]!.position
                                let arc = ElectricArcMesh(device: renderer.device, startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                                renderer.effectsLayer.meshes.append(arc)
                            }
                        }
                        // top-to-bottom
                        if tile.hasConnection(direction: .down), y < gameBoard.height - 1 {
                            if let downTile = gameBoard.connections[x][y + 1], downTile.hasConnection(direction: .up) {
                                let start = tileQuads[y][x + 1]!.position
                                let end = tileQuads[y + 1][x + 1]!.position
                                let arc = ElectricArcMesh(device: renderer.device, startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                                renderer.effectsLayer.meshes.append(arc)
                            }
                        }
                    }
                }
            }
        }
    }

    func notifyInput(at point: CGPoint) {
        self.lastInput = CGPoint(x: point.x, y: point.y)
        print("got some input at ", self.lastInput!.x, self.lastInput!.y)
    }
}
