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

let boardW = Float(boardWidth + 3) * tileSize
let boardH = Float(boardHeight + 1) * tileSize

let needW = Float(boardWidth + 9) * tileSize
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

    var leftScore: Int = 0
    var scoreLeftMesh: TextQuadMesh? = nil
    var rightScore: Int = 0
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
    
    // get correct texture position depending on the grid connections
    func getTextureX(gridConnections: Int) -> Float {
        let textureUnitX: Float = 1.0 / 16.0
        return grid_codep[gridConnections] * textureUnitX
    }
    
    // get correct tile position X
    func getIdealTilePositionX(i: Int) -> Float {
        return Float(i) * tileSize + tileSize / 2.0 - Float(boardWidth + 2) / 2.0 * tileSize
    }
    
    // get correct tile position Y
    func getIdealTilePositionY(j: Int) -> Float {
        return Float(j) * tileSize + tileSize / 2.0 - Float(boardHeight) / 2.0 * tileSize
    }
    
    // function to create ONE tile quad based on its position and gameBoard connections
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
//            print ("created new quad mesh based on gbc ", Int(gameBoard.connections[i - 1][j]!.connections), "at ", i, j)
        }

        let topLeftUV = SIMD2<Float>(textureX, textureY)
        let bottomRightUV = SIMD2<Float>(textureX + textureUnitX, textureY + textureUnitY)

        let quad = QuadMesh(size: tileSize, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
        // appropriate positions for the tile
        quad.position = SIMD2<Float>(Float(i) * tileSize + tileSize / 2.0 - Float(boardWidth + 2) / 2.0 * tileSize,
                                     Float(j) * tileSize + tileSize / 2.0 - Float(boardHeight) / 2.0 * tileSize)
        quad.rotation = 0.0
        quad.scale = 1.0
        
        return quad
    }

    // function to remake the score meshes
    func updateScoreMeshes() {
        // create text meshes for keeping score
        var text = "INDIGO\n\(leftScore) points"
        let font = Font.systemFont(ofSize: 32)

        if (renderer != nil) {
            renderer!.textLayer.meshes.removeAll { $0 === scoreLeftMesh }
            renderer!.textLayer.meshes.removeAll { $0 === scoreRightMesh }
        }

        let textSize = CGSize(width: 256, height: 128)
        scoreLeftMesh = TextQuadMesh(text: text, font: font, color: Color.magenta, size: textSize)
        scoreLeftMesh?.position = SIMD2<Float>(-needW / 2.0 + tileSize * 1.75, -needH / 2.0 + tileSize * 2.0)
        text = "ORANGE\n\(rightScore) points"
        scoreRightMesh = TextQuadMesh(text: text, font: font, color: Color.orange, size: textSize)
        scoreRightMesh?.position = SIMD2<Float>(needW / 2.0 - tileSize * 1.75, -needH / 2.0 + tileSize * 2.0)
        
        if (renderer != nil) {
            renderer!.textLayer.meshes.append(scoreLeftMesh!)
            renderer!.textLayer.meshes.append(scoreRightMesh!)
        }
    }
    
    // function to create ALL tileQuads when initializing
    func createTiles() {
        for i in 0..<boardWidth + 2 {
            for j in 0..<boardHeight {
                tileQuads[j][i] = createNewTileQuad(i: i, j: j)
            }
        }

        updateScoreMeshes()
    }

    // method to update tileQuads based on the new connections table
    func zapRemoveConnectionsCreateNewAndMakeThemFall() {
        SoundManager.shared.playSoundEffect(filename: "explode")
        // first remove from the tile matrix and generate new tiles
        gameBoard?.removeAndShiftConnectingTiles()
        // now our business - remove old and create new tile quads
        // and set up animations for them to fall into place
        for x in 1..<boardWidth + 1 {
            var newTilePosition = getIdealTilePositionY(j: 0) - Float(tileSize)
            var shiftedItems = 0
            for y in (0..<boardHeight).reversed() {
                if gameBoard?.connectMarkings[x - 1][y] == .ok {
                    // make an explosion out of it
                    animationManager?.addParticleAnimation(speedLimit: 10.0, width: 4.0, count: 10, duration: 2.0, tilePosition: (x: x - 1, y: y), targetScreen: renderer!.gameScreen)
                    // but make sure to remake the marking
                    gameBoard?.connectMarkings[x - 1][y] = .ok
                    shiftedItems += 1
                    // Shift tileQuads above downward - only in the tileQuads matrix
                    if y >= 1 {
                        for shiftY in (1...y).reversed() {
                            tileQuads[shiftY][x] = tileQuads[shiftY - 1][x]
                        }
                    }
                }
            }
//            print ("on column ", x, " we shifted ", shiftedItems, " tileQuads down")
            for y in (0..<shiftedItems).reversed() {
                // do NOT update their positions, let them stand where they are
                // will add an animation later to bring them down
                // Create new tileQuad at the top
                tileQuads[y][x] = createNewTileQuad(i: x, j: y)
                if let quad = tileQuads[y][x] {
                    quad.position.y = newTilePosition
                    newTilePosition -= Float(tileSize) // generate the next one even higher above
                }
            }
        }
        for x in 1..<boardWidth + 1 {
            for y in 0..<boardHeight {
                // as mentioned above, if a tile is above where it should be
                // then generate an animation to bring it down
                if let quad = tileQuads[y][x], quad.position.y < getIdealTilePositionY(j: y) {
                    animationManager?.addFallAnimation(quad: quad, targetY: getIdealTilePositionY(j: y), tilePosition: (x: x - 1, y: y))
                }
            }
        }
    }

    // function that does what it has to do when a tile is tapped
    func tapTile(i: Int, j: Int) {
        // play that sound
        SoundManager.shared.playSoundEffect(filename: "rotate")
        
        gameBoard?.connections[i][j]?.rotate()
        let newQuad = createNewTileQuad(i: i + 1, j: j)
        tileQuads[j][i + 1] = newQuad
        animationManager?.addRotateAnimation(quad: newQuad!, duration: 0.2, tilePosition: (x: i, y: j), objectsLayer: renderer!.objectsLayer, effectsLayer: renderer!.effectsLayer)
    }
    
    // function that handles frame by frame updates
    func update() {
        guard let renderer = renderer else { print("NO RENDERER? return");return }
        // ...
        // check for input
        if self.lastInput != nil {
            SoundManager.shared.playSoundEffect(filename: "bop")
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
            let quadX = Int(round((gameX + boardW / 2.0) / tileSize) - 1)
            let quadY = Int(round((gameY + boardH / 2.0) / tileSize) - 1)
            if quadX >= 0 && quadX < boardWidth + 2 && quadY >= 0 && quadY < boardWidth {
//                tileQuads[quadY][quadX]?.position = SIMD2<Float>(gameX, gameY)
                if quadX >= 1 && quadX < boardWidth + 1 {
                    print ("hit the board at ", quadX - 1, quadY)
                    tapTile(i: quadX - 1, j: quadY)
                }
            }
            self.lastInput = nil
        }
        // move those animations
        animationManager?.updateAnimations()
        // check connections
        if gameBoard?.checkConnections() != 0 {
            // wait, who gets the points?
            print ("left pins connected: ", gameBoard!.leftPinsConnect)
            print ("right pins connected: ", gameBoard!.rightPinsConnect)
            
            leftScore += gameBoard!.leftPinsConnect
            rightScore += gameBoard!.rightPinsConnect
/*
            if gameBoard!.leftPinsConnect > gameBoard!.rightPinsConnect {
                Particle.attractor = scoreLeftMesh!.position
            } else if gameBoard!.leftPinsConnect < gameBoard!.rightPinsConnect {
                Particle.attractor = scoreRightMesh!.position
            } else {
                Particle.attractor = SIMD2<Float> (0.0, 1000.0)
            }
*/
            Particle.attractor = SIMD2<Float> (0.0, tileSize * Float(boardHeight))
            animationManager?.addFreezeFrameAnimation(duration: 2.0)
            updateScoreMeshes()
            zapRemoveConnectionsCreateNewAndMakeThemFall()
        }
    }

    // function to clean up and remake electric arcs when the board changes
    // call after checkConnections
    func remakeElectricArcs(forMarker: Connection, withColor: SegmentColor, po2: Int, andWidth: Float) {
        guard let gameBoard = gameBoard, let renderer = renderer else { return }
        
        var preferredColor: SegmentColor = withColor

        // Recreate arcs based on connections
        for y in 0..<gameBoard.height {
            // make those pins BRIGHT RED to see them better
            if forMarker == .ok {
                preferredColor = .red
            }
            // check leftmost connections with the pins
            if forMarker == gameBoard.connectMarkings[0][y] {
                if let tile = gameBoard.connections[0][y] {
                    if tile.hasConnection(direction: .left) {
                        let start = tileQuads[y][0]!.position
                        let end = tileQuads[y][1]!.position
                        let arc = ElectricArcMesh(startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: preferredColor)
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
                        let arc = ElectricArcMesh(startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: preferredColor)
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
                                let arc = ElectricArcMesh(startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                                renderer.effectsLayer.meshes.append(arc)
                            }
                        }
                        // top-to-bottom
                        if tile.hasConnection(direction: .down), y < gameBoard.height - 1 {
                            if let downTile = gameBoard.connections[x][y + 1], downTile.hasConnection(direction: .up) {
                                let start = tileQuads[y][x + 1]!.position
                                let end = tileQuads[y + 1][x + 1]!.position
                                let arc = ElectricArcMesh(startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                                renderer.effectsLayer.meshes.append(arc)
                            }
                        }
                    }
                }
            }
        }
    }

    // function to call when getting input from mouse or touch
    // - converted to game coordinates
    func notifyInput(at point: CGPoint) {
        self.lastInput = CGPoint(x: point.x, y: point.y)
        print("got some input at ", self.lastInput!.x, self.lastInput!.y)
    }
}
