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
        gameBoard = GameBoard(width: boardWidth, height: boardHeight, missingLinks: 4)
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
            if renderer!.textLayer != nil {
                renderer!.textLayer.meshes.removeAll { $0 === scoreLeftMesh }
                renderer!.textLayer.meshes.removeAll { $0 === scoreRightMesh }
            }
        }

        let textSize = CGSize(width: 256, height: 128)
        scoreLeftMesh = TextQuadMesh(text: text, font: font, color: Color.magenta, size: textSize)
        scoreLeftMesh?.position = SIMD2<Float>(-needW / 2.0 + tileSize * 1.75, -needH / 2.0 + tileSize * 2.0)
        text = "ORANGE\n\(rightScore) points"
        scoreRightMesh = TextQuadMesh(text: text, font: font, color: Color.orange, size: textSize)
        scoreRightMesh?.position = SIMD2<Float>(needW / 2.0 - tileSize * 1.75, -needH / 2.0 + tileSize * 2.0)
        
        if (renderer != nil) {
            if renderer!.textLayer != nil {
                renderer!.textLayer.meshes.append(scoreLeftMesh!)
                renderer!.textLayer.meshes.append(scoreRightMesh!)
            }
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
    
    // method to apply the "bombing" on the table
    func bombTable(ati: Int, atj: Int) {
        // make sure we're not bombing outside
        if ati < 0 || ati >= boardWidth || atj < 0 || atj >= boardHeight {
            return
        }
        // remove the arcs
        renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
        // also "bomb" the gameTable
        gameBoard?.bombTable(ati: ati, atj: atj)
        // play exploding sound for effect
//        SoundManager.shared.playSoundEffect(filename: "bomb")
        // will remove the tiles around ati, atj
        // will "fall down" the ones above
        // will generate new ones from above
        var starti = ati - 2
        var endi = ati + 3
        var startj = atj - 2
        var endj = atj + 3
        // clip
        if starti < 0 {
            starti = 0
        }
        if endi >= boardWidth {
            endi = boardWidth
        }
        if startj < 0 {
            startj = 0
        }
        if endj >= boardHeight {
            endj = boardHeight
        }
        starti += 1
        endi += 1
        // shift down and generate
        for x in starti..<endi {
            // new tiles will be added above the first tile
            // so they can fall down
            // new tile position will be shifted as we add more tiles later
            var newTilePosition = getIdealTilePositionY(j: 0) - Float(tileSize)
            var shiftedItems = 0 // remember how many tiles we shift as we go
            // because we will have to compensate the copying position by this number
            // now do it for each column, bottom-up
            for y in (startj..<endj).reversed() {
                // Shift tiles above down
                if y >= 1 {
                    for shiftY in (1...y).reversed() {
                        // remember to compensate copying position by shiftedItems
                        tileQuads[shiftY + shiftedItems][x] = tileQuads[shiftY + shiftedItems - 1][x]
                        // Shift tileQuads above downward
                        // - only in the tileQuads matrix
                        // - their position on screen remains the same
                    }
                }
                // one more disappeared so far
                shiftedItems += 1
                // make an explosion out of it
                // at exactly x-1, y tile position
                animationManager?.addParticleAnimation(speedLimit: 10.0, width: 4.0, count: 10, duration: 2.0, tilePosition: (x: x - 1, y: y), targetScreen: renderer!.gameScreen)
            }
            for y in (0..<shiftedItems).reversed() {
                // do NOT update their positions, let them stand where they are
                // will add an animation later to bring them down
                // for now just create one more tileQuad at the top
                tileQuads[y][x] = createNewTileQuad(i: x, j: y)
                if let quad = tileQuads[y][x] {
                    quad.position.y = newTilePosition
                    newTilePosition -= Float(tileSize) // generate the next one even higher above
                }
            }
            // make animations
            for x in starti..<endi {
                for y in 0..<endj {
                    // as mentioned above, if a tile is above where it should be
                    // then generate an animation to bring it down
                    if let quad = tileQuads[y][x], quad.position.y < getIdealTilePositionY(j: y) {
                        animationManager?.addFallAnimation(quad: quad, targetY: getIdealTilePositionY(j: y), tilePosition: (x: x - 1, y: y))
                    }
                }
            }
        }
        animationManager?.addFreezeFrameAnimation(duration: 1.0, drop1s: 1, drop2s: 1, drop5s: 1)
    }

    // method to update tileQuads based on the new connections table
    func zapRemoveConnectionsCreateNewAndMakeThemFall() {
        // play exploding sound for effect
        SoundManager.shared.playSoundEffect(filename: "explode")
        // first remove from the tile matrix and generate new tiles
        // in the game board representation
        // VERY IMPORTANT - this function needs to mirror EXACTLY
        // the algorightm below - shift tiles from above, overwrite the current one
        // when they are part of a connection
        // then generate new ones in the spots left open at the top
        gameBoard?.removeAndShiftConnectingTiles()
        // now do our business - remove old and create new tile quads
        // and set up animations for them to fall into place
        // everything is done PER COLUMN
        for x in 1..<boardWidth + 1 {
            // new tiles will be added above the first tile
            // so they can fall down
            // new tile position will be shifted as we add more tiles later
            var newTilePosition = getIdealTilePositionY(j: 0) - Float(tileSize)
            var shiftedItems = 0 // remember how many tiles we shift as we go
            // because we will have to compensate the copying position by this number
            for y in (0..<boardHeight).reversed() {
                if gameBoard?.connectMarkings[x - 1][y] == .ok {
                    // make an explosion out of it
                    // at exactly x-1, y tile position
                    animationManager?.addParticleAnimation(speedLimit: 10.0, width: 4.0, count: 10, duration: 2.0, tilePosition: (x: x - 1, y: y), targetScreen: renderer!.gameScreen)
                    // but make sure to remake the marking
                    gameBoard?.connectMarkings[x - 1][y] = .ok
                    // Shift tileQuads above downward
                    // - only in the tileQuads matrix
                    // - their position on screen remains the same
                    if y >= 1 {
                        for shiftY in (1...y).reversed() {
                            // remember to compensate copying position by shiftedItems
                            tileQuads[shiftY + shiftedItems][x] = tileQuads[shiftY + shiftedItems - 1][x]
                        }
                    }
                    // one more disappeared so far
                    shiftedItems += 1
                }
            }
            for y in (0..<shiftedItems).reversed() {
                // do NOT update their positions, let them stand where they are
                // will add an animation later to bring them down
                // for now just create one more tileQuad at the top
                tileQuads[y][x] = createNewTileQuad(i: x, j: y)
                if let quad = tileQuads[y][x] {
                    quad.position.y = newTilePosition
                    newTilePosition -= Float(tileSize) // generate the next one even higher above
                }
            }
        }
        // make animations
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
    
    // function to create score animation and update the LEFT score
    func updateScoreLeft(byPoints: Int, atTile: (Int, Int)) {
        guard let renderer = renderer else { return }
        // increase left score
        leftScore += byPoints
        var scoreText = "+\(byPoints)"
        if byPoints < 0 {
            scoreText = "\(byPoints)"
        }
        // add the animation
        animationManager?.createTextAnimation(text: scoreText, font: Font.systemFont(ofSize: 24), color: .purple, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: atTile.0), getIdealTilePositionY(j: atTile.1)), textLayer: renderer.textLayer)
        // remake the meshes
        updateScoreMeshes()
    }
    
    // function to create score animation and update the RIGHT score
    func updateScoreRight(byPoints: Int, atTile: (Int, Int)) {
        guard let renderer = renderer else { return }
        // increase left score
        rightScore += byPoints
        var scoreText = "+\(byPoints)"
        if byPoints < 0 {
            scoreText = "\(byPoints)"
        }
        // add the animation
        animationManager?.createTextAnimation(text: scoreText, font: Font.systemFont(ofSize: 24), color: .orange, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: atTile.0), getIdealTilePositionY(j: atTile.1)), textLayer: renderer.textLayer)
        // remake the meshes
        updateScoreMeshes()
    }
    
    // function to generate bonuses of various denominations
    func dropCoins(many1: Int, many2: Int, many5: Int) {
        // remake the connection markings
        _ = gameBoard?.checkConnections()
        
        if many1 > 0 {
            for _ in 0..<many1 {
                animationManager?.createFallingObject(objectType: Bonus1.self)
            }
        }
        if many2 > 0 {
            for _ in 0..<many2 {
                animationManager?.createFallingObject(objectType: Bonus2.self)
            }
        }
        if many5 > 0 {
            for _ in 0..<many5 {
                animationManager?.createFallingObject(objectType: Bonus5.self)
            }
        }
        // randomly add a bomb
        if 0 == Int.random(in: 0..<1) {
            animationManager?.createFallingObject(objectType: Bomb.self)
        }

        // play that coin sound
        SoundManager.shared.playSoundEffect(filename: "coindrop")
    }
    
    // Converts screen coordinates to tile coordinates and returns the tile position
    func getTilePosition(from input: CGPoint) -> (x: Int, y: Int)? {
        guard let renderer = renderer else { return nil }
        
        let screenW = Float(renderer.view.drawableSize.width)
        let screenH = Float(renderer.view.drawableSize.height)
        let horizRatio = screenW / needW
        let vertRatio = screenH / needH
        
        var gameX: Float
        var gameY: Float
        if horizRatio < vertRatio {
            gameX = (Float(input.x) - (screenW / 2.0)) / horizRatio
            gameY = (Float(input.y) - (screenH / 2.0)) / horizRatio
        } else {
            gameX = (Float(input.x) - (screenW / 2.0)) / vertRatio
            gameY = (Float(input.y) - (screenH / 2.0)) / vertRatio
        }
        
        // Convert to tile coordinates
        let quadX = Int(round((gameX + boardW / 2.0) / tileSize) - 1)
        let quadY = Int(round((gameY + boardH / 2.0) / tileSize) - 1)
        
        // Ensure the tile is within bounds
        if quadX >= 1 && quadX < boardWidth + 1 && quadY >= 0 && quadY < boardHeight {
            return (x: quadX - 1, y: quadY)
        } else {
            return nil
        }
    }

    // function that handles frame by frame updates
    func update() {
        guard let gameBoard = gameBoard, let renderer = renderer else { return }
        // ...
        // check for input
        var tapped = false
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
            tapped = true
        }
        // move those animations
        animationManager?.updateAnimations()
        // check connections
        if gameBoard.checkConnections() != 0 {
            // wait, who gets the points?
            print ("left pins connected: ", gameBoard.leftPinsConnect)
            print ("right pins connected: ", gameBoard.rightPinsConnect)
            
            var many1s = 2
            var many2s = 0
            var many5s = 0
            
            // let it rain bonus money
            if gameBoard.leftPinsConnect <= 3 {
            } else if gameBoard.leftPinsConnect <= 6 {
                many1s += 1
                many2s += gameBoard.leftPinsConnect - 3
            } else {
                many1s += 1
                many2s += 3
                many5s += gameBoard.leftPinsConnect - 6
            }

            // let it rain bonus money AGAIN
            if gameBoard.rightPinsConnect <= 3 {
            } else if gameBoard.rightPinsConnect <= 6 {
                many1s += 1
                many2s += gameBoard.rightPinsConnect - 3
            } else {
                many1s += 1
                many2s += 3
                many5s += gameBoard.rightPinsConnect - 6
            }
            
            // remove existing bonuses
            renderer.objectsLayer.meshes.removeAll()

            // increment scores
            leftScore += gameBoard.leftPinsConnect
            rightScore += gameBoard.rightPinsConnect
            // set up attractor down below for particles
            Particle.attractor = SIMD2<Float> (0.0, 2.0 * tileSize * Float(boardHeight))
            // stop everything mid air for the player to see the bolt
            animationManager?.addFreezeFrameAnimation(duration: 2.0, drop1s: many1s, drop2s: many2s, drop5s: many5s)
            // remake the meshes
            updateScoreMeshes()
            
            // add score animations for each pin on the left
            // and on the right
            for y in 0..<gameBoard.height {
                if .ok == gameBoard.connectMarkings[0][y] {
                    if let tile = gameBoard.connections[0][y] {
                        if tile.hasConnection(direction: .left) {
                            animationManager?.createTextAnimation(text: "+1", font: Font.systemFont(ofSize: 24), color: .purple, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: -1), getIdealTilePositionY(j: y)), textLayer: renderer.textLayer)
                        }
                    }
                }
                if .ok == gameBoard.connectMarkings[gameBoard.width - 1][y] {
                    if let tile = gameBoard.connections[gameBoard.width - 1][y] {
                        if tile.hasConnection(direction: .right) {
                            animationManager?.createTextAnimation(text: "+1", font: Font.systemFont(ofSize: 24), color: .orange, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: gameBoard.width + 2), getIdealTilePositionY(j: y)), textLayer: renderer.textLayer)
                        }
                    }
                }
            }

            // remove the connecting tiles, make new ones, and make them fall from above
            zapRemoveConnectionsCreateNewAndMakeThemFall()
        } else if tapped {
            // wait there was no connection left to right, but we still need to check for bonuses after tap
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
