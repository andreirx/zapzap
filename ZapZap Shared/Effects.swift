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

let maxArcDisplacement: Float = 0.2

// // // // // // // // // // // // // // // // // // // // //
//
// ElectricArc - class that handles the points that make an electric arc
//

class ElectricArc {
    var startPoint: SIMD2<Float>
    var endPoint: SIMD2<Float>
    var points: [SIMD2<Float>]
    private var numberOfSegments: Int
    private var displacements: [Float]
    
    init(startPoint: SIMD2<Float>, endPoint: SIMD2<Float>, powerOfTwo: Int) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        
        self.numberOfSegments = Int(pow(2.0, Float(powerOfTwo)))
        self.points = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: numberOfSegments + 1)
        self.displacements = [Float](repeating: 0, count: numberOfSegments - 1)
        
        self.points[0] = startPoint
        self.points[numberOfSegments] = endPoint
        
        // Generate initial displacements
        generateDisplacements()
        // Generate points based on the initial displacements
        generatePoints(startIndex: 0, endIndex: numberOfSegments)
    }
    
    private func generateDisplacements() {
        for i in 0..<displacements.count {
            let displacement = Float.random(in: -maxArcDisplacement...maxArcDisplacement)
            displacements[i] = displacement
        }
    }
    
    private func generatePoints(startIndex: Int, endIndex: Int) {
        if endIndex - startIndex <= 1 {
            return
        }
        
        let midIndex = (startIndex + endIndex) / 2
        let startPoint = points[startIndex]
        let endPoint = points[endIndex]
        
        let midPoint = (startPoint + endPoint) / 2.0
        let dir = normalize(endPoint - startPoint)
        let perp = SIMD2<Float>(-dir.y, dir.x)
        let displacement = displacements[midIndex - 1] * distance(startPoint, endPoint)
        //        let displacement = (Float.random(in: -maxArcDisplacement...maxArcDisplacement) * distance(startPoint, endPoint))
        
        points[midIndex] = midPoint + perp * displacement
        
        generatePoints(startIndex: startIndex, endIndex: midIndex)
        generatePoints(startIndex: midIndex, endIndex: endIndex)
    }
    
    func twitchPoints(byFactor: Float) {
        for i in 0..<displacements.count {
            let change = byFactor * Float.random(in: -1.0...1.0)
            displacements[i] += change
            displacements[i] = min(max(displacements[i], -maxArcDisplacement), maxArcDisplacement)
        }
        
        // Regenerate points based on the updated displacements
        generatePoints(startIndex: 0, endIndex: numberOfSegments)
    }
}


// // // // // // // // // // // // // // // // // // // // //
//
// ElectricArcMesh - a class that combines the SegmentStripMesh and ElectricArc
//

// a class that combines the SegmentStripMesh and ElectricArc to allow
// using the point management from ElectricArc
// and the strip management from SegmentStripMesh

class ElectricArcMesh: SegmentStripMesh {
    var electricArc: ElectricArc

    init(device: MTLDevice, startPoint: SIMD2<Float>, endPoint: SIMD2<Float>, powerOfTwo: Int, width: Float, color: SegmentColor) {
        self.electricArc = ElectricArc(startPoint: startPoint, endPoint: endPoint, powerOfTwo: powerOfTwo)
        super.init(device: device, points: electricArc.points, width: width, color: color)
    }

    func twitch(byFactor: Float) {
        electricArc.twitchPoints(byFactor: byFactor)
        self.points = electricArc.points
        remakeVertices()
    }
}

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

    init(device: MTLDevice, position: SIMD2<Float>, speed: SIMD2<Float>, width: Float, color: SegmentColor) {
        self.speed = speed
        super.init(device: device, points: [SIMD2<Float>(0, 0), speed], width: width, color: color)
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
            let particle = Particle(device: device, position: position, speed: speed, width: width, color: color)
            particles.append(particle)
        }

        return particles
    }
}

