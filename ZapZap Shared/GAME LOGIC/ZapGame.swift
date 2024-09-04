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
    weak var animationManager: AnimationManager?
    weak var renderer: Renderer?
    public var zapGameState: ZapGameState = .waitingForInput
    
    init(gameManager: GameManager, animationManager: AnimationManager, renderer: Renderer) {
        self.gameManager = gameManager
        self.animationManager = animationManager
        self.renderer = renderer
        renderer.createBaseLayer(fromGameManager: gameManager)
    }

    // Initialize a local or multiplayer game
    func startNewGame(isMultiplayer: Bool) {
        guard let renderer = gameManager.renderer else { return }
        renderer.setCurrentScreen(renderer.gameScreen)
        gameManager.gameBoard?.resetTable(percentMissingLinks: defaultMissingLinks)
        zapGameState = .waitingForInput
    }

    // Process a single input event (e.g., tap on a tile)
    func processInput(at position: CGPoint) {
        guard zapGameState == .waitingForInput else { return }
        guard let tilePosition = gameManager.getTilePosition(from: position) else { return }
        gameManager.tapTile(i: tilePosition.x, j: tilePosition.y)
    }

    // update the score after ZAP + compute the bonuses
    private func updateScoreComputeBonuses() {
        zapGameState = .freezeDuringZap
    }

    // Clear electric arcs
    private func clearArcs() {
        guard let renderer = gameManager.renderer else { return }
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
        guard let renderer = gameManager.renderer else { return }
        // Check if bonuses are present, apply them, and remove them
        renderer.objectsLayer.meshes.removeAll()
    }

    // Freeze the frame for a dramatic effect
    private func freezeFrame() {
    }

    // Handle falling tiles
    private func fallTiles() {
        zapGameState = .fallingTiles
    }

    // Add bonuses after tiles have fallen
    private func addBonuses() {
        zapGameState = .fallingBonuses
    }
}
