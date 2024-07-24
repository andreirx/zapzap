//
//  GameBoardAnimations.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

import Foundation

class AnimationManager {
    var animations: [Animation] = []
    var gameBoard: GameBoard
    
    init(gameBoard: GameBoard) {
        self.gameBoard = gameBoard
    }
    
    func addAnimation(_ animation: Animation) {
        animations.append(animation)
        let tilePosition = animation.tilePosition
        gameBoard.connectMarkings[tilePosition.x][tilePosition.y] = .animating
    }
    
    func updateAnimations() {
        for animation in animations {
            animation.update()
        }
        
        // Remove finished animations and update connectMarkings
        animations.removeAll { animation in
            if animation.isFinished {
                let tilePosition = animation.tilePosition
                gameBoard.connectMarkings[tilePosition.x][tilePosition.y] = .none
            }
            return animation.isFinished
        }
    }
}

protocol Animation {
    var isFinished: Bool { get }
    var tilePosition: (x: Int, y: Int) { get }
    func update()
}

class RotateAnimation: Animation {
    private let tile: Tile
    private let duration: TimeInterval
    private var elapsedTime: TimeInterval = 0
    private let startConnections: UInt8
    private let endConnections: UInt8
    let tilePosition: (x: Int, y: Int)
    
    var isFinished: Bool {
        return elapsedTime >= duration
    }
    
    init(tile: Tile, duration: TimeInterval, tilePosition: (x: Int, y: Int)) {
        self.tile = tile
        self.duration = duration
        self.tilePosition = tilePosition
        self.startConnections = tile.connections
        self.endConnections = startConnections.rotate()
    }
    
    func update() {
        guard !isFinished else { return }
        
        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
        let progress = min(elapsedTime / duration, 1.0)
        
        // Interpolate connections (simple example)
        if progress == 1.0 {
            tile.connections = endConnections
        }
    }
}

extension UInt8 {
    func rotate() -> UInt8 {
        var rVal = self << 1
        rVal = (rVal & 0x0F) | (rVal >> 4)
        return rVal & 0x0F
    }
}
