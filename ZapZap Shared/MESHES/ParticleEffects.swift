//
//  Effects.swift
//  ZapZap
//
//  Created by apple on 31.07.2024.
//

import simd
import MetalKit
import Foundation
import Metal


// // // // // // // // // // // // // // // // // // // // //
//
// Particle - a class that makes a SegmentStripMesh of 2 points and has physical properties
//

class Particle: SegmentStripMesh, Poolable {
    static var friction: Float = 0.02
    static var attractor: SIMD2<Float> = SIMD2<Float>(-300, -300)
    static var attractStrength: Float = 0.8
    static var speedFactor: Float = 0.8

    var speed: SIMD2<Float>
    var available: Bool = true  // Poolable property

    // Default initializer for object pool allocation
    required init() {
        self.speed = SIMD2<Float>(0, 0)
        super.init(points: [SIMD2<Float>(0, 0), SIMD2<Float>(0, 0)], width: 1.0, color: .white)
    }

    // Initializer with parameters for when an object is pulled from the pool
    init(position: SIMD2<Float>, speed: SIMD2<Float>, width: Float, color: SegmentColor) {
        self.speed = speed
        super.init(points: [SIMD2<Float>(0, 0), speed], width: width, color: color)
        self.position = position
    }

    // Function to set up the particle after it's pulled from the pool
    func setParameters(position: SIMD2<Float>, speed: SIMD2<Float>, width: Float, color: SegmentColor) {
        self.speed = speed
        self.width = width
        self.color = color
        self.position = position
        self.points = [SIMD2<Float>(0, 0), speed]
        self.available = false
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        update()

        // Update points for the SegmentStripMesh
        points[0] = SIMD2<Float>(0, 0)
        points[1] = speed

        // Re-make vertices based on updated points
        remakeVertices()
        
        super.draw(encoder: encoder)
    }

    private func update() {
        // Calculate the direction towards the attractor
        let toAttractor = normalize(Particle.attractor - position)
        
        // Apply attractor force
        speed += toAttractor * Particle.attractStrength

        // Apply friction
        speed *= 1.0 - Particle.friction

        // Update position
        position += speed * Particle.speedFactor
    }

    // Poolable method to reset the particle to an unused state
    func resetToUnused() {
        available = true
        // Reset other properties if necessary
    }

    // Factory method to generate particles using the pool
    static func generate(count: Int, speedLimit: Float, width: Float) -> [Particle] {
        var particles: [Particle] = []

        for _ in 0..<count {
            let randomX = Float.random(in: -speedLimit...speedLimit)
            let randomY = Float.random(in: -speedLimit...speedLimit)
            let speed = SIMD2<Float>(randomX, randomY)
            let position = SIMD2<Float>(0, 0) // Initial position
            let color = SegmentColor.random()

            // Get a particle from the pool and set its parameters
            var particle = AnimationPools.particlePool.getObject()
            particle.setParameters(position: position, speed: speed, width: width, color: color)
            
            particles.append(particle)
        }

        return particles
    }
}
