//
//  GameBoardAnimations.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

import Foundation
import simd

// // // // // // // // // // // // // // // // // // // // //
//
// AnimationManager - class to manage animations around
//

class AnimationManager {
    var simpleRotateAnimations: [SimpleRotateAnimation] = []
    var rotateAnimations: [RotateAnimation] = []
    var fallAnimations: [FallAnimation] = []
    var particleAnimations: [ParticleAnimation] = []
    var freezeFrameAnimations: [FreezeFrameAnimation] = []
    var objectFallAnimations: [ObjectFallAnimation] = []
    var textAnimations: [TextAnimation] = []
    var superAnimations: SuperheroAnimation?
    
    var fingerQuad: QuadMesh!

    weak var gameManager: GameManager? // Use weak reference to avoid retain cycles
    
    init(gameManager: GameManager) {
        // there will be only one finger on the screen ;)
        fingerQuad = QuadMesh(size: 5.0 * tileSize, topLeftUV: SIMD2<Float>(1.0/4.0, 5.0/8.0), bottomRightUV: SIMD2<Float>(3.0/4.0, 8.0/8.0))
        // but we start by hiding it
        fingerQuad.alpha = 0.0
        fingerQuad.position.x = 0.0
        fingerQuad.position.y = 0.0
        
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
    func addFreezeFrameAnimation(duration: TimeInterval, drop1s: Int, drop2s: Int, drop5s: Int) {
        let animation = AnimationPools.freezeFrameAnimationPool.getObject()
        animation.configure(duration: duration, drop1s: drop1s, drop2s: drop2s, drop5s: drop5s)
        
        guard let gameManager = gameManager else { return }
        gameManager.gameBoard?.checkConnections()
        gameManager.renderer!.effectsLayer.meshes.removeAll { $0 is ElectricArcMesh }
        gameManager.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        gameManager.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)

        freezeFrameAnimations.append(animation)
    }

    // this will animate the superheroes
    func addSuperheroAnimation() {
        SoundManager.shared.playSoundEffect(filename: "superhero")
        superAnimations = SuperheroAnimation(sLeft: (gameManager?.superheroLeft)!, sRight: (gameManager?.superheroRight)!)
    }

    // this will remove all gameplay animations - in a graceful way
    // that means also cleanup any associated objects
    // and put them back into their pools if they come from pools
    func removeAllGameplayAnimations() {
        // just remove the object falling animations, they don't go to pools
        objectFallAnimations.removeAll()

        // iterate through all text animations
        for animation in textAnimations {
            // cleanup to remove the text itself not just the animation
            animation.cleanup()
        }
        // just remove the text animations, they don't go to pools either
        textAnimations.removeAll()

        // Iterate through all freeze frame animations
        for freezeFrame in freezeFrameAnimations {
            // Call cleanup to ensure resources are freed properly
            freezeFrame.cleanup()

            // Return the animation object to the pool
            AnimationPools.freezeFrameAnimationPool.releaseObject(freezeFrame)
        }
        // Clear the array after releasing all objects
        freezeFrameAnimations.removeAll()

        // Iterate through all particle animations
        for animation in particleAnimations {
            // Call cleanup to ensure resources are freed properly
            animation.cleanup()

            // Return the animation object to the pool
            AnimationPools.particleAnimationPool.releaseObject(animation)
        }
        // Clear the array after releasing all objects
        particleAnimations.removeAll()

        // Iterate through all rotate animations
        for animation in rotateAnimations {
            // Call cleanup to ensure resources are freed properly
            animation.cleanup()

            // Return the animation object to the pool
            AnimationPools.rotateAnimationPool.releaseObject(animation)
        }
        // Clear the array after releasing all objects
        rotateAnimations.removeAll()

        // Iterate through all fall animations
        for fallAnimation in fallAnimations {
            // Call cleanup to ensure resources are freed properly
            fallAnimation.cleanup()

            // Return the animation object to the pool
            AnimationPools.fallAnimationPool.releaseObject(fallAnimation)
        }
        // Clear the array after releasing all objects
        fallAnimations.removeAll()
    }
    
    // Add a simple rotation animation to the list
    func addSimpleRotation(_ animation: SimpleRotateAnimation) {
        if simpleRotateAnimations.isEmpty {
            // only ONE AT A TIME
            simpleRotateAnimations.append(animation)
        }
    }

    // Update all simple rotate animations each frame
    func updateSimpleRotateAnimations() {
        for animation in simpleRotateAnimations {
            animation.update()
        }
        
        // Remove finished animations
        simpleRotateAnimations.removeAll { $0.isFinished }
    }

    // function to check whether there are objects on this tile
    func anythingOnThisTile(i: Int, j: Int) -> Bool {
        guard let gameManager = gameManager else { return false }

        if gameManager.gameBoard?.connectMarkings[i - 1][j] != Connection.none {
            return true
        }
        
        for mesh in gameManager.renderer!.objectsLayer.meshes {
            if let bonus = mesh as? GameObject {
                if i-1 == bonus.tilePosition.x && j == bonus.tilePosition.y {
                    return true
                }
            }
        }
        
        return false
    }
    
    // this will create a falling object animation
    // Function to create a falling object with a specific type
    func createFallingObject(objectType: GameObject.Type) {
        guard let gameManager = gameManager else { return }
        
        // Choose a random tile on the game board
        var randomX = 1 + Int.random(in: 0..<gameManager.gameBoard!.width)
        var randomY = Int.random(in: 0..<gameManager.gameBoard!.height)
        // if a bonus is falling on "something", choose another position
        while anythingOnThisTile(i: randomX, j: randomY) {
            randomX = 1 + Int.random(in: 0..<gameManager.gameBoard!.width)
            randomY = Int.random(in: 0..<gameManager.gameBoard!.height)
        }
        
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
        // set the tile position
        gameObject.tilePosition.x = randomX - 1
        gameObject.tilePosition.y = randomY
        
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
        updateSimpleRotateAnimations()
        
        // finger update
//        fingerQuad.alpha = 0.5 + 0.5 * sin(Float(gameManager!.renderer!.frameIndex) / 60.0)

        // superheroes fly even during freeze frames
        if superAnimations != nil {
            superAnimations?.update()
        }
        
        // do the freeze frame animations first
        if let freezeFrame = freezeFrameAnimations.first {
            freezeFrame.update()
            if freezeFrame.isFinished {
                addSuperheroAnimation()
                gameManager?.dropCoins(many1: freezeFrame.drop1, many2: freezeFrame.drop2, many5: freezeFrame.drop5)
                freezeFrame.cleanup()
                freezeFrameAnimations.removeFirst()
                AnimationPools.freezeFrameAnimationPool.releaseObject(freezeFrame)

                // normally after a freeze frame, tiles will be falling
                gameManager!.zapGameState = .fallingTiles
                gameManager!.clearElectricArcs()
                if gameManager!.zapGameState == .freezeDuringZap {
                    // after the last freeze frame completes, remove the arcs
                } else if gameManager!.zapGameState == .freezeDuringBomb {
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
                // rotating tile animation completed
                // get tile position for this animation
                let tilePosition = animation.tilePosition

                // mark this tile as not connecting
                gameManager.gameBoard?.connectMarkings[tilePosition.x][tilePosition.y] = .none
                gameManager.gameBoard?.checkConnections()
                // remove electric arcs
                gameManager.clearElectricArcs()
                // remake the arcs only if there's no falling tiles
                // on
                if fallAnimations.isEmpty {
                    gameManager.addElectricArcs()
                    // ok so we also need to check for bonuses now
                    // Collect bonuses to be removed
                    var bonusesToRemove: [GameObject] = []
                    var didBomb = false
                    // Check for bonuses on the table - and remove those that are picked
                    for mesh in gameManager.renderer!.objectsLayer.meshes {
                        // uhh
                        if let bonus = mesh as? GameObject {
                            if bonus.scale < 2 {
                                let tileX = bonus.tilePosition.x
                                let tileY = bonus.tilePosition.y
                                
                                if let marking = gameManager.gameBoard?.connectMarkings[tileX][tileY] {
                                    if marking == .left {
                                        if bonus.bonusPoints != 0 {
                                            gameManager.updateScoreLeft(byPoints: bonus.bonusPoints, atTile: (tileX + 1, tileY))
                                        }
                                        bonusesToRemove.append(bonus)
                                        // play that sound
                                        SoundManager.shared.playSoundEffect(filename: bonus.sound)
                                        // was it a bomb?
                                        if let _ = bonus as? Bomb {
                                            gameManager.powerLBomb = true
                                            gameManager.renderer!.objLBomb!.alpha = 1.0
//                                            gameManager.bombTable(ati: tileX, atj: tileY)
//                                            didBomb = true
                                        }
                                        // was it a cross?
                                        if let _ = bonus as? Cross {
                                            gameManager.powerLCross = true
                                            gameManager.renderer!.objLCross!.alpha = 1.0
                                        }
                                        // was it an arrow?
                                        if let _ = bonus as? Arrow {
                                            gameManager.powerLArrow = true
                                            gameManager.renderer!.objLArrow!.alpha = 1.0
                                        }
                                    } else if marking == .right {
                                        if bonus.bonusPoints != 0 {
                                            gameManager.updateScoreRight(byPoints: bonus.bonusPoints, atTile: (tileX + 1, tileY))
                                        }
                                        bonusesToRemove.append(bonus)
                                        // play that sound
                                        SoundManager.shared.playSoundEffect(filename: bonus.sound)
                                        // was it a bomb?
                                        if let _ = bonus as? Bomb {
                                            gameManager.powerRBomb = true
                                            gameManager.renderer!.objRBomb!.alpha = 1.0
//                                            gameManager.bombTable(ati: tileX, atj: tileY)
//                                            didBomb = true
                                        }
                                        // was it a cross?
                                        if let _ = bonus as? Cross {
                                            gameManager.powerRCross = true
                                            gameManager.renderer!.objRCross!.alpha = 1.0
                                        }
                                        // was it an arrow?
                                        if let _ = bonus as? Arrow {
                                            gameManager.powerRArrow = true
                                            gameManager.renderer!.objRArrow!.alpha = 1.0
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Remove the collected bonuses
                    gameManager.renderer!.objectsLayer.meshes.removeAll { mesh in
                        return bonusesToRemove.contains(where: { $0 === mesh })
                    }
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
        
        // this marks the end of the falling animations
        if removedOne && fallAnimations.isEmpty {
            gameManager.zapGameState = .waitingForInput
            gameManager.gameBoard?.checkConnections()
            gameManager.clearElectricArcs()
            gameManager.addElectricArcs()
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
        
        var removedOne = false
        // remove the completed animation objects from the list
        objectFallAnimations.removeAll { animation in
            if animation.isFinished {
                animation.cleanup()
                removedOne = true
                return true
            }
            return false
        }
        
        // this marks the end of the falling objects
        if removedOne && objectFallAnimations.isEmpty {
            gameManager?.zapGameState = .waitingForInput
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

        let tempQuad = QuadMesh(size: tileSize * 2.5, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(0.25, 0.25))
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
// SimpleRotateAnimation - class defining and managing a rotating unrelated quad animation
//

class SimpleRotateAnimation: Animation {
    var tilePosition: (x: Int, y: Int)
    
    private var quad: QuadMesh
    private var fingerQuad: QuadMesh
    private var duration: Float
    private var elapsedTime: Float = 0.0
    private var startRotation: Float
    private var endRotation: Float
    private var tempQuad: QuadMesh?
    private weak var effectsLayer: EffectsLayer?

    // Duration for each phase
    private var fingerDuration: Float
    private var rotateDuration: Float

    // Initialize with the QuadMesh to rotate, the finger quad, and the duration of the animation
    init(quad: QuadMesh, fingerQuad: QuadMesh, duration: Float, effectsLayer: EffectsLayer) {
        self.quad = quad
        self.fingerQuad = fingerQuad
        self.duration = duration
        self.startRotation = quad.rotation
        self.endRotation = quad.rotation - (.pi / 2) // Rotate by 90 degrees
        self.tilePosition = (-1, -1)
        self.effectsLayer = effectsLayer
        
        self.fingerDuration = duration * 0.4  // 40% of the total duration for finger fade in/out
        self.rotateDuration = duration * 0.6  // 60% for tile rotation
        
        // Create the temp quad that follows the rotation
        let tempQuad = QuadMesh(size: 100.0, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(0.25, 0.25))
        tempQuad.position = quad.position
        tempQuad.rotation = quad.rotation
        tempQuad.scale = quad.scale
        tempQuad.alpha = 0.0
        self.tempQuad = tempQuad

        // Position and reset finger quad
        fingerQuad.position = quad.position
        fingerQuad.position.x += tileSize * 4.0
        fingerQuad.position.y += tileSize * 4.0
        fingerQuad.alpha = 0.0
//        effectsLayer.meshes.append(fingerQuad)
    }
    
    // Check if the animation is finished
    var isFinished: Bool {
        return elapsedTime >= duration
    }

    // Update the animation progress
    func update() {
        guard !isFinished else { return }
        
        elapsedTime += 1.0 / 60.0 // Assuming 60 FPS update rate

        // Handle finger phase (fading in and out)
        if elapsedTime <= fingerDuration {
            tempQuad?.alpha = 0.0
            let progress = elapsedTime / fingerDuration
            fingerQuad.alpha = sin(min(1.0, Float(progress)) * (.pi / 2.0)) // Fade in
            fingerQuad.position.x = quad.position.x + tileSize * 4.0 - progress * tileSize * 2.0
            fingerQuad.position.y = quad.position.y + tileSize * 4.0 - progress * tileSize * 2.0
        } else {
            if tempQuad?.alpha == 0.0 {
                effectsLayer!.meshes.append(tempQuad!)
            }
            tempQuad?.alpha = 1.0
            // Once fade-in is done, start fading out
            let fadeOutProgress = (elapsedTime - fingerDuration) / rotateDuration
            fingerQuad.alpha = sin(max(0.0, Float(1.0 - fadeOutProgress)) * (.pi / 2.0)) // Fade out
            fingerQuad.position.x = quad.position.x + tileSize * 2.0 + fadeOutProgress * tileSize * 2.0
            fingerQuad.position.y = quad.position.y + tileSize * 2.0 + fadeOutProgress * tileSize * 2.0
            // Once the finger phase is complete, start the rotation
            let rotateProgress = (elapsedTime - fingerDuration) / rotateDuration
            let rotationProgress = min(rotateProgress, 1.0)

            // Interpolate the rotation between startRotation and endRotation
            let newRotation = startRotation + (endRotation - startRotation) * Float(rotationProgress)
            quad.rotation = newRotation
            tempQuad?.rotation = newRotation

            // Once finished, make sure it's exactly the end rotation
            if rotationProgress >= 1.0 {
                quad.rotation = endRotation
                tempQuad?.rotation = endRotation
                cleanup()
            }
        }
    }

    // Cleanup the temporary quad and finger from the effects layer once the animation is finished
    func cleanup() {
        effectsLayer?.meshes.removeAll { $0 === tempQuad || $0 === fingerQuad }
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
    var drop1: Int = 0
    var drop2: Int = 0
    var drop5: Int = 0
    var tilePosition: (x: Int, y: Int) = (0, 0) // Dummy position as it's not used

    var isFinished: Bool {
        return elapsedTime >= duration
    }

    var available: Bool = true

    required init() {}

    func configure(duration: TimeInterval, drop1s: Int, drop2s: Int, drop5s: Int) {
        self.duration = duration
        self.elapsedTime = 0
        self.available = false
        self.drop1 = drop1s
        self.drop2 = drop2s
        self.drop5 = drop5s
    }

    func resetToUnused() {
        duration = 0
        elapsedTime = 0
        drop1 = 0
        drop2 = 0
        drop5 = 0
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

class SuperheroAnimation: Animation {
    private weak var superLeft: QuadMesh?
    private weak var superRight: QuadMesh?
    private let startAlpha: Float = 0.1
    private let alphaDecreaseRate: Float = 0.015 // Controls how quickly alpha decreases

    var isFinished: Bool {
        return superLeft!.alpha <= 0.0
    }

    var tilePosition: (x: Int, y: Int) = (0, 0)
    
    init(sLeft: QuadMesh, sRight: QuadMesh) {
        self.superLeft = sLeft
        self.superRight = sRight
        self.superLeft?.alpha = startAlpha
        self.superLeft?.position.y = 0.0
        self.superLeft?.scale = 1.0
        self.superRight?.alpha = startAlpha
        self.superRight?.position.y = 0.0
        self.superRight?.scale = 1.0
    }

    func update() {
        guard !isFinished else { cleanup();return }
        guard superLeft != nil else { return }
        guard superRight != nil else { return }

        // Decrease alpha gradually
        superLeft!.alpha -= alphaDecreaseRate
        superRight!.alpha -= alphaDecreaseRate
        superLeft!.position.y -= 2.0
        superRight!.position.y -= 2.0
    }
    
    func cleanup() {
        // cleanup logic if necessary
        superLeft?.alpha = 0.0
        superRight?.alpha = 0.0
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
        // scale will be 1 + K * (distance in tiles from target position) where K is 0.5
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
    private let startAlpha: Float = 4.0
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
