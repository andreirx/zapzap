//
//  Meshes.swift
//  ZapZap
//
//  Created by apple on 26.07.2024.
//

import Foundation
import Metal
import simd

// // // // // // // // // // // // // // // // // // // // //
//
// PerInstanceUniforms - pass model / instance constants to the shaders
//

struct PerInstanceUniforms {
    var modelMatrix: matrix_float4x4
    var alphaUniform: Float
}

// // // // // // // // // // // // // // // // // // // // //
//
// Mesh - base class for various mesh types
//

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
    var alpha: Float = 0.9 { // Alpha value that controls transparency or brightness
        didSet { updateModelMatrix() }
    }

    init(vertices: [Float], indices: [UInt16]?, primitiveType: MTLPrimitiveType) {
        self.primitiveType = primitiveType
        self.vertexBuffer = Renderer.device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * vertices.count, options: [])
        self.vertexCount = vertices.count / 5
        
        if let indices = indices {
            self.indexBuffer = Renderer.device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: [])
            self.indexCount = indices.count
        }
        
        self.perInstanceUniform = PerInstanceUniforms(modelMatrix: matrix_identity_float4x4, alphaUniform: alpha)
        self.uniformBuffer = Renderer.device.makeBuffer(length: MemoryLayout<PerInstanceUniforms>.stride, options: .storageModeShared)
        updateModelMatrix()
    }
    
    func updateBuffers(vertices: [Float], indices: [UInt16]) {
        vertexBuffer?.contents().copyMemory(from: vertices, byteCount: vertices.count * MemoryLayout<Float>.size)
        indexBuffer?.contents().copyMemory(from: indices, byteCount: indices.count * MemoryLayout<UInt16>.size)
    }

    func updateModelMatrix() {
        let translationMatrix = matrix4x4_translation(position.x, position.y, 0)
        let rotationMatrix = matrix4x4_rotation_z(rotation)
        let scaleMatrix = matrix4x4_scale(scale, scale, scale)
        perInstanceUniform.modelMatrix = translationMatrix * rotationMatrix * scaleMatrix
        perInstanceUniform.alphaUniform = alpha // Set the alpha value
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
        
        // Set the vertex buffer for the vertex stage
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set the uniform buffer for the vertex stage
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        
        // Also bind the uniform buffer to the fragment stage
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 3)

        if let indexBuffer = indexBuffer, indexCount > 0 {
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else {
            encoder.drawPrimitives(type: primitiveType, vertexStart: 0, vertexCount: vertexCount)
        }
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// QuadMesh - simple RECTANGULAR sprite
//

class QuadMesh: Mesh {
    init(size: Float, topLeftUV: SIMD2<Float>, bottomRightUV: SIMD2<Float>) {
        let halfSize = size / 2.0
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -halfSize, -halfSize, 0, topLeftUV.x, 1.0 - topLeftUV.y,
             halfSize, -halfSize, 0, bottomRightUV.x, 1.0 - topLeftUV.y,
             halfSize,  halfSize, 0, bottomRightUV.x, 1.0 - bottomRightUV.y,
            -halfSize,  halfSize, 0, topLeftUV.x, 1.0 - bottomRightUV.y
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        super.init(vertices: vertices, indices: indices, primitiveType: .triangle)
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// AnimQuadMesh - simple RECTANGULAR sprite with animated texture position
//


class AnimQuadMesh: Mesh, Animation {
    private var elapsedTime: TimeInterval = 0
    private var textureX: Float
    private var textureY: Float
    private var direction: Float = 1.0 // 1.0 for up, -1.0 for down
    private var frameDuration: TimeInterval = 1 / 60.0 // Assuming 60 FPS update rate
    var isAnimating = false
    private var halfSize: Float

    var tilePosition: (x: Int, y: Int) = (0, 0) // Dummy position as it's not used

    var isFinished: Bool {
        return !isAnimating
    }

    init(size: Float) {
//        isAnimating
        // Initialize textureX randomly
        self.textureX = Float(Int.random(in: 0..<16)) / 16.0
        self.textureY = Float(Int.random(in: 0..<16)) / 16.0 // Start from the darkest
        
        self.halfSize = size / 2.0
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -halfSize, -halfSize, 0, textureX, 1.0 - textureY,
             halfSize, -halfSize, 0, textureX + 1.0 / 16.0, 1.0 - textureY,
             halfSize,  halfSize, 0, textureX + 1.0 / 16.0, 1.0 - (textureY + 1.0 / 16.0),
            -halfSize,  halfSize, 0, textureX, 1.0 - (textureY + 1.0 / 16.0)
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        super.init(vertices: vertices, indices: indices, primitiveType: .triangle)
    }

    func update() {
        guard isAnimating else { return }
        
        elapsedTime += frameDuration

        // Update the textureY coordinate
        textureY += direction * (1.0 / 16.0) // 60.0 // Increment by one step per frame

        // Check if we reached the top or bottom
        if textureY >= 1.0 || textureY <= 0.0 {
            direction *= -1.0 // Reverse the direction
        }

        // If we reached back to the dark position, stop animating
        if textureY <= 0.0 {
            isAnimating = false
        }

        // Update vertices with the new texture coordinates
        updateVertices()
    }

    private func updateVertices() {
        //let halfSize = (self.vertexBuffer!.length / MemoryLayout<Float>.stride) / 5
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -halfSize, -halfSize, 0, textureX, 1.0 - textureY,
             halfSize, -halfSize, 0, textureX + 1.0 / 16.0, 1.0 - textureY,
             halfSize,  halfSize, 0, textureX + 1.0 / 16.0, 1.0 - (textureY + 1.0 / 16.0),
            -halfSize,  halfSize, 0, textureX, 1.0 - (textureY + 1.0 / 16.0)
        ]
        self.updateBuffers(vertices: vertices, indices: [0, 1, 2, 2, 3, 0])
    }

    func cleanup() {
        // Reset animation state if necessary
        isAnimating = false
        elapsedTime = 0
        textureY = 0.0
        direction = 1.0
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// TextQuadMesh - generate text into texture and make a QuadMesh out of it
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import MetalKit

class TextQuadMesh: Mesh {
    var texture: MTLTexture?
    
    init(text: String, font: Font, color: Color, size: CGSize) {
        let textImage = TextQuadMesh.createTextImage(text: text, font: font, color: color, size: size)
        guard let texture = TextQuadMesh.createTextureFromImage(image: textImage) else {
            fatalError("Failed to create texture from text image")
        }
        self.texture = texture
        let vertices: [Float] = [
            // Position          // Texture Coordinates
            -Float(size.width / 2), -Float(size.height / 2), 0, 0.0, 0.0,
             Float(size.width / 2), -Float(size.height / 2), 0, 1.0, 0.0,
             Float(size.width / 2),  Float(size.height / 2), 0, 1.0, 1.0,
             -Float(size.width / 2),  Float(size.height / 2), 0, 0.0, 1.0
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        super.init(vertices: vertices, indices: indices, primitiveType: .triangle)
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        updateModelMatrix()
        
        guard let vertexBuffer = vertexBuffer else { return }
        guard let uniformBuffer = uniformBuffer else { return }
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        if let indexBuffer = indexBuffer, indexCount > 0 {
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else {
            encoder.drawPrimitives(type: primitiveType, vertexStart: 0, vertexCount: vertexCount)
        }
    }
    
    private static func createTextImage(text: String, font: Font, color: Color, size: CGSize) -> Image {
#if os(iOS)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let rect = CGRect(origin: .zero, size: size)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        text.draw(in: rect, withAttributes: attributes)
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            fatalError("Failed to generate text image")
        }
        return image
#elseif os(macOS)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let rect = CGRect(origin: .zero, size: size)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        (text as NSString).draw(in: rect, withAttributes: attributes)
        
        image.unlockFocus()
        return image
#endif
    }
    
    private static func createTextureFromImage(image: Image) -> MTLTexture? {
#if os(iOS)
        guard let cgImage = image.cgImage else { return nil }
#elseif os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
#endif
        
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rawData = calloc(height * width * 4, MemoryLayout<UInt8>.size)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        let context = CGContext(data: rawData,
                                width: width,
                                height: height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let pixelData = context?.data
        let rawPointer = pixelData!.bindMemory(to: UInt8.self, capacity: height * width * 4)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                         width: width,
                                                                         height: height,
                                                                         mipmapped: false)
        textureDescriptor.usage = .shaderRead
        let texture = Renderer.device.makeTexture(descriptor: textureDescriptor)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture?.replace(region: region, mipmapLevel: 0, withBytes: rawPointer, bytesPerRow: bytesPerRow)
        
        free(rawData)
        
        return texture
    }
    
    func updateText(text: String, font: Font, color: Color, size: CGSize) {
        let textImage = TextQuadMesh.createTextImage(text: text, font: font, color: color, size: size)
        guard let newTexture = TextQuadMesh.createTextureFromImage(image: textImage) else {
            fatalError("Failed to create texture from text image")
        }
        self.texture = newTexture
    }
}

#if os(iOS)
typealias Font = UIFont
typealias Color = UIColor
typealias Image = UIImage
#elseif os(macOS)
typealias Font = NSFont
typealias Color = NSColor
typealias Image = NSImage
#endif

// // // // // // // // // // // // // // // // // // // // //
//
// helper functions
//

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
