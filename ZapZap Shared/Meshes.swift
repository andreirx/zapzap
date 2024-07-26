//
//  Meshes.swift
//  ZapZap
//
//  Created by apple on 26.07.2024.
//

import Foundation
import Metal

class Mesh {
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    var vertexCount: Int = 0
    var indexCount: Int = 0
    var primitiveType: MTLPrimitiveType
    
    init(device: MTLDevice, vertices: [Float], indices: [UInt16]?, primitiveType: MTLPrimitiveType) {
        self.primitiveType = primitiveType
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * vertices.count, options: [])
        self.vertexCount = vertices.count / 5
        
        if let indices = indices {
            self.indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: [])
            self.indexCount = indices.count
        }
    }
}

class QuadMesh: Mesh {
    init(device: MTLDevice, size: Float, topLeftUV: SIMD2<Float>, bottomRightUV: SIMD2<Float>) {
        let halfSize = size / 2.0
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -halfSize, -halfSize, 0, topLeftUV.x, topLeftUV.y,
             halfSize, -halfSize, 0, bottomRightUV.x, topLeftUV.y,
             halfSize,  halfSize, 0, bottomRightUV.x, bottomRightUV.y,
            -halfSize,  halfSize, 0, topLeftUV.x, bottomRightUV.y
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
