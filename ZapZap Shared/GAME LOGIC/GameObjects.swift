//
//  GameObjects.swift
//  ZapZap
//
//  Created by apple on 19.08.2024.
//

import Foundation
import simd

// Base class for all game objects with rotation and pulsating scale
class GameObject: QuadMesh {
    private var rotationSpeed: Float
    var baseScale: Float
    private var maxScale: Float
    private var pulseFreq: Float
    private var frameIndex: Int = 0
    var sound: String = "powerup"
    var tilePosition: (x: Int, y: Int) = (-1, -1) // start off the table
    var bonusPoints: Int = 0

    // static Dictionary mapping types to their respective initializers
    static let objectFactory: [ObjectIdentifier: () -> GameObject] = [
        ObjectIdentifier(Bonus1.self): { Bonus1() },
        ObjectIdentifier(Bonus2.self): { Bonus2() },
        ObjectIdentifier(Bonus5.self): { Bonus5() },
        ObjectIdentifier(Bomb.self): { Bomb() }
    ]

    init(size: Float, topLeftUV: SIMD2<Float>, bottomRightUV: SIMD2<Float>,
         rotationSpeed: Float = 1.0, baseScale: Float = 1.0, maxScale: Float = 1.3, pulseFreq: Float = 0.2) {
        self.rotationSpeed = rotationSpeed
        self.baseScale = baseScale
        self.maxScale = maxScale
        self.pulseFreq = pulseFreq
        super.init(size: size, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV)
        self.alpha = 4.0
    }

    // Update the object each frame
    func update() {
        // Rotate the object
        rotation += rotationSpeed * (.pi / 180.0)
        
        // Apply pulsating scale
        scale = baseScale + sin(pulseFreq * Float(frameIndex)) * (maxScale - baseScale) / 2.0
        
        // Increment the frame index
        frameIndex += 1
    }
}

// Bonus objects
class Bonus1: GameObject {
    init() {
        let size = tileSize * 0.8
        let topLeftUV = SIMD2<Float>(3.0 / 8.0, 2.0 / 8.0)
        let bottomRightUV = SIMD2<Float>(4.0 / 8.0, 3.0 / 8.0)
        super.init(size: size, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV, rotationSpeed: 0.0, pulseFreq: 0.11)
        self.alpha = 1.5
        self.bonusPoints = 1
    }
}

class Bonus2: GameObject {
    init() {
        let size = tileSize * 0.8
        let topLeftUV = SIMD2<Float>(3.0 / 8.0, 3.0 / 8.0)
        let bottomRightUV = SIMD2<Float>(4.0 / 8.0, 4.0 / 8.0)
        super.init(size: size, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV, rotationSpeed: 0.0, pulseFreq: 0.12)
        self.alpha = 2.0
        self.bonusPoints = 2
    }
}

class Bonus5: GameObject {
    init() {
        let size = tileSize * 0.8
        let topLeftUV = SIMD2<Float>(3.0 / 8.0, 4.0 / 8.0)
        let bottomRightUV = SIMD2<Float>(4.0 / 8.0, 5.0 / 8.0)
        super.init(size: size, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV, rotationSpeed: 0.0, pulseFreq: 0.15)
        self.alpha = 3.5
        self.bonusPoints = 5
    }
}

// Bomb object
class Bomb: GameObject {
    init() {
        let size = tileSize * 0.8
        let topLeftUV = SIMD2<Float>(5.0 / 8.0, 1.0 / 8.0)
        let bottomRightUV = SIMD2<Float>(6.0 / 8.0, 2.0 / 8.0)
        super.init(size: size, topLeftUV: topLeftUV, bottomRightUV: bottomRightUV, rotationSpeed: 0.0, pulseFreq: 0.03)
        self.alpha = 3.0
        self.bonusPoints = -5
        self.sound = "bomb"
    }
    
    func explode() {
        // Define the bomb explosion logic here
    }
}
