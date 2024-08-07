//
//  GraphicsLayer.swift
//  ZapZap
//
//  Created by apple on 19.07.2024.
//

import Foundation
import MetalKit

import Metal

class VertexDescriptor {
    static let shared: MTLVertexDescriptor = {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 5
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        return vertexDescriptor
    }()
}


// // // // // // // // // // // // // // // // // // // // //
//
// GraphicsLayer - class with a texture that holds multiple meshes
//


class GraphicsLayer {
    var device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var texture: MTLTexture?
    var meshes: [Mesh] = []
    
    init() {
        self.device = Renderer.device
//        print("GraphicsLayer init: will create pipeline")
        setupPipeline(vertexFunctionName: "vertex_main", fragmentFunctionName: "sprite_fragment_main")
    }
    
    func setupPipeline(vertexFunctionName: String, fragmentFunctionName: String, pixelFormat: MTLPixelFormat = .rgba16Float) {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create default library")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            print("Failed to create vertex function: \(vertexFunctionName)")
            return
        }
        
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            print("Failed to create fragment function: \(fragmentFunctionName)")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexDescriptor = VertexDescriptor.shared
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
//            print("Created pipeline state for simple alpha blending")
        } catch let error {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    func render(encoder: MTLRenderCommandEncoder) {
        guard let pipelineState = pipelineState else { return }
        encoder.setRenderPipelineState(pipelineState)
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        for (index, mesh) in meshes.enumerated() {
            mesh.draw(encoder: encoder)
        }
    }
    
    func loadTexture(imageName: String) {
        do {
            self.texture = try Renderer.loadTexture(textureName: imageName)
        } catch {
            print("Failed to load texture: \(error)")
        }
    }
}

class GameBoardLayer: GraphicsLayer {
    var gameMgr: GameManager
    
    init(gameManager: GameManager) {
        self.gameMgr = gameManager
        super.init()
    }
    
    override func render(encoder: MTLRenderCommandEncoder) {
        guard let pipelineState = pipelineState else { return }
        encoder.setRenderPipelineState(pipelineState)
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        for row in gameMgr.tileQuads {
            for quad in row {
                guard let mesh = quad else { continue }
                mesh.draw(encoder: encoder)
            }
        }
    }
}

// // // // // // // // // // // // // // // // // // // // //
//
// EffectsLayer - additive layer conceived for making EDR effects that stand out
//

class EffectsLayer: GraphicsLayer {
    override init() {
        super.init()
//        print("EffectsLayer init: will create pipeline")
        setupAdditivePipeline(vertexFunctionName: "vertex_main", fragmentFunctionName: "additive_fragment_main")
    }
    
    func setupAdditivePipeline(vertexFunctionName: String, fragmentFunctionName: String, pixelFormat: MTLPixelFormat = .rgba16Float) {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create default library for effects layer")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            print("Failed to create vertex function: \(vertexFunctionName) for effects layer")
            return
        }
        
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            print("Failed to create fragment function: \(fragmentFunctionName) for effects layer")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexDescriptor = VertexDescriptor.shared
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
//            print("Created pipeline state for additive EDR effects")
        } catch let error {
            print("Failed to create additive pipeline state: \(error)")
        }
    }
    
    override func render(encoder: MTLRenderCommandEncoder) {
        guard let pipelineState = pipelineState else { return }
        encoder.setRenderPipelineState(pipelineState)
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        for (index, mesh) in meshes.enumerated() {
            if let arcMesh = mesh as? ElectricArcMesh {
                arcMesh.twitch(byFactor: 0.05)
            }
            mesh.draw(encoder: encoder)
        }
    }

    func generateParticles(position: SIMD2<Float>, speedLimit: Float, width: Float, count: Int) {
        // Generate particles
        var particles = Particle.generate(count: count, speedLimit: speedLimit, width: width)
        
        // Set initial position for all particles
        for particle in particles {
            particle.position = position
        }
        
        // Add particles to effectsLayer
        meshes.append(contentsOf: particles)
    }
    
    func removeAllParticles() {
        meshes.removeAll { $0 is Particle }
    }
    
}
