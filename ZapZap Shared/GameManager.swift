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
    var animationManager: AnimationManager?
    var lastInput: CGPoint
    
    init() {
        gameBoard = GameBoard(width: 10, height: 10)
        animationManager = AnimationManager(gameBoard: gameBoard!)
        self.lastInput = CGPointZero
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
