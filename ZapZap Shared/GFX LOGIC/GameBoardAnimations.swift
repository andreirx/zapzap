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
    var objectFallAnimations: [ObjectFallAnimation] = []
    var textAnimations: [TextAnimation] = []

    weak var gameManager: GameManager? // Use weak reference to avoid retain cycles
    
    init(gameManager: GameManager) {
        self.gameManager = gameManager
    }
    
    // this will also link a rotation indicator quad to the base tile quad
    func addRotateAnimation(quad: QuadMesh, duration: TimeInterval, tilePosition: (x: Int, y: Int), objectsLayer: GraphicsLayer, effectsLayer: EffectsLayer) {
        let animation = AnimationPools.rotateAnimationPool.getObject()
        animation.configure(quad: quad, duration: duration, tilePosition: tilePosition, objectsLayer: objectsLayer, effectsLayer: effectsLayer)
        rotateAnimations.append(animation)
    }
    
    // this is for falling tiles until they get into their ideal position
    func addFallAnimation(quad: QuadMesh, targetY: Float, tilePosition: (x: Int, y: Int)) {
        let animation = AnimationPools.fallAnimationPool.getObject()
        animation.configure(quad: quad, targetY: targetY, tilePosition: tilePosition)
        fallAnimations.append(animation)
    }
    
    // this is to start a burst of particles and add them to an effects layer in the desired screen
    func addParticleAnimation(speedLimit: Float, width: Float, count: Int, duration: TimeInterval, tilePosition: (x: Int, y: Int), targetScreen: Screen) {
        let animation = AnimationPools.particleAnimationPool.getObject()
        animation.configure(speedLimit: speedLimit, width: width, count: count, duration: duration, tilePosition: tilePosition, targetScreen: targetScreen)
        particleAnimations.append(animation)
    }

    // this will stop all other animations for the duration of the animation
    func addFreezeFrameAnimation(duration: TimeInterval) {
        let animation = AnimationPools.freezeFrameAnimationPool.getObject()
        animation.configure(duration: duration)
        
        guard let gameManager = gameManager else { return }
        gameManager.gameBoard?.checkConnections()
        gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
        gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)

        freezeFrameAnimations.append(animation)
    }
    
    // this will create a falling object animation
    // Function to create a falling object with a specific type
    func createFallingObject(objectType: GameObject.Type) {
        guard let gameManager = gameManager else { return }
        
        // Choose a random tile on the game board
        let randomX = 1 + Int.random(in: 0..<gameManager.gameBoard!.width)
        let randomY = Int.random(in: 0..<gameManager.gameBoard!.height)
        print("chose random position ", randomX, ", ", randomY)
        
        // Create the object instance
        // Retrieve the correct initializer and create the object
        guard let factory = GameObject.objectFactory[ObjectIdentifier(objectType)] else {
            print("Trying to create an animation for an unknown GameObject type")
            return
        }
        
        let gameObject = factory()

        // Set the initial position above the board
        let initialX = gameManager.getIdealTilePositionX(i: randomX)
        let initialY = gameManager.getIdealTilePositionY(j: randomY) - boardH / 2.0 // start Y is one board height above target Y
        gameObject.position = SIMD2<Float>(initialX, initialY)
        // scale will be 1 + K * (distance in tiles from target position) where K is 0.2
        gameObject.baseScale = 1.0 + 0.3 * (boardH / tileSize)
        
        // Calculate the target position (the tile's center)
        let targetY = gameManager.getIdealTilePositionY(j: randomY)
        
        // Add the object to the objects layer
        gameManager.renderer?.objectsLayer.meshes.append(gameObject)
        
        // Create a fall animation for this object
        let fallAnimation = ObjectFallAnimation(object: gameObject, targetY: targetY, tilePosition: (x: randomX, y: randomY))
        
        // Add the animation to the animation manager
        objectFallAnimations.append(fallAnimation)
    }
    
    // this will create a "floating text" that grows and fades away
    func createTextAnimation(text: String, font: Font, color: Color, size: CGSize, startPosition: SIMD2<Float>, textLayer: GraphicsLayer) {
        let textAnimation = TextAnimation(text: text, font: font, color: color, size: size, startPosition: startPosition, textLayer: textLayer)
        textAnimations.append(textAnimation)
    }

    // this will be called every frame
    func updateAnimations() {
        // only the text animations can go even during the freeze frames
        updateTextAnimations()
        
        // do the freeze frame animations first
        if let freezeFrame = freezeFrameAnimations.first {
            freezeFrame.update()
            if freezeFrame.isFinished {
                freezeFrame.cleanup()
                freezeFrameAnimations.removeFirst()
                AnimationPools.freezeFrameAnimationPool.releaseObject(freezeFrame)
                // after the last freeze frame completes, remove the arcs
                if freezeFrameAnimations.isEmpty {
                    gameManager!.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
                }
            }
            // and don't do anything else until they are over
            return
        }
        
        // if we're not in a freeze frame, continue updating the other animations
        updateRotateAnimations()
        updateFallAnimations()
        updateParticleAnimations()
        updateObjectFallAnimations()
    }
    
    // this handles updates to rotations and their completion
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
                // remake the arcs only if there's no falling tiles
                if fallAnimations.isEmpty {
                    gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
                    gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
                    gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
                }
                animation.cleanup()
                AnimationPools.rotateAnimationPool.releaseObject(animation)
                return true
            }
            return false
        }
    }
    
    // this handles updates to falling tiles and their completion
    private func updateFallAnimations() {
        guard let gameManager = gameManager else { return }

        for animation in fallAnimations {
            animation.update()
        }

        var removedOne = false
        fallAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                AnimationPools.fallAnimationPool.releaseObject(animation)
                removedOne = true
                return true
            }
            return false
        }
        
        if removedOne && fallAnimations.isEmpty {
            gameManager.gameBoard?.checkConnections()
            gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
            gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
            gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
            gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
        }

    }

    // this will update particle animations - and their completion
    private func updateParticleAnimations() {
        for animation in particleAnimations {
            animation.update()
        }
        
        // remove the completed animation objects from the list
        // return them to the object pool
        particleAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                AnimationPools.particleAnimationPool.releaseObject(animation)
                return true
            }
            return false
        }
    }

    // this will update object falling animation - until their completion
    private func updateObjectFallAnimations() {
        for animation in objectFallAnimations {
            animation.update()
        }
        
        // remove the completed animation objects from the list
        objectFallAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                return true
            }
            return false
        }
    }
    
    // this will update the floating text animations - until they are invisible
    private func updateTextAnimations() {
        for animation in textAnimations {
            animation.update()
        }
        
        // remove the completed animation objects from the list
        textAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
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
//            SoundManager.shared.playSoundEffect(filename: "buzz")
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

// // // // // // // // // // // // // // // // // // // // //
//
// ObjectFallAnimation - animation for objects falling from the sky
//

class ObjectFallAnimation: Animation {
    private let object: GameObject
    private let targetY: Float
    private var elapsedTime: TimeInterval = 0
    private var speed: Float = 0

    static var gravity: Float = 9.8
    static var friction: Float = 0.005
    static var speedFactor: Float = 1.0

    var isFinished: Bool {
        return object.position.y >= targetY
    }

    var tilePosition: (x: Int, y: Int)

    init(object: GameObject, targetY: Float, tilePosition: (x: Int, y: Int)) {
        self.object = object
        self.targetY = targetY
        self.tilePosition = tilePosition
    }

    func update() {
        guard !isFinished else {
            object.position.y = targetY
            self.object.baseScale = 1.0
            return
        }

        elapsedTime += 1 / 60.0 // Assuming 60 FPS update rate
        speed += ObjectFallAnimation.gravity * ObjectFallAnimation.speedFactor * (1 / 60.0)
        speed *= (1.0 - ObjectFallAnimation.friction)
        object.position.y += speed
        // scale will be 1 + K * (distance in tiles from target position) where K is 0.2
        object.baseScale = 1.0 + 0.5 * (targetY - object.position.y) / tileSize

        if object.position.y >= targetY {
            object.position.y = targetY
            self.object.baseScale = 1.0
        }
    }

    func cleanup() {
        // Cleanup logic if necessary
        // I mean we DO NOT want to remove the object after it fell
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// TextAnimation - animation for when you gain or lose something
//

class TextAnimation: Animation {
    private let textQuadMesh: TextQuadMesh
    private let startAlpha: Float = 3.0
    private let startScale: Float = 1.0
    private let alphaDecreaseRate: Float = 0.02 // Controls how quickly alpha decreases
    private let startPosition: SIMD2<Float>
    private weak var textLayer: GraphicsLayer?

    var isFinished: Bool {
        return textQuadMesh.alpha <= 0.0
    }

    var tilePosition: (x: Int, y: Int) = (0, 0) // Not used but required by the Animation protocol

    init(text: String, font: Font, color: Color, size: CGSize, startPosition: SIMD2<Float>, textLayer: GraphicsLayer) {
        self.textQuadMesh = TextQuadMesh(text: text, font: font, color: color, size: size)
        self.startPosition = startPosition
        self.textLayer = textLayer
        
        textQuadMesh.position = startPosition
        textQuadMesh.scale = startScale
        textQuadMesh.alpha = startAlpha
        
        textLayer.meshes.append(textQuadMesh)
    }

    func update() {
        guard !isFinished else { return }

        // Increase scale gradually
        textQuadMesh.scale += 0.02 // or use a different rate if desired
        
        // Decrease alpha gradually
        textQuadMesh.alpha -= alphaDecreaseRate

        // Drift upwards
        textQuadMesh.position.y -= 0.4 // Adjust speed of drifting as needed
    }
    
    func cleanup() {
        // Remove the text quad from the layer
        if let textLayer = textLayer {
            textLayer.meshes.removeAll { $0 === textQuadMesh }
        }
    }
}
