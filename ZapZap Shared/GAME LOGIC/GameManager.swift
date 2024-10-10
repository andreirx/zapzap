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
let boardHeight = 10
let defaultMissingLinks = 3
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

enum ZapGameState: Int {
    case waitingForInput = 0
    case rotatingTile
    case fallingTiles
    case fallingBonuses
    case freezeDuringZap
    case freezeDuringBomb
    case waitingForOrange
    case waitingForIndigo
    case superheroBeforeDrop
    case superheroAfterDrop
}


class GameManager {
    // might or might not have
    var gameBoard: GameBoard?
    weak var renderer: Renderer?
    var animationManager: AnimationManager?
    var tileQuads: [[QuadMesh?]]
    var lastInput: CGPoint?
    
    var superheroLeft: QuadMesh?
    var superheroRight: QuadMesh?

    var leftScore: Int = 0
    var scoreLeftMesh: TextQuadMesh? = nil
    var rightScore: Int = 0
    var scoreRightMesh: TextQuadMesh? = nil

    // very important things
    var multiplayer: Bool = false
    var bot: BotPlayer? = nil
    var isBotThinking: Bool = false
    var botMoveReady: Bool = false
    var botMove: ((x: Int, y: Int), rotationCount: Int)? = nil

    // powers
    var powerLBomb: Bool = false
    var powerLCross: Bool = false
    var powerLArrow: Bool = false
    var powerRBomb: Bool = false
    var powerRCross: Bool = false
    var powerRArrow: Bool = false

    // armed
    var armLBomb: Bool = false
    var armLCross: Bool = false
    var armLArrow: Bool = false
    var armRBomb: Bool = false
    var armRCross: Bool = false
    var armRArrow: Bool = false

    public var zapGameState: ZapGameState = .waitingForInput

    // these are the correct texture positions (to be divided by 16.0) based on the connection code
    let grid_codep: [Float] = [
        0.0, 12.0, 15.0, 5.0, 14.0, 1.0, 4.0, 7.0, 13.0, 6.0, 2.0, 8.0, 3.0, 9.0, 10.0, 11.0
    ]

    init() {
        gameBoard = GameBoard(width: boardWidth, height: boardHeight, missingLinks: defaultMissingLinks)
        self.lastInput = nil
        self.multiplayer = false

        // Initialize tileQuads array with nil values
        self.tileQuads = Array(repeating: Array(repeating: nil, count: boardWidth + 2), count: boardHeight)

        // create the animationManager
        animationManager = AnimationManager(gameManager: self)

        // Create and configure the tiles
        createTiles()
    }
    
    // add a bot if you want to plauy with it
    func addBot() {
        if self.gameBoard != nil {
            bot = BotPlayer(gameBoard: self.gameBoard!)
        }
        updateScoreMeshes()
    }

    // make the bot move
    func triggerBotMove() {
        if bot == nil {
            // no bot, no move
            return
        }
        isBotThinking = true
        botMoveReady = false
        DispatchQueue.global(qos: .background).async { [weak self] in
            // Call bot's determineNextMove in the background
            if let move = self?.bot?.determineNextMove() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Save the move and mark it as ready
                    self?.botMove = move
                    self?.botMoveReady = true
                }
            }
        }
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
            // first row is left pins
            textureX = 12.0 / 16.0
            textureY = 3.0 * textureUnitY
        } else if i == boardWidth + 1 {
            // last row is right pins
            textureX = 14.0 / 16.0
            textureY = 3.0 * textureUnitY
        } else {
            // remaining rows in between are the game table connections
            let gridIndex = Int(gameBoard.connections.connections[i - 1][j]!.connections)
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

    // function to create ONE tile quad based on a position but NO gameBoard connections
    func createUnrelatedTileQuad(i: Int, j: Int) -> QuadMesh? {
        let textureUnitX: Float = 1.0 / 16.0
        let textureUnitY: Float = 1.0 / 8.0

        let textureX: Float
        let textureY: Float
        let gridIndex = Int.random(in: 1...15)
        textureX = getTextureX(gridConnections: gridIndex)
        textureY = 3.0 * textureUnitY

        let topLeftUV = SIMD2<Float>(textureX, textureY)
        let bottomRightUV = SIMD2<Float>(textureX + textureUnitX, textureY + textureUnitY)

        let quad = QuadMesh(size: tileSize, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
        // appropriate positions for the tile
        quad.position = SIMD2<Float>(Float(i) * tileSize - Float(boardWidth + 2) / 2.0 * tileSize,
                                     Float(j) * tileSize - Float(boardHeight) / 2.0 * tileSize)
        quad.rotation = .pi / 4.0
        quad.scale = 1.42
        quad.alpha = 0.5
        
        return quad
    }

    // function to remake the score meshes
    func updateScoreMeshes() {
        let font = Font.systemFont(ofSize: 32)
        let textSize = CGSize(width: 256, height: 128)
        // remove previous meshes
        if (renderer != nil) {
            if renderer!.textLayer != nil {
                renderer!.textLayer.meshes.removeAll { $0 === scoreLeftMesh }
                renderer!.textLayer.meshes.removeAll { $0 === scoreRightMesh }
            }
        }
        if multiplayer || bot != nil {
            // for MULTIPLAYER or BOT, show scores separately
            var leftText = "YOU"
            var rightText = "BOT"
            // for MULTIPLAYER, show the actual names
            if multiplayer {
                leftText = renderer!.multiMgr.match!.players[0].displayName
                rightText = renderer!.multiMgr.match!.players[1].displayName
            }
            // create text meshes for keeping score
            var text = "\(leftText)\n\(leftScore)\npoints"
            scoreLeftMesh = TextQuadMesh(text: text, font: font, color: Color.magenta, size: textSize)
            scoreLeftMesh?.position = SIMD2<Float>(-needW / 2.0 + tileSize * 1.5, -tileSize)
            text = "\(rightText)\n\(rightScore)\npoints"
            scoreRightMesh = TextQuadMesh(text: text, font: font, color: Color.orange, size: textSize)
            scoreRightMesh?.position = SIMD2<Float>(needW / 2.0 - tileSize * 1.5, -tileSize)
            
            if (renderer != nil) {
                if renderer!.textLayer != nil {
                    renderer!.textLayer.meshes.append(scoreLeftMesh!)
                    renderer!.textLayer.meshes.append(scoreRightMesh!)
                }
            }
        } else {
            // for SINGLE PLAYER, sum them up and display together
            var text = "SCORE\n\(leftScore + rightScore)\npoints"
            scoreLeftMesh = TextQuadMesh(text: text, font: font, color: Color.yellow, size: textSize)
            scoreLeftMesh?.position = SIMD2<Float>(-needW / 2.0 + tileSize * 1.5, -tileSize)

            if (renderer != nil) {
                if renderer!.textLayer != nil {
                    renderer!.textLayer.meshes.append(scoreLeftMesh!)
                }
            }
        }
    }
    
    // Clear electric arcs
    func clearElectricArcs() {
        guard let renderer = self.renderer else { return }
        renderer.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
    }

    // Add electric arcs
    func addElectricArcs() {
        remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
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
    
    // Initialize a local or multiplayer game
    func startNewGame(isMultiplayer: Bool) {
        // remove effects
        clearElectricArcs()
        // remove animations
        animationManager!.removeAllGameplayAnimations()
        // remove all objects
        renderer!.objectsLayer.meshes.removeAll()
        renderer!.effectsLayer.meshes.removeAll()
        // create new tiles
        gameBoard?.resetTable(percentMissingLinks: defaultMissingLinks)
        // reset the score
        leftScore = 0
        rightScore = 0
        // reset the bot
        isBotThinking = false
        botMoveReady = false
        botMove = nil
        // create new meshes corresponding to the underlying tiles
        createTiles()
        // add the multiplier lights
        for j in 0..<boardHeight {
            // left
            for i in 0..<(gameBoard?.multiplierLeft[j])! {
                // multiplier should be 1, but let's go with this
                let dx = tileSize / 10.0 + Float(i / 4) * tileSize / 5.0
                let dy = 2.0 * tileSize / 10.0 + Float(i % 4) * tileSize / 5.0
                let newLight = QuadMesh(size: tileSize / 4.0, topLeftUV: SIMD2(x: 1.0/32.0, y: 30.0/32.0), bottomRightUV: SIMD2(x: 2.0/32.0, y: 31.0/32.0))
                newLight.position.x = getIdealTilePositionX(i: 0) - tileSize / 2.0 - dx
                newLight.position.y = getIdealTilePositionY(j: j) - tileSize / 2.0 + dy
                renderer!.effectsLayer.meshes.append(newLight)
            }
            // right
            for i in 0..<(gameBoard?.multiplierRight[j])! {
                // multiplier should be 1, but let's go with this
                let dx = tileSize / 10.0 + Float(i / 4) * tileSize / 5.0
                let dy = 2.0 * tileSize / 10.0 + Float(i % 4) * tileSize / 5.0
                let newLight = QuadMesh(size: tileSize / 4.0, topLeftUV: SIMD2(x: 1.0/32.0, y: 28.0/32.0), bottomRightUV: SIMD2(x: 2.0/32.0, y: 29.0/32.0))
                newLight.position.x = getIdealTilePositionX(i: boardWidth + 1) + tileSize / 2.0 + dx
                newLight.position.y = getIdealTilePositionY(j: j) - tileSize / 2.0 + dy
                renderer!.effectsLayer.meshes.append(newLight)
            }
        }
        // superheroes
        superheroLeft = QuadMesh(size: boardW / 2.0, topLeftUV: SIMD2(x: 0.01, y: 0.01), bottomRightUV: SIMD2(x: 0.99, y: 0.99/4.0))
        superheroLeft?.position.x = -boardW / 4.0
        superheroLeft?.alpha = 0.0
        renderer?.superheroLayer.meshes.append(superheroLeft!)
        renderer?.superheroExtraLayer.meshes.append(superheroLeft!)
        //
        superheroRight = QuadMesh(size: boardW / 2.0, topLeftUV: SIMD2(x: 0.01, y: 1.01/4.0), bottomRightUV: SIMD2(x: 0.99, y: 1.99/4.0))
        superheroRight?.position.x = boardW / 4.0
        superheroRight?.alpha = 0.0
        renderer?.superheroLayer.meshes.append(superheroRight!)
        renderer?.superheroExtraLayer.meshes.append(superheroRight!)
        //
        multiplayer = isMultiplayer
        //
        // disarm superpowers
        powerLBomb = false
        armLBomb = false
        powerRBomb = false
        armRBomb = false
        powerLArrow = false
        armLArrow = false
        powerRArrow = false
        armRArrow = false
        powerLCross = false
        armLCross = false
        powerRCross = false
        armRCross = false
        // wait for user input
        updateScoreMeshes()
        zapGameState = .waitingForInput
    }

    // method to apply the "bombing" on the table
    func bombTable(ati: Int, atj: Int, deltaX: Int = 2, deltaY: Int = 2) {
        // make sure we're not bombing outside
        if ati < 0 || ati >= boardWidth || atj < 0 || atj >= boardHeight {
            return
        }
        // remove the arcs
        renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
        // also "bomb" the gameTable
        gameBoard?.bombTable(ati: ati, atj: atj, deltaX: deltaX, deltaY: deltaY)
        // play exploding sound for effect
        SoundManager.shared.playSoundEffect(filename: "bomb")
        // will remove the tiles around ati, atj
        // will "fall down" the ones above
        // will generate new ones from above
        var starti = ati - deltaX
        var endi = ati + deltaX + 1
        var startj = atj - deltaY
        var endj = atj + deltaY + 1
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
        zapGameState = .freezeDuringBomb
        animationManager?.addFreezeFrameAnimation(duration: 1.0, drop1s: 1, drop2s: 1, drop5s: 1)
        clearElectricArcs()
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
        
        gameBoard?.connections.connections[i][j]?.rotate()
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
        
        // put the game in falling objects state
        zapGameState = .fallingBonuses
        
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
        // randomly add a bomb or other objects
        if 0 == Int.random(in: 0..<1) {
            animationManager?.createFallingObject(objectType: Bomb.self)
        }
        if 0 == Int.random(in: 0..<1) {
            animationManager?.createFallingObject(objectType: Cross.self)
        }
        if 0 == Int.random(in: 0..<1) {
            animationManager?.createFallingObject(objectType: Arrow.self)
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
    
    // function that updates the score, generates bonuses,
    // sets animations in motion
    // everything that needs to be done when connecting from left to right
    func checkConnectionsAndStartZap() {
        guard let gameBoard = gameBoard, let renderer = renderer else { return }
        // only when waiting for input
        if zapGameState != .waitingForInput {
            return
        }
        if gameBoard.checkConnections() != 0 {
            // wait, who gets the points?
            print ("left pins connected: ", gameBoard.leftPinsConnect)
            print ("right pins connected: ", gameBoard.rightPinsConnect)
            
            // TODO - put the bonus generating logic into a separate function
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

            // set up attractor down below for particles
            Particle.attractor = SIMD2<Float> (0.0, 2.0 * tileSize * Float(boardHeight))
            // stop everything mid air for the player to see the bolt
            zapGameState = .freezeDuringZap
            animationManager?.addFreezeFrameAnimation(duration: 2.0, drop1s: many1s, drop2s: many2s, drop5s: many5s)
            // add score animations for each pin on the left
            // and on the right
            for y in 0..<gameBoard.height {
                if .ok == gameBoard.connectMarkings[0][y] {
                    if let tile = gameBoard.connections.connections[0][y] {
                        if tile.hasConnection(direction: .left) {
                            let plusScore = gameBoard.multiplierLeft[y]
                            leftScore += plusScore
                            // add another charge
                            gameBoard.multiplierLeft[y] += 1
                            // left
                            let j = y
                            let i = gameBoard.multiplierLeft[y] - 1
                            // multiplier should be 1, but let's go with this
                            let dx = tileSize / 10.0 + Float(i / 4) * tileSize / 5.0
                            let dy = 2.0 * tileSize / 10.0 + Float(i % 4) * tileSize / 5.0
                            let newLight = QuadMesh(size: tileSize / 4.0, topLeftUV: SIMD2(x: 1.0/32.0, y: 30.0/32.0), bottomRightUV: SIMD2(x: 2.0/32.0, y: 31.0/32.0))
                            newLight.position.x = getIdealTilePositionX(i: 0) - tileSize / 2.0 - dx
                            newLight.position.y = getIdealTilePositionY(j: j) - tileSize / 2.0 + dy
                            renderer.effectsLayer.meshes.append(newLight)
                            // add animation
                            animationManager?.createTextAnimation(text: "+\(plusScore)", font: Font.systemFont(ofSize: 24), color: .purple, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: -1), getIdealTilePositionY(j: y)), textLayer: renderer.textLayer)
                        }
                    }
                }
                if .ok == gameBoard.connectMarkings[gameBoard.width - 1][y] {
                    if let tile = gameBoard.connections.connections[gameBoard.width - 1][y] {
                        if tile.hasConnection(direction: .right) {
                            let plusScore = gameBoard.multiplierRight[y]
                            rightScore += plusScore
                            // add another charge
                            gameBoard.multiplierRight[y] += 1
                            // right
                            let j = y
                            let i = gameBoard.multiplierRight[y] - 1
                            // multiplier should be 1, but let's go with this
                            let dx = tileSize / 10.0 + Float(i / 4) * tileSize / 5.0
                            let dy = 2.0 * tileSize / 10.0 + Float(i % 4) * tileSize / 5.0
                            let newLight = QuadMesh(size: tileSize / 4.0, topLeftUV: SIMD2(x: 1.0/32.0, y: 28.0/32.0), bottomRightUV: SIMD2(x: 2.0/32.0, y: 29.0/32.0))
                            newLight.position.x = getIdealTilePositionX(i: boardWidth + 1) + tileSize / 2.0 + dx
                            newLight.position.y = getIdealTilePositionY(j: j) - tileSize / 2.0 + dy
                            renderer.effectsLayer.meshes.append(newLight)
                            // add animation
                            animationManager?.createTextAnimation(text: "+\(plusScore)", font: Font.systemFont(ofSize: 24), color: .orange, size: CGSize(width: 64, height: 32), startPosition: SIMD2<Float>(getIdealTilePositionX(i: gameBoard.width + 2), getIdealTilePositionY(j: y)), textLayer: renderer.textLayer)
                        }
                    }
                }
            }

            // remake the meshes
            updateScoreMeshes()

            // remove the connecting tiles, make new ones, and make them fall from above
            zapRemoveConnectionsCreateNewAndMakeThemFall()
        }
    }
    
    // function that handles frame by frame updates
    func update() {
        guard let gameBoard = gameBoard, let renderer = renderer else { return }
        // ...
        // check for input
        var tapped = false
        if self.lastInput != nil && zapGameState == .waitingForInput {
            // input to process
            // but only if we're waiting for input
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
            if quadX >= 0 && quadX < boardWidth + 2 && quadY >= 0 && quadY < boardHeight {
                if quadX >= 1 && quadX < boardWidth + 1 {
                    print ("hit the board at ", quadX - 1, quadY)
                    // OK: if no powerups are armed, just tap
                    if armLBomb || armRBomb {
                        // bomb the table
                        bombTable(ati: quadX - 1, atj: quadY)
                        // remove bonuses because bomb
                        renderer.objectsLayer.meshes.removeAll()
                        // lose the power
                        if armLBomb {
                            armLBomb = false
                            powerLBomb = false
                        }
                        if armRBomb {
                            armRBomb = false
                            powerRBomb = false
                        }
                    } else if armLCross || armRCross {
                        // change the connection to a cross
                        gameBoard.setTile(at: quadX - 1, y: quadY, connection: 0x0f)
                        // TODO: recreate the tile
                        tileQuads[quadY][quadX] = createNewTileQuad(i: quadX, j: quadY)
                        // remake the arcs
                        clearElectricArcs()
                        // check connections and ZAP if needed
                        checkConnectionsAndStartZap()
                        addElectricArcs()
                        // play powerup sound
                        SoundManager.shared.playSoundEffect(filename: "powerup")
                        // lose the power
                        if armLCross {
                            armLCross = false
                            powerLCross = false
                        }
                        if armRCross {
                            armRCross = false
                            powerRCross = false
                        }
                    } else if armLArrow || armRArrow {
                        // TODO: clear the column
                        bombTable(ati: quadX - 1, atj: quadY, deltaX: 0, deltaY: boardHeight)
                        // remove bonuses because bomb
                        renderer.objectsLayer.meshes.removeAll()
                        // lose the power
                        if armLArrow {
                            armLArrow = false
                            powerLArrow = false
                        }
                        if armRArrow {
                            armRArrow = false
                            powerRArrow = false
                        }
                    } else {
                        tapTile(i: quadX - 1, j: quadY)
                    }
                }
            }
            self.lastInput = nil
            tapped = true
        } else if self.lastInput != nil {
            // if the player tapped but we weren't waiting for input, discard
            self.lastInput = nil
        }
        if zapGameState == .waitingForInput {
            //
            // Check if it's the bot's turn to move
            if let bot = bot {
                if !isBotThinking && !botMoveReady {
                    // Trigger the bot's move in the background if it's not thinking
                    triggerBotMove()
                } else if botMoveReady {
                    // If the bot move is ready, apply the move to the board
                    if let move = botMove {
                        let (x, y) = move.0
                        let rotationCount = move.1
                        
                        // Apply the move to the game board
                        for _ in 0..<rotationCount {
                            tapTile(i: x, j: y)
                        }
                        
                        // Reset the flags and prepare for the next move
                        isBotThinking = false
                        botMoveReady = false
                        botMove = nil
                    }
                }
            }
        }
        // move those animations
        animationManager?.updateAnimations()
        // check connections and ZAP if needed
        checkConnectionsAndStartZap()

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
                if let tile = gameBoard.connections.connections[0][y] {
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
                if let tile = gameBoard.connections.connections[gameBoard.width - 1][y] {
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
                if let tile = gameBoard.connections.connections[x][y] {
                    if forMarker == gameBoard.connectMarkings[x][y] {
                        // For each connection direction, create an arc if connected
                        // right-to-left
                        if tile.hasConnection(direction: .right), x < gameBoard.width - 1 {
                            if let rightTile = gameBoard.connections.connections[x + 1][y], rightTile.hasConnection(direction: .left) {
                                let start = tileQuads[y][x + 1]!.position
                                let end = tileQuads[y][x + 2]!.position
                                let arc = ElectricArcMesh(startPoint: start, endPoint: end, powerOfTwo: po2, width: andWidth, color: withColor)
                                renderer.effectsLayer.meshes.append(arc)
                            }
                        }
                        // top-to-bottom
                        if tile.hasConnection(direction: .down), y < gameBoard.height - 1 {
                            if let downTile = gameBoard.connections.connections[x][y + 1], downTile.hasConnection(direction: .up) {
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
