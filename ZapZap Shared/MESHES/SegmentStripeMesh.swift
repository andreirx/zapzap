//
//  SegmentStripeMesh.swift
//  ZapZap
//
//  Created by apple on 03.08.2024.
//

import Foundation
import Metal
import simd

// // // // // // // // // // // // // // // // // // // // //
//
// SegmentColor - texture positions
//

enum SegmentColor {
    case red, orange, yellow, limeGreen, green, greenCyan, cyan, skyBlue, blue, indigo, magenta, pink, white

    var textureCoordinates: (first: (start: SIMD2<Float>, end: SIMD2<Float>), middle: (start: SIMD2<Float>, end: SIMD2<Float>), last: (start: SIMD2<Float>, end: SIMD2<Float>)) {
        let tu = Float(1.0 / 8.0)
        switch self {
        case .red:
            return ((SIMD2<Float>(4.0 * tu, 5.0 * tu), SIMD2<Float>(5.0 * tu, 5.0 * tu)),
                    (SIMD2<Float>(4.0 * tu, 5.5 * tu), SIMD2<Float>(5.0 * tu, 5.5 * tu)),
                    (SIMD2<Float>(4.0 * tu, 6.0 * tu), SIMD2<Float>(5.0 * tu, 6.0 * tu)))
        case .orange:
            return ((SIMD2<Float>(5.0 * tu, 5.0 * tu), SIMD2<Float>(6.0 * tu, 5.0 * tu)),
                    (SIMD2<Float>(5.0 * tu, 5.5 * tu), SIMD2<Float>(6.0 * tu, 5.5 * tu)),
                    (SIMD2<Float>(5.0 * tu, 6.0 * tu), SIMD2<Float>(6.0 * tu, 6.0 * tu)))
        case .yellow:
            return ((SIMD2<Float>(6.0 * tu, 5.0 * tu), SIMD2<Float>(7.0 * tu, 5.0 * tu)),
                    (SIMD2<Float>(6.0 * tu, 5.5 * tu), SIMD2<Float>(7.0 * tu, 5.5 * tu)),
                    (SIMD2<Float>(6.0 * tu, 6.0 * tu), SIMD2<Float>(7.0 * tu, 6.0 * tu)))
        case .limeGreen:
            return ((SIMD2<Float>(7.0 * tu, 5.0 * tu), SIMD2<Float>(8.0 * tu, 5.0 * tu)),
                    (SIMD2<Float>(7.0 * tu, 5.5 * tu), SIMD2<Float>(8.0 * tu, 5.5 * tu)),
                    (SIMD2<Float>(7.0 * tu, 6.0 * tu), SIMD2<Float>(8.0 * tu, 6.0 * tu)))
        case .green:
            return ((SIMD2<Float>(4.0 * tu, 4.0 * tu), SIMD2<Float>(5.0 * tu, 4.0 * tu)),
                    (SIMD2<Float>(4.0 * tu, 4.5 * tu), SIMD2<Float>(5.0 * tu, 4.5 * tu)),
                    (SIMD2<Float>(4.0 * tu, 5.0 * tu), SIMD2<Float>(5.0 * tu, 5.0 * tu)))
        case .greenCyan:
            return ((SIMD2<Float>(5.0 * tu, 4.0 * tu), SIMD2<Float>(6.0 * tu, 4.0 * tu)),
                    (SIMD2<Float>(5.0 * tu, 4.5 * tu), SIMD2<Float>(6.0 * tu, 4.5 * tu)),
                    (SIMD2<Float>(5.0 * tu, 5.0 * tu), SIMD2<Float>(6.0 * tu, 5.0 * tu)))
        case .cyan:
            return ((SIMD2<Float>(6.0 * tu, 4.0 * tu), SIMD2<Float>(7.0 * tu, 4.0 * tu)),
                    (SIMD2<Float>(6.0 * tu, 4.5 * tu), SIMD2<Float>(7.0 * tu, 4.5 * tu)),
                    (SIMD2<Float>(6.0 * tu, 5.0 * tu), SIMD2<Float>(7.0 * tu, 5.0 * tu)))
        case .skyBlue:
            return ((SIMD2<Float>(7.0 * tu, 4.0 * tu), SIMD2<Float>(8.0 * tu, 4.0 * tu)),
                    (SIMD2<Float>(7.0 * tu, 4.5 * tu), SIMD2<Float>(8.0 * tu, 4.5 * tu)),
                    (SIMD2<Float>(7.0 * tu, 5.0 * tu), SIMD2<Float>(8.0 * tu, 5.0 * tu)))
        case .blue:
            return ((SIMD2<Float>(4.0 * tu, 3.0 * tu), SIMD2<Float>(5.0 * tu, 3.0 * tu)),
                    (SIMD2<Float>(4.0 * tu, 3.5 * tu), SIMD2<Float>(5.0 * tu, 3.5 * tu)),
                    (SIMD2<Float>(4.0 * tu, 4.0 * tu), SIMD2<Float>(5.0 * tu, 4.0 * tu)))
        case .indigo:
            return ((SIMD2<Float>(5.0 * tu, 3.0 * tu), SIMD2<Float>(6.0 * tu, 3.0 * tu)),
                    (SIMD2<Float>(5.0 * tu, 3.5 * tu), SIMD2<Float>(6.0 * tu, 3.5 * tu)),
                    (SIMD2<Float>(5.0 * tu, 4.0 * tu), SIMD2<Float>(6.0 * tu, 4.0 * tu)))
        case .magenta:
            return ((SIMD2<Float>(6.0 * tu, 3.0 * tu), SIMD2<Float>(7.0 * tu, 3.0 * tu)),
                    (SIMD2<Float>(6.0 * tu, 3.5 * tu), SIMD2<Float>(7.0 * tu, 3.5 * tu)),
                    (SIMD2<Float>(6.0 * tu, 4.0 * tu), SIMD2<Float>(7.0 * tu, 4.0 * tu)))
        case .pink:
            return ((SIMD2<Float>(7.0 * tu, 3.0 * tu), SIMD2<Float>(8.0 * tu, 3.0 * tu)),
                    (SIMD2<Float>(7.0 * tu, 3.5 * tu), SIMD2<Float>(8.0 * tu, 3.5 * tu)),
                    (SIMD2<Float>(7.0 * tu, 4.0 * tu), SIMD2<Float>(8.0 * tu, 4.0 * tu)))
        case .white:
            return ((SIMD2<Float>(7.0 * tu, 2.0 * tu), SIMD2<Float>(8.0 * tu, 2.0 * tu)),
                    (SIMD2<Float>(7.0 * tu, 2.5 * tu), SIMD2<Float>(8.0 * tu, 2.5 * tu)),
                    (SIMD2<Float>(7.0 * tu, 3.0 * tu), SIMD2<Float>(8.0 * tu, 3.0 * tu)))
        }
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// SegmentStripeMesh - mesh that generates a triangle strip along a path of points, with a width
//

class SegmentStripMesh: Mesh {
    var points: [SIMD2<Float>]
    var width: Float
    var color: SegmentColor
    
    init(device: MTLDevice, points: [SIMD2<Float>], width: Float, color: SegmentColor) {
        self.points = points
        self.width = width
        self.color = color
        
        let (firstTexCoords, middleTexCoords, lastTexCoords) = color.textureCoordinates
        
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        // Calculate additional start and end points
        let firstPoint = points.first!
        let secondPoint = points[1]
        let lastPoint = points.last!
        let secondLastPoint = points[points.count - 2]
        
        let startDir = normalize(secondPoint - firstPoint)
        let startPerp = SIMD2<Float>(-startDir.y, startDir.x) * width
        let startPoint = firstPoint - startDir * width
        
        let endDir = normalize(lastPoint - secondLastPoint)
        let endPerp = SIMD2<Float>(-endDir.y, endDir.x) * width
        let endPoint = lastPoint + endDir * width
        
        // Add vertices for the additional start point
        vertices.append(contentsOf: [(startPoint + startPerp).x, (startPoint + startPerp).y, 0, firstTexCoords.start.x, firstTexCoords.start.y])
        vertices.append(contentsOf: [(startPoint - startPerp).x, (startPoint - startPerp).y, 0, firstTexCoords.end.x, firstTexCoords.start.y])
        indices.append(UInt16(vertices.count / 5 - 2))
        indices.append(UInt16(vertices.count / 5 - 1))
        
        for i in 0..<points.count {
            let currentPoint = points[i]
            
            if i == 0 {
                // First user point
                let nextPoint = points[i + 1]
                let dir = normalize(nextPoint - currentPoint)
                let perp = SIMD2<Float>(-dir.y, dir.x) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            } else if i == points.count - 1 {
                // Last user point
                let previousPoint = points[i - 1]
                let dir = normalize(currentPoint - previousPoint)
                let perp = SIMD2<Float>(-dir.y, dir.x) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            } else {
                // Middle user points
                let previousPoint = points[i - 1]
                let dir = normalize(currentPoint - previousPoint)
                var perp = SIMD2<Float>(-dir.y, dir.x)
                
                let nextPoint = points[i + 1]
                let nextDir = normalize(nextPoint - currentPoint)
                let nextPerp = SIMD2<Float>(-nextDir.y, nextDir.x)
                perp = normalize(perp + nextPerp) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            }
        }
        
        // Add vertices for the additional end point
        vertices.append(contentsOf: [(endPoint + endPerp).x, (endPoint + endPerp).y, 0, lastTexCoords.start.x, lastTexCoords.end.y])
        vertices.append(contentsOf: [(endPoint - endPerp).x, (endPoint - endPerp).y, 0, lastTexCoords.end.x, lastTexCoords.end.y])
        indices.append(UInt16(vertices.count / 5 - 2))
        indices.append(UInt16(vertices.count / 5 - 1))
        
        super.init(device: device, vertices: vertices, indices: indices, primitiveType: .triangleStrip)
    }
    
    func remakeVertices() {
        let (firstTexCoords, middleTexCoords, lastTexCoords) = color.textureCoordinates

        var vertices: [Float] = []
        var indices: [UInt16] = []

        // Calculate additional start and end points
        let firstPoint = points.first!
        let secondPoint = points[1]
        let lastPoint = points.last!
        let secondLastPoint = points[points.count - 2]
        
        let startDir = normalize(secondPoint - firstPoint)
        let startPerp = SIMD2<Float>(-startDir.y, startDir.x) * width
        let startPoint = firstPoint - startDir * width
        
        let endDir = normalize(lastPoint - secondLastPoint)
        let endPerp = SIMD2<Float>(-endDir.y, endDir.x) * width
        let endPoint = lastPoint + endDir * width
        
        // Add vertices for the additional start point
        vertices.append(contentsOf: [(startPoint + startPerp).x, (startPoint + startPerp).y, 0, firstTexCoords.start.x, firstTexCoords.start.y])
        vertices.append(contentsOf: [(startPoint - startPerp).x, (startPoint - startPerp).y, 0, firstTexCoords.end.x, firstTexCoords.start.y])
        indices.append(UInt16(vertices.count / 5 - 2))
        indices.append(UInt16(vertices.count / 5 - 1))
        
        for i in 0..<points.count {
            let currentPoint = points[i]
            
            if i == 0 {
                // First user point
                let nextPoint = points[i + 1]
                let dir = normalize(nextPoint - currentPoint)
                let perp = SIMD2<Float>(-dir.y, dir.x) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            } else if i == points.count - 1 {
                // Last user point
                let previousPoint = points[i - 1]
                let dir = normalize(currentPoint - previousPoint)
                let perp = SIMD2<Float>(-dir.y, dir.x) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            } else {
                // Middle user points
                let previousPoint = points[i - 1]
                let dir = normalize(currentPoint - previousPoint)
                var perp = SIMD2<Float>(-dir.y, dir.x)
                
                let nextPoint = points[i + 1]
                let nextDir = normalize(nextPoint - currentPoint)
                let nextPerp = SIMD2<Float>(-nextDir.y, nextDir.x)
                perp = normalize(perp + nextPerp) * width
                
                let v0 = currentPoint + perp
                let v1 = currentPoint - perp
                
                vertices.append(contentsOf: [v0.x, v0.y, 0, middleTexCoords.start.x, middleTexCoords.end.y])
                vertices.append(contentsOf: [v1.x, v1.y, 0, middleTexCoords.end.x, middleTexCoords.end.y])
                
                indices.append(UInt16(vertices.count / 5 - 2))
                indices.append(UInt16(vertices.count / 5 - 1))
            }
        }
        
        // Add vertices for the additional end point
        vertices.append(contentsOf: [(endPoint + endPerp).x, (endPoint + endPerp).y, 0, lastTexCoords.start.x, lastTexCoords.end.y])
        vertices.append(contentsOf: [(endPoint - endPerp).x, (endPoint - endPerp).y, 0, lastTexCoords.end.x, lastTexCoords.end.y])
        indices.append(UInt16(vertices.count / 5 - 2))
        indices.append(UInt16(vertices.count / 5 - 1))
        
        updateBuffers(vertices: vertices, indices: indices)
    }
}

