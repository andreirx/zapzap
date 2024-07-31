//
//  Meshes.swift
//  ZapZap
//
//  Created by apple on 26.07.2024.
//

import Foundation
import Metal

struct PerInstanceUniforms {
    var modelMatrix: matrix_float4x4
}

class Mesh {
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    var uniformBuffer: MTLBuffer?
    var vertexCount: Int = 0
    var indexCount: Int = 0
    var primitiveType: MTLPrimitiveType
    var perInstanceUniform: PerInstanceUniforms
    var mtlDevice: MTLDevice

    var position: SIMD2<Float> = SIMD2<Float>(0, 0) {
        didSet { updateModelMatrix() }
    }
    var rotation: Float = 0 {
        didSet { updateModelMatrix() }
    }
    var scale: Float = 1 {
        didSet { updateModelMatrix() }
    }
        
    init(device: MTLDevice, vertices: [Float], indices: [UInt16]?, primitiveType: MTLPrimitiveType) {
        self.mtlDevice = device
        self.primitiveType = primitiveType
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * vertices.count, options: [])
        self.vertexCount = vertices.count / 5
        
        if let indices = indices {
            self.indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: [])
            self.indexCount = indices.count
        }
        
        self.perInstanceUniform = PerInstanceUniforms(modelMatrix: matrix_identity_float4x4)
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<PerInstanceUniforms>.size, options: .storageModeShared)
        updateModelMatrix()
    }
    
    func updateBuffers(vertices: [Float], indices: [UInt16]) {
        vertexBuffer?.contents().copyMemory(from: vertices, byteCount: vertices.count * MemoryLayout<Float>.size)
        indexBuffer?.contents().copyMemory(from: indices, byteCount: indices.count * MemoryLayout<UInt16>.size)
    }

    private func updateModelMatrix() {
        let translationMatrix = matrix4x4_translation(position.x, position.y, 0)
        let rotationMatrix = matrix4x4_rotation_z(rotation)
        let scaleMatrix = matrix4x4_scale(scale, scale, scale)
        perInstanceUniform.modelMatrix = translationMatrix * rotationMatrix * scaleMatrix
        let bufferPointer = uniformBuffer?.contents()
        memcpy(bufferPointer, &perInstanceUniform, MemoryLayout<PerInstanceUniforms>.size)
    }
    
    func getModelMatrix() -> matrix_float4x4 {
        return perInstanceUniform.modelMatrix
    }

    func draw(encoder: MTLRenderCommandEncoder) {
        updateModelMatrix()

        guard let vertexBuffer = vertexBuffer else { return }
        guard let uniformBuffer = uniformBuffer else { return }
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        
        if let indexBuffer = indexBuffer, indexCount > 0 {
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else {
            encoder.drawPrimitives(type: primitiveType, vertexStart: 0, vertexCount: vertexCount)
        }
    }
}

class QuadMesh: Mesh {
    init(device: MTLDevice, size: Float, topLeftUV: SIMD2<Float>, bottomRightUV: SIMD2<Float>) {
        let halfSize = size / 2.0
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -halfSize, -halfSize, 0, topLeftUV.x, 1.0 - topLeftUV.y,
             halfSize, -halfSize, 0, bottomRightUV.x, 1.0 - topLeftUV.y,
             halfSize,  halfSize, 0, bottomRightUV.x, 1.0 - bottomRightUV.y,
            -halfSize,  halfSize, 0, topLeftUV.x, 1.0 - bottomRightUV.y
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        super.init(device: device, vertices: vertices, indices: indices, primitiveType: .triangle)
    }
}

import Foundation
import Metal
import simd

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


func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

func matrix4x4_rotation_z(_ radians: Float) -> matrix_float4x4 {
    let cos_r = cos(radians)
    let sin_r = sin(radians)
    return matrix_float4x4(columns: (
        SIMD4<Float>( cos_r, sin_r, 0, 0),
        SIMD4<Float>(-sin_r, cos_r, 0, 0),
        SIMD4<Float>(     0,     0, 1, 0),
        SIMD4<Float>(     0,     0, 0, 1)
    ))
}

func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}
