//
//  Renderer.swift
//  ZapZap Shared
//
//  Created by apple on 19.07.2024.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3
let MaxOutstandingFrameCount = 3

class Renderer: NSObject, MTKViewDelegate {
    var gameMgr: GameManager
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    var samplerState: MTLSamplerState?
    
    var baseLayer: GraphicsLayer!
    var objectsLayer: GraphicsLayer!
    var textLayer: GraphicsLayer!
    var effectsLayer: EffectsLayer!
    
    private var constantBuffer: MTLBuffer!
    private let constantsSize: Int
    private let constantsStride: Int
    private var currentConstantBufferOffset: Int
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var modelViewMatrix: matrix_float4x4 = matrix_float4x4()

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    private var frameIndex: Int = 0
        
    init?(metalKitView: MTKView, gameManager: GameManager) {
        self.gameMgr = gameManager
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.view = metalKitView
        self.view.device = device
        self.view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)

        metalKitView.colorPixelFormat = .rgba16Float
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

        self.constantsSize = MemoryLayout<Uniforms>.size
        self.constantsStride = align(self.constantsSize, upTo: 256)
        self.currentConstantBufferOffset = 0
        self.frameIndex = 0
        let constantBufferSize = self.constantsStride * maxBuffersInFlight
        self.constantBuffer = device.makeBuffer(length: constantBufferSize, options: .storageModeShared)
        self.constantBuffer.label = "Dynamic Constant Buffer"
        print("Renderer init created constant buffer")

        super.init()
        self.view.delegate = self

        baseLayer = GraphicsLayer(device: device)
        objectsLayer = GraphicsLayer(device: device)
        textLayer = GraphicsLayer(device: device)
        effectsLayer = EffectsLayer(device: device)
        
        do {
            baseLayer.texture = try Renderer.loadTexture(device: device, textureName: "base_tiles")
            objectsLayer.texture = try Renderer.loadTexture(device: device, textureName: "arrows")
            effectsLayer.texture = try Renderer.loadTexture(device: device, textureName: "arrows")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }
        
        let quadMesh1 = QuadMesh(device: device, size: 100000, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))
        let quadMesh2 = QuadMesh(device: device, size: 60000, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))
        let quadMesh3 = QuadMesh(device: device, size: 30000, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))
        
        baseLayer.meshes.append(quadMesh1)
        objectsLayer.meshes.append(quadMesh2)
        effectsLayer.meshes.append(quadMesh3)
    }
    
    class func loadTexture(device: MTLDevice, textureName: String) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]
        return try textureLoader.newTexture(name: textureName, scaleFactor: 1.0, bundle: nil, options: textureLoaderOptions)
    }
    
    private func updateConstants() {
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let canvasWidth: Float = (aspectRatio < 1) ? 500 : 500 * aspectRatio
        let canvasHeight = (aspectRatio < 1) ? canvasWidth / aspectRatio : canvasWidth / aspectRatio
        let projectionMatrix = simd_float4x4(orthographicProjectionWithLeft: -canvasWidth / 2,
                                             top: canvasHeight / 2,
                                             right: canvasWidth / 2,
                                             bottom: -canvasHeight / 2,
                                             near: 0.0,
                                             far: 1.0)

        var transformMatrix = projectionMatrix

        currentConstantBufferOffset = (frameIndex % MaxOutstandingFrameCount) * constantsStride
        let constants = constantBuffer.contents().advanced(by: currentConstantBufferOffset)
        constants.copyMemory(from: &transformMatrix, byteCount: constantsSize)
        print("update constants copied memory from transform matrix")
    }
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        currentConstantBufferOffset = (frameIndex % maxBuffersInFlight) * constantsStride
        updateConstants()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("renderer draw makeCommandBuffer, renderPassDescriptor, or renderEncoder FAILED")
            return
        }
        
        renderEncoder.label = "Primary Render Encoder"
        renderEncoder.pushDebugGroup("Draw Layers")
        renderEncoder.setVertexBuffer(constantBuffer, offset: currentConstantBufferOffset, index: 2)
        print("render encoder set constants")

        if let samplerState = samplerState {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            print("render encoder set sampler state")
        }
        
        renderEncoder.setFrontFacing(.counterClockwise)
        print("render encoder set front facing")

        baseLayer.render(encoder: renderEncoder)
        objectsLayer.render(encoder: renderEncoder)
        textLayer.render(encoder: renderEncoder)
        effectsLayer.render(encoder: renderEncoder)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        commandBuffer.commit()
        frameIndex += 1
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)
        modelViewMatrix = matrix4x4_translation(0, 0, -2)
        print("view size has changed: ", size.width, size.height, " and aspect: ", aspect)
    }
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * nearZ, 0)
    ))
}

func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

