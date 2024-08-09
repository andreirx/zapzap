//
//  GameBoardAnimations.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

import Foundation

// // // // // // // // // // // // // // // // // // // // //
//
// AnimationManager - class to manage animations around
//

class AnimationManager {

    var rotateAnimations: [RotateAnimation] = []
    var fallAnimations: [FallAnimation] = []
    var particleAnimations: [ParticleAnimation] = []
    var freezeFrameAnimations: [FreezeFrameAnimation] = []

    weak var gameManager: GameManager? // Use weak reference to avoid retain cycles
    
    init(gameManager: GameManager) {
        self.gameManager = gameManager
    }
    
    func addRotateAnimation(quad: QuadMesh, duration: TimeInterval, tilePosition: (x: Int, y: Int), objectsLayer: GraphicsLayer, effectsLayer: EffectsLayer) {
        let animation = AnimationPools.rotateAnimationPool.getObject()
        animation.configure(quad: quad, duration: duration, tilePosition: tilePosition, objectsLayer: objectsLayer, effectsLayer: effectsLayer)
        rotateAnimations.append(animation)
    }
    
    func addFallAnimation(quad: QuadMesh, targetY: Float, tilePosition: (x: Int, y: Int)) {
        let animation = AnimationPools.fallAnimationPool.getObject()
        animation.configure(quad: quad, targetY: targetY, tilePosition: tilePosition)
        fallAnimations.append(animation)
    }
    
    func addParticleAnimation(speedLimit: Float, width: Float, count: Int, duration: TimeInterval, tilePosition: (x: Int, y: Int), targetScreen: Screen) {
        let animation = AnimationPools.particleAnimationPool.getObject()
        animation.configure(speedLimit: speedLimit, width: width, count: count, duration: duration, tilePosition: tilePosition, targetScreen: targetScreen)
        particleAnimations.append(animation)
    }

    func addFreezeFrameAnimation(duration: TimeInterval) {
        let animation = AnimationPools.freezeFrameAnimationPool.getObject()
        animation.configure(duration: duration)
        freezeFrameAnimations.append(animation)
    }

    func updateAnimations() {
        // do the freeze frame animations first
        if let freezeFrame = freezeFrameAnimations.first {
            freezeFrame.update()
            if freezeFrame.isFinished {
                freezeFrame.cleanup()
                freezeFrameAnimations.removeFirst()
                AnimationPools.freezeFrameAnimationPool.releaseObject(freezeFrame)
            }
            // and don't do anything else until they are over
            return
        }
        
        updateRotateAnimations()
        updateFallAnimations()
        updateParticleAnimations()
    }
    
    private func updateRotateAnimations() {
        for animation in rotateAnimations {
            animation.update()
        }
        
        guard let gameManager = gameManager else { return }
        rotateAnimations.removeAll { animation in
            if animation.isFinished {
                let tilePosition = animation.tilePosition
                gameManager.gameBoard?.connectMarkings[tilePosition.x][tilePosition.y] = .none
                gameManager.gameBoard?.checkConnections()
                gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
                gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
                gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
                gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
                animation.cleanup()
                AnimationPools.rotateAnimationPool.releaseObject(animation)
                return true
            }
            return false
        }
    }
    
    private func updateFallAnimations() {
        for animation in fallAnimations {
            animation.update()
        }
        
        fallAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                AnimationPools.fallAnimationPool.releaseObject(animation)
                return true
            }
            return false
        }
    }
    
    private func updateParticleAnimations() {
        for animation in particleAnimations {
            animation.update()
        }
        
        particleAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                AnimationPools.particleAnimationPool.releaseObject(animation)
                return true
            }
            return false
        }
    }

}

// // // // // // // // // // // // // // // // // // // // //
//
// Animation - protocol to say what an animation is
//

protocol Animation {
    var isFinished: Bool { get }
    var tilePosition: (x: Int, y: Int) { get }
    func update()
    func cleanup()
}

// // // // // // // // // // // // // // // // // // // // //
//
// RotateAnimation - class defining and managing a rotating tile animation
//

class RotateAnimation: Animation, Poolable {
    var available: Bool = true
    private var quad: QuadMesh?
    private var duration: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    private var startRotation: Float = 0
    private var endRotation: Float = 0
    var tilePosition: (x: Int, y: Int) = (0, 0)
    
    private var tempQuad: QuadMesh?
    private weak var objectsLayer: GraphicsLayer?
    private weak var effectsLayer: EffectsLayer?
    
    required init() {}
    
    func resetToUnused() {
        available = true
        quad = nil
        duration = 0
        elapsedTime = 0
        startRotation = 0
        endRotation = 0
        tilePosition = (0, 0)
        tempQuad = nil
        objectsLayer = nil
        effectsLayer = nil
    }

    func configure(quad: QuadMesh, duration: TimeInterval, tilePosition: (x: Int, y: Int), objectsLayer: GraphicsLayer, effectsLayer: EffectsLayer) {
        self.quad = quad
        self.duration = duration
        self.tilePosition = tilePosition
        self.endRotation = quad.rotation
        self.startRotation = quad.rotation + .pi / 2
        self.objectsLayer = objectsLayer
        self.effectsLayer = effectsLayer

        let tempQuad = QuadMesh(size: 100.0, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(0.25, 0.25))
        tempQuad.position = quad.position
        tempQuad.rotation = quad.rotation
        effectsLayer.meshes.append(tempQuad)
        self.tempQuad = tempQuad
    }

    var isFinished: Bool {
        return elapsedTime >= duration
    }
    
    func update() {
        guard !isFinished else { return }
        guard quad != nil else { return }
        guard tempQuad != nil else { return }
        
        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
        let progress = min(elapsedTime / duration, 1.0)
        
        // Interpolate rotation
        let newRotation = startRotation + (endRotation - startRotation) * Float(progress)
        quad!.rotation = newRotation
        tempQuad?.rotation = newRotation
        
        // Update the connections at the end of the animation
        if progress >= 1.0 {
            quad!.rotation = endRotation
            tempQuad?.rotation = endRotation
            
            // Remove the temporary object from the objectsLayer
            if let tempQuad = tempQuad {
                effectsLayer?.meshes.removeAll { $0 === tempQuad }
            }
        }
    }
    
    func cleanup() {
        if let tempQuad = tempQuad {
            effectsLayer?.meshes.removeAll { $0 === tempQuad }
        }
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// ParticleAnimation - class defining and managing animating particles
//

class ParticleAnimation: Animation, Poolable {
    private var duration: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0

    var isFinished: Bool {
        return elapsedTime >= duration
    }

    var tilePosition: (x: Int, y: Int) = (0, 0)
    private var effectsLayer: EffectsLayer?
    private weak var targetScreen: Screen?

    var available: Bool = true

    required init() {}

    func resetToUnused() {
        available = true
        duration = 0
        elapsedTime = 0
        tilePosition = (0, 0)
        effectsLayer?.removeAllParticles()
        effectsLayer = nil
        if targetScreen != nil {
            if effectsLayer != nil {
                targetScreen?.removeLayer(effectsLayer!)
            }
        }
        targetScreen = nil
    }

    func configure(speedLimit: Float, width: Float, count: Int, duration: TimeInterval, tilePosition: (x: Int, y: Int), targetScreen: Screen) {
        self.duration = duration
        self.tilePosition = tilePosition
        self.targetScreen = targetScreen
        available = false
        
        // Create a new EffectsLayer
        self.effectsLayer = EffectsLayer()
        effectsLayer?.texture = Renderer.textures.getTexture(named: "arrows")
        
        let position = SIMD2<Float>(Float(tilePosition.x + 2) * tileSize - boardW / 2.0,
                                    Float(tilePosition.y + 1) * tileSize - boardH / 2.0)
        effectsLayer?.generateParticles(position: position, speedLimit: speedLimit, width: width, count: count)

        // Add the new EffectsLayer to the target screen's layers
        targetScreen.addLayer(effectsLayer!)
    }

    func update() {
        guard !isFinished else { return }
        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
    }

    func cleanup() {
        // Remove all particles from effectsLayer
        effectsLayer?.removeAllParticles()
        // Remove the EffectsLayer from the target screen's layers
        targetScreen?.removeLayer(effectsLayer!)
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// FallAnimation - class defining and managing a falling tile animation
//

class FallAnimation: Animation, Poolable {
    private var quad: QuadMesh?
    private var targetY: Float = 0
    private var elapsedTime: TimeInterval = 0
    private var speed: Float = 0

    static var gravity: Float = 9.8
    static var friction: Float = 0.005
    static var speedFactor: Float = 1.0

    var isFinished: Bool {
        guard let quad = quad else { return true }
        return quad.position.y >= targetY
    }

    var tilePosition: (x: Int, y: Int) = (0, 0)

    var available: Bool = true

    required init() {}

    func configure(quad: QuadMesh, targetY: Float, tilePosition: (x: Int, y: Int)) {
        self.quad = quad
        self.targetY = targetY
        self.tilePosition = tilePosition
        self.elapsedTime = 0
        self.speed = 0
        self.available = false
    }

    func resetToUnused() {
        quad = nil
        targetY = 0
        elapsedTime = 0
        speed = 0
        tilePosition = (0, 0)
        available = true
    }

    func update() {
        guard let quad = quad, !isFinished else {
            self.quad?.position.y = targetY
            return
        }

        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
        speed += FallAnimation.gravity * FallAnimation.speedFactor * (1 / 60.0)
        speed *= (1.0 - FallAnimation.friction)
        quad.position.y += speed

        if quad.position.y >= targetY {
            quad.position.y = targetY
            SoundManager.shared.playSoundEffect(filename: "buzz")
        }
    }

    func cleanup() {
        // Cleanup logic if necessary
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// FreezeFrameAnimation - high priority animation that stops everything else until it's done
//

class FreezeFrameAnimation: Animation, Poolable {
    private var duration: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    var tilePosition: (x: Int, y: Int) = (0, 0) // Dummy position as it's not used

    var isFinished: Bool {
        return elapsedTime >= duration
    }

    var available: Bool = true

    required init() {}

    func configure(duration: TimeInterval) {
        self.duration = duration
        self.elapsedTime = 0
        self.available = false
    }

    func resetToUnused() {
        duration = 0
        elapsedTime = 0
        available = true
    }

    func update() {
        guard !isFinished else { return }
        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
    }

    func cleanup() {
        // Cleanup logic if necessary
    }
}

