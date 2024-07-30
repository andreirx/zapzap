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
            -halfSize, -halfSize, 0, topLeftUV.x, 1.0 - bottomRightUV.y,
             halfSize, -halfSize, 0, bottomRightUV.x, 1.0 - bottomRightUV.y,
             halfSize,  halfSize, 0, bottomRightUV.x, 1.0 - topLeftUV.y,
            -halfSize,  halfSize, 0, topLeftUV.x, 1.0 - topLeftUV.y
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        super.init(device: device, vertices: vertices, indices: indices, primitiveType: .triangle)
    }
}

class IndexedMesh: Mesh {
    init(device: MTLDevice, vertices: [Float], indices: [UInt16]) {
        super.init(device: device, vertices: vertices, indices: indices, primitiveType: .triangle)
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
