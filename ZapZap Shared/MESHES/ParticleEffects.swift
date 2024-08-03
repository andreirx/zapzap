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

class Particle: SegmentStripMesh {
    static var friction: Float = 0.02
    static var attractor: SIMD2<Float> = SIMD2<Float>(-300, -300)
    static var attractStrength: Float = 0.5
    static var speedFactor: Float = 0.3

    var speed: SIMD2<Float>

    init(position: SIMD2<Float>, speed: SIMD2<Float>, width: Float, color: SegmentColor) {
        self.speed = speed
        super.init(points: [SIMD2<Float>(0, 0), speed], width: width, color: color)
        self.position = position
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

    static func generate(device: MTLDevice, count: Int, speedLimit: Float, width: Float, color: SegmentColor) -> [Particle] {
        var particles: [Particle] = []

        for _ in 0..<count {
            let randomX = Float.random(in: -speedLimit...speedLimit)
            let randomY = Float.random(in: -speedLimit...speedLimit)
            let speed = SIMD2<Float>(randomX, randomY)
            let position = SIMD2<Float>(0, 0) // Initial position
            let particle = Particle(position: position, speed: speed, width: width, color: color)
            particles.append(particle)
        }

        return particles
    }
}

