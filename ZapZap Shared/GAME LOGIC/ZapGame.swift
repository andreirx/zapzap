//
//  ZapGame.swift
//  ZapZap
//
//  Created by apple on 26.08.2024.
//

import Foundation

// high level organization of a ZAP GAME - gather the logic here
class ZapGame {
    private var gameManager: GameManager
    private var animationManager: AnimationManager
    private var renderer: Renderer
    
    init(gameManager: GameManager, animationManager: AnimationManager, renderer: Renderer) {
        self.gameManager = gameManager
        self.animationManager = animationManager
        self.renderer = renderer
    }

    // Initialize a local or multiplayer game
    func startNewGame(isMultiplayer: Bool) {
        // Initialize the game board, players, etc.
//        gameManager.initializeGameBoard(isMultiplayer: isMultiplayer)
        renderer.createBaseLayer(fromGameManager: gameManager)
        renderer.setCurrentScreen(renderer.gameScreen)
    }

    // Process a single input event (e.g., tap on a tile)
    func processInput(at position: CGPoint) {
        guard let tilePosition = gameManager.getTilePosition(from: position) else { return }
        performGameAction(onTileAt: tilePosition)
    }

    // Perform a sequence of game actions for a specific tile
    private func performGameAction(onTileAt tilePosition: (x: Int, y: Int)) {
        clearArcs()
        rotateTile(at: tilePosition)
        addArcs()
        while checkZap() {
            updateScoreComputeBonuses()
            clearPreviousBonuses()
            freezeFrame()
            clearArcs()
            fallTiles()
            addArcs()
            addBonuses()
        }
    }
    
    // update the score after ZAP + compute the bonuses
    private func updateScoreComputeBonuses() {
        
    }

    // Clear electric arcs
    private func clearArcs() {
        renderer.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
    }

    // Rotate a specific tile
    private func rotateTile(at position: (x: Int, y: Int)) {
        gameManager.tapTile(i: position.x, j: position.y)
        // Additional logic to add rotate animations if needed
    }

    // Add electric arcs
    private func addArcs() {
        gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
    }

    // Check if a "Zap" condition is met, return true if yes
    private func checkZap() -> Bool {
        return gameManager.gameBoard?.checkConnections() == 1
    }

    // Clear bonuses on the board
    private func clearPreviousBonuses() {
        // Check if bonuses are present, apply them, and remove them
        renderer.objectsLayer.meshes.removeAll()
    }

    // Freeze the frame for a dramatic effect
    private func freezeFrame() {
    }

    // Handle falling tiles
    private func fallTiles() {
    }

    // Add bonuses after tiles have fallen
    private func addBonuses() {
    }
}
