//
//  GameBoardAnimations.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

import Foundation

class AnimationManager {
    var animations: [Animation] = []
    weak var gameManager: GameManager? // Use weak reference to avoid retain cycles
    
    init(gameManager: GameManager) {
        self.gameManager = gameManager
    }
    
    func addAnimation(_ animation: Animation) {
        guard let gameManager = gameManager else { return }
        animations.append(animation)
        let tilePosition = animation.tilePosition

        // Call checkConnections and recreate connections
        gameManager.gameBoard?.checkConnections()
        // except this one that is going to be rotating
        gameManager.gameBoard?.connectMarkings[tilePosition.x][tilePosition.y] = .animating

        // Remove all ElectricArcMesh instances from effectsLayer
        gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }

        // remake all electric arcs according to their markers
        gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
    }
    
    func updateAnimations() {
        for animation in animations {
            animation.update()
        }
        
        guard let gameManager = gameManager else { return }
        // Remove finished animations and update connectMarkings
        animations.removeAll { animation in
            if animation.isFinished {
                let tilePosition = animation.tilePosition
                gameManager.gameBoard?.connectMarkings[tilePosition.x][tilePosition.y] = .none
                // Call checkConnections and recreate connections
                gameManager.gameBoard?.checkConnections()

                // Remove all ElectricArcMesh instances from effectsLayer
                gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }

                // remake all electric arcs according to their markers
                gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
                gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
                gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
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
    private let quad: QuadMesh
    private let duration: TimeInterval
    private var elapsedTime: TimeInterval = 0
    private let startRotation: Float
    private let endRotation: Float
    let tilePosition: (x: Int, y: Int)
    
    private var tempQuad: QuadMesh?
    private weak var objectsLayer: GraphicsLayer?
    private weak var effectsLayer: EffectsLayer?

    var isFinished: Bool {
        return elapsedTime >= duration
    }
    
    init(quad: QuadMesh, duration: TimeInterval, tilePosition: (x: Int, y: Int), objectsLayer: GraphicsLayer, effectsLayer: EffectsLayer) {
        self.quad = quad
        self.duration = duration
        self.tilePosition = tilePosition
        self.endRotation = quad.rotation
        self.startRotation = quad.rotation + .pi / 2
        self.objectsLayer = objectsLayer
        self.effectsLayer = effectsLayer
        // we start from -90 degrees because the tile actually got rotated 90 degrees
        // which is to say its texture now shows it rotated
        // so we start rotating from -90 as if it was the old tile
        // and rotate into its correct position
        
        // Create a temporary object and add it to the objectsLayer
        let tempQuad = QuadMesh(device: quad.mtlDevice, size: 100.0, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(0.25, 0.25))
        tempQuad.position = quad.position
        tempQuad.rotation = quad.rotation
        effectsLayer.meshes.append(tempQuad)
        self.tempQuad = tempQuad
    }
    
    func update() {
        guard !isFinished else { return }
        
        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
        let progress = min(elapsedTime / duration, 1.0)
        
        // Interpolate rotation
        let newRotation = startRotation + (endRotation - startRotation) * Float(progress)
        quad.rotation = newRotation
        tempQuad?.rotation = newRotation

        // Update the connections at the end of the animation
        if progress >= 1.0 {
            quad.rotation = endRotation
            tempQuad?.rotation = endRotation
            
            // Remove the temporary object from the objectsLayer
            if let tempQuad = tempQuad {
                effectsLayer?.meshes.removeAll { $0 === tempQuad }
            }
        }
    }
}
