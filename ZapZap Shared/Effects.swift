//
//  Effects.swift
//  ZapZap
//
//  Created by apple on 31.07.2024.
//

import simd
import Foundation
import Metal

let maxArcDisplacement: Float = 0.2

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
