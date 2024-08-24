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


// // // // // // // // // // // // // // // // // // // // //
//
// ResourceTextures - class for managing textures
//

class ResourceTextures {
    private var textures: [String: MTLTexture] = [:]
    private let textureLoader: MTKTextureLoader
    
    init(device: MTLDevice, textureNames: [String]) {
        self.textureLoader = MTKTextureLoader(device: device)
        loadTextures(textureNames: textureNames)
    }
    
    private func loadTextures(textureNames: [String]) {
        let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]
        
        for name in textureNames {
            do {
                let texture = try textureLoader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: textureLoaderOptions)
                textures[name] = texture
                print("Loaded texture: \(name)")
            } catch {
                print("Failed to load texture: \(name). Error: \(error)")
            }
        }
    }
    
    func getTexture(named name: String) -> MTLTexture? {
        return textures[name]
    }
}


// // // // // // // // // // // // // // // // // // // // //
//
// Renderer - the class that will draw everything
//

class Renderer: NSObject, MTKViewDelegate {
    var gameMgr: GameManager
    static var device: MTLDevice!
    let commandQueue: MTLCommandQueue
    let view: MTKView
    var samplerState: MTLSamplerState?

    static var textures: ResourceTextures!
    
    var logoScreen: Screen!
    var titleScreen: Screen!
    var mainMenuScreen: Screen!
    var gameScreen: Screen!
    var pauseScreen: Screen!
    
    var currentScreen: Screen?

    var backgroundLayer: GraphicsLayer!
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
        guard let device = Renderer.device else {
            print("Renderer init... No device to render on...")
            return nil
        }
        self.gameMgr = gameManager
        guard let queue = device.makeCommandQueue() else { return nil }
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
        
        let logoTexture = ["companylogo"]
        let tempTexture = ResourceTextures(device: Renderer.device, textureNames: logoTexture)
/*
        let textureNames = ["arrows", "base_tiles", "stars"]
        Renderer.textures = ResourceTextures(device: Renderer.device, textureNames: textureNames)
*/
        self.currentConstantBufferOffset = 0
        self.frameIndex = 0
        let constantBufferSize = Renderer.constantsStride * maxBuffersInFlight
        self.constantBuffer = device.makeBuffer(length: constantBufferSize, options: .storageModeShared)
        self.constantBuffer.label = "Dynamic Constant Buffer"
        print("Renderer init created constant buffer")

        super.init()
        self.view.delegate = self

        logoScreen = Screen()
        titleScreen = Screen()
        mainMenuScreen = Screen()
        gameScreen = Screen()
        pauseScreen = Screen()

        // Setup logo screen
        setupLogoScreen()
        
        // Set logo screen as the initial screen
        setCurrentScreen(logoScreen)
    }
    
    private func setupLogoScreen() {
        let logoTexture = ["companylogo"]
        let logoTextures = ResourceTextures(device: Renderer.device, textureNames: logoTexture)
        
        let logoQuad = QuadMesh(size: boardH / 1.1, topLeftUV: SIMD2<Float>(0, 0), bottomRightUV: SIMD2<Float>(1, 1))
        logoQuad.position = SIMD2<Float>(0, 0)
        
        let logoLayer = GraphicsLayer()
        logoLayer.texture = logoTextures.getTexture(named: "companylogo")
        logoLayer.meshes.append(logoQuad)
        
        logoScreen.addLayer(logoLayer)
    }

    func createBaseLayer(fromGameManager: GameManager) {
        gameMgr = fromGameManager
        baseLayer = GameBoardLayer(gameManager: fromGameManager)
        baseLayer?.texture = Renderer.textures.getTexture(named: "base_tiles")

        if textLayer != nil {
            // Example of adding a text quad
            textLayer.meshes.append(gameMgr.scoreLeftMesh!)
            textLayer.meshes.append(gameMgr.scoreRightMesh!)
        }

        // Call checkConnections and recreate connections
        gameMgr.gameBoard?.checkConnections()

        // remake all electric arcs according to their markers
        gameMgr.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameMgr.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        gameMgr.remakeElectricArcs(forMarker: .ok, withColor: .skyBlue, po2: 3, andWidth: 8.0)
        
        // add layers to game screen
        gameScreen.addLayer(backgroundLayer)
        gameScreen.addLayer(baseLayer!)
        gameScreen.addLayer(effectsLayer)
        gameScreen.addLayer(textLayer)
        gameScreen.addLayer(objectsLayer)
    }
    
    func initializeGameScreen() {
        let textureNames = ["arrows", "base_tiles", "stars"]
        Renderer.textures = ResourceTextures(device: Renderer.device, textureNames: textureNames)
        
        // Set up layers and initialize game screen
        backgroundLayer = GraphicsLayer()
        objectsLayer = GraphicsLayer()
        effectsLayer = EffectsLayer()
        textLayer = GraphicsLayer()

        gameMgr.createTiles()
//        createBaseLayer(fromGameManager: gameMgr)

//        createBackgroundLayer()
        
        backgroundLayer.texture = Renderer.textures.getTexture(named: "stars")
        objectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        effectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        
        createBaseLayer(fromGameManager: gameMgr)
    }

    func setCurrentScreen(_ screen: Screen) {
        currentScreen = screen
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
    
    func update() {
        // logo screen updates
        if currentScreen === logoScreen {
            // Update elapsed time
            let elapsedTime = Float(frameIndex) / 60.0 // Assuming 60 FPS
            
            if frameIndex == 5 { // at exactly frame 5
                print ("this is frame 5")
                initializeGameScreen()
            }

            if let logoQuad = logoScreen.layers.first?.meshes.first as? QuadMesh {
                if elapsedTime <= 0.5 {
                    logoQuad.alpha = elapsedTime * 2.0
                } else if elapsedTime <= 1.5 {
                    logoQuad.alpha = 1.0
                } else {
                    logoQuad.alpha = (2.0 - elapsedTime) * 6.0
                }
            }
            if elapsedTime >= 2.0 {
                // Proceed to load textures and initialize other screens
                setCurrentScreen(gameScreen)
            }
        }

        if currentScreen === gameScreen {
            gameMgr.update()
            // update the GameObjects in the objectLayer
            if objectsLayer != nil {
                for mesh in objectsLayer.meshes {
                    if let gameObject = mesh as? GameObject {
                        gameObject.update()
                    }
                }
            }
        }
    }

    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        currentConstantBufferOffset = (frameIndex % maxBuffersInFlight) * Renderer.constantsStride
        updateConstants()
        update()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("renderer draw makeCommandBuffer, renderPassDescriptor, or renderEncoder FAILED")
            return
        }
        
        renderEncoder.label = "Primary Render Encoder"

        if let samplerState = samplerState {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }
        
        renderEncoder.setFrontFacing(.counterClockwise)
        let constants = constantBuffer.contents().advanced(by: currentConstantBufferOffset)
        renderEncoder.setVertexBuffer(constantBuffer, offset: currentConstantBufferOffset, index: 2)

        currentScreen?.render(encoder: renderEncoder)

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

