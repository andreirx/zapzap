//
//  GraphicsLayer.swift
//  ZapZap
//
//  Created by apple on 19.07.2024.
//

import Foundation
import MetalKit

class GraphicsLayer {
    var device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var texture: MTLTexture?
    var vertexCount: Int = 0
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func setupPipeline(vertexFunctionName: String, fragmentFunctionName: String, pixelFormat: MTLPixelFormat = .rgba16Float) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: vertexFunctionName),
              let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    func render(encoder: MTLRenderCommandEncoder) {
        guard let pipelineState = pipelineState else { return }
        encoder.setRenderPipelineState(pipelineState)
        if let vertexBuffer = vertexBuffer {
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        }
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }
    
    func setVertexBuffer(vertices: [Float]) {
        vertexCount = vertices.count / 5
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * vertices.count, options: [])
    }
    
    func loadTexture(imageName: String) {
        do {
            self.texture = try Renderer.loadTexture(device: device, textureName: imageName)
        } catch {
            print("Failed to load texture: \(error)")
        }
    }
}

class EffectsLayer: GraphicsLayer {
    
    override init(device: MTLDevice) {
        super.init(device: device)
    }
    
    func setupAdditivePipeline(vertexFunctionName: String, fragmentFunctionName: String, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: vertexFunctionName),
              let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("Failed to create additive pipeline state: \(error)")
        }
    }
}
