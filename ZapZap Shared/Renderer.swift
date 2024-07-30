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
let alignedUniformsSize = (MemoryLayout<matrix_float4x4>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3
let MaxOutstandingFrameCount = 3

class Renderer: NSObject, MTKViewDelegate {
    var gameMgr: GameManager
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    var samplerState: MTLSamplerState?
    
    var baseLayer: GameBoardLayer? // this one won't be ready at creation time, will have to add it later after getting a GameManager
    var objectsLayer: GraphicsLayer!
    var textLayer: GraphicsLayer!
    var effectsLayer: EffectsLayer!
    
    private var constantBuffer: MTLBuffer!
    static let constantsSize: Int = MemoryLayout<matrix_float4x4>.size
    static let constantsStride: Int = align(constantsSize, upTo: 256)
    private var currentConstantBufferOffset: Int
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var modelMatrix: matrix_float4x4 = matrix_float4x4()

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

//        self.constantsSize = MemoryLayout<Uniforms>.size
//        self.constantsStride = align(self.constantsSize, upTo: 256)
        self.currentConstantBufferOffset = 0
        self.frameIndex = 0
        let constantBufferSize = Renderer.constantsStride * maxBuffersInFlight
        self.constantBuffer = device.makeBuffer(length: constantBufferSize, options: .storageModeShared)
        self.constantBuffer.label = "Dynamic Constant Buffer"
        print("Renderer init created constant buffer")

        super.init()
        self.view.delegate = self

        // must have the tilequads already initialized in gameManager before creating the renderer!
        
        objectsLayer = GraphicsLayer(device: device)
        textLayer = GraphicsLayer(device: device)
        effectsLayer = EffectsLayer(device: device)
        
        do {
            objectsLayer.texture = try Renderer.loadTexture(device: device, textureName: "arrows")
            print ("created objects layer texture")
            effectsLayer.texture = try Renderer.loadTexture(device: device, textureName: "arrows")
            print ("created effects layer texture")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }
        
//        let quadMesh2 = QuadMesh(device: device, size: 600, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))
//        let quadMesh3 = QuadMesh(device: device, size: 300, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))

//        objectsLayer.meshes.append(quadMesh2)
//        effectsLayer.meshes.append(quadMesh3)
    }
    
    func createBaseLayer(fromGameManager: GameManager) {
        gameMgr = fromGameManager
        baseLayer = GameBoardLayer(device: device, gameManager: fromGameManager)
        do {
            baseLayer!.texture = try Renderer.loadTexture(device: device, textureName: "base_tiles")
            print ("created base layer texture")
        } catch {
            print("Unable to load base layer texture. Error info: \(error)")
        }

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
        // viewport aspect ratio
        let screenAspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        // model space width and height needed to fit to the viewport
        let needW = needW / 2.0
        let needH = needH / 2.0
        let modelAspectRatio = needW / needH
        // pixels to model space units ratios - will fit to the smallest one
        let horizRatio = Float(view.drawableSize.width) / needW
        let vertRatio = Float(view.drawableSize.height) / needH
        // let's think this throug
        // - if horizRatio and vertRatio were EQUAL -> it means the viewport is perfectly fit to display them as it is
        // - if horizRatio is the SMALLER one, it means horizontally it's the correct screen to model ratio
        var canvasWidth: Float
        var canvasHeight: Float
        if (horizRatio < vertRatio) {
            canvasWidth = needW
            canvasHeight = needH * modelAspectRatio / screenAspectRatio
        } else {
            canvasWidth = needW * screenAspectRatio / modelAspectRatio
            canvasHeight = needH
        }

        let projectionMatrix = simd_float4x4(orthographicProjectionWithLeft: -canvasWidth,
                                             top: -canvasHeight,
                                             right: canvasWidth,
                                             bottom: canvasHeight,
                                             near: 0.0,
                                             far: 1.0)
        var transformMatrix = projectionMatrix

        currentConstantBufferOffset = (frameIndex % MaxOutstandingFrameCount) * Renderer.constantsStride
        let constants = constantBuffer.contents().advanced(by: currentConstantBufferOffset)
        constants.copyMemory(from: &transformMatrix, byteCount: Renderer.constantsSize)
    }
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        currentConstantBufferOffset = (frameIndex % maxBuffersInFlight) * Renderer.constantsStride
        updateConstants()
        gameMgr.update()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("renderer draw makeCommandBuffer, renderPassDescriptor, or renderEncoder FAILED")
            return
        }
        
        renderEncoder.label = "Primary Render Encoder"
//        renderEncoder.pushDebugGroup("Draw Layers")
//        renderEncoder.setVertexBuffer(constantBuffer, offset: currentConstantBufferOffset, index: 2)

        if let samplerState = samplerState {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }
        
        renderEncoder.setFrontFacing(.counterClockwise)
        let constants = constantBuffer.contents().advanced(by: currentConstantBufferOffset)
        renderEncoder.setVertexBuffer(constantBuffer, offset: currentConstantBufferOffset, index: 2)

        baseLayer!.render(encoder: renderEncoder)
        objectsLayer.render(encoder: renderEncoder)
        textLayer.render(encoder: renderEncoder)
        effectsLayer.render(encoder: renderEncoder)

//        renderEncoder.popDebugGroup()
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
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(0), aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)
        modelMatrix = matrix4x4_translation(0, 0, -1)
//        print("view size has changed: ", size.width, size.height, " and aspect: ", aspect)
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

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

