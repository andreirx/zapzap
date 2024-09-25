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
    var multiMgr: MultiplayerManager

    static var device: MTLDevice!
    let commandQueue: MTLCommandQueue
    let view: MTKView
    var samplerState: MTLSamplerState?
    
#if os(iOS)
    var viewController: UIViewController?
#elseif os(macOS)
    var viewController: NSViewController?
#endif

    static var textures: ResourceTextures!
    
    // screens
    var logoScreen: Screen!
    var titleScreen: Screen!
    var mainMenuScreen: Screen!
    var multiplayerScreen: Screen!
    var gameScreen: Screen!
    var pauseScreen: Screen!
    
    var currentScreen: Screen?

    // buttons
    var buttonLocal: ButtonMesh?
    var button1v1: ButtonMesh?
    var buttonBuyCoffee: ButtonMesh?
    var buttonPause: ButtonMesh?
    var buttonBack: ButtonMesh?
    
    // layers
    var backgroundLayer: GraphicsLayer!
    var menuLayer: GraphicsLayer!
    var mainButtonsLayer: GraphicsLayer!
    var multiplayerButtonsLayer: GraphicsLayer!
    var fingerLayer: GraphicsLayer!
    var baseLayer: GameBoardLayer? // this one won't be ready at creation time, will have to add it later after getting a GameManager
    var objectsLayer: GraphicsLayer!
    var textLayer: GraphicsLayer!
    var effectsLayer: EffectsLayer!
    
    // internal renderer stuff
    private var constantBuffer: MTLBuffer!
    static let constantsSize: Int = MemoryLayout<matrix_float4x4>.size
    static let constantsStride: Int = align(constantsSize, upTo: 256)
    private var currentConstantBufferOffset: Int

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var modelMatrix: matrix_float4x4 = matrix_float4x4()

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var frameIndex: Int = 0

    // init the renderer
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
        
        multiMgr = MultiplayerManager()

        super.init()
        self.view.delegate = self
        self.multiMgr.renderer = self

        logoScreen = Screen()
        titleScreen = Screen()
        mainMenuScreen = Screen()
        multiplayerScreen = Screen()
        gameScreen = Screen()
        pauseScreen = Screen()

        // Setup logo screen
        setupLogoScreen()
        
        // Set logo screen as the initial screen
        setCurrentScreen(logoScreen)
    }
    
    // initialize logo screen separately because we need it immediately
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
    
    // Helper function to update text meshes with inout to modify the passed mesh reference
    static func updateText(mesh: inout TextQuadMesh?, onLayer: GraphicsLayer, withText: String, fontSize: CGFloat, color: Color, size: CGSize) {
        let font = Font.systemFont(ofSize: fontSize)
        
        // Remove the old mesh from the layer if it exists
        if let existingMesh = mesh {
            onLayer.meshes.removeAll { $0 === existingMesh }
        }
        
        // Create a new mesh with the updated text
        let newMesh = TextQuadMesh(text: withText, font: font, color: color, size: size)
        
        // Set position based on the existing mesh (if any)
        if let existingMesh = mesh {
            newMesh.position = existingMesh.position
        }
        
        // Add the new mesh to the layer
        onLayer.meshes.append(newMesh)
        
        // Update the reference to point to the new mesh
        mesh = newMesh
    }

    // this function is important because the game manager needs it to function properly
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
    }
    
    // function does what it says - sets up game screens, with their layers and contents
    func initializeGameScreens() {
        guard let animationManager = gameMgr.animationManager else { return }
        let textureNames = ["arrows", "base_tiles", "stars"]
        Renderer.textures = ResourceTextures(device: Renderer.device, textureNames: textureNames)
        
        // Set up layers and initialize game screen
        backgroundLayer = GraphicsLayer()
        objectsLayer = GraphicsLayer()
        effectsLayer = EffectsLayer()
        textLayer = GraphicsLayer()
        menuLayer = GraphicsLayer()
        mainButtonsLayer = GraphicsLayer()
        multiplayerButtonsLayer = GraphicsLayer()
        fingerLayer = GraphicsLayer()

        gameMgr.createTiles()
//        createBaseLayer(fromGameManager: gameMgr)

//        createBackgroundLayer()
        
        backgroundLayer.texture = Renderer.textures.getTexture(named: "stars")
        objectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        effectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        menuLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        mainButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        multiplayerButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        fingerLayer.texture = Renderer.textures.getTexture(named: "arrows")

        // have the finger on the finger layer
        // remember we created it invisible
        fingerLayer.meshes.append(animationManager.fingerQuad)
        
//        zapGame = ZapGame(gameManager: gameMgr, animationManager: animationManager, renderer: self)
        createBaseLayer(fromGameManager: gameMgr)

        // add layers to game screen
        gameScreen.addLayer(backgroundLayer)
        gameScreen.addLayer(baseLayer!)
        gameScreen.addLayer(effectsLayer)
        gameScreen.addLayer(textLayer)
        gameScreen.addLayer(objectsLayer)
        
        // add layers to menu screen
        mainMenuScreen.addLayer(menuLayer)
        mainMenuScreen.addLayer(mainButtonsLayer)
        mainMenuScreen.addLayer(fingerLayer)
        mainMenuScreen.addLayer(effectsLayer)
//        gameScreen.addLayer(textLayer)
        
        // add layers to multiplayer screen
        multiplayerScreen.addLayer(menuLayer)
        multiplayerScreen.addLayer(multiplayerButtonsLayer)
        multiplayerScreen.addLayer(fingerLayer)
        multiplayerScreen.addLayer(effectsLayer)

        // put some random tiles in there on the menu screen
        for i in stride(from: -boardWidth/2 - 2, through: boardWidth*3/2 + 4, by: 2) {
            for j in stride(from:-2, through: boardHeight+4, by: 2) {
                if j < 1 {
                    menuLayer.meshes.append(gameMgr.createUnrelatedTileQuad(i: i, j: j)!)
                } else {
                    if i < 2 || i > boardWidth {
                        menuLayer.meshes.append(gameMgr.createUnrelatedTileQuad(i: i, j: j)!)
                    }
                }
            }
        }
        
        // add buttons to menuLayer
        buttonLocal = ButtonMesh.createUnlitButton(innerWidth: 8.0 * tileSize, innerHeight: 1.2 * tileSize, borderWidth: tileSize / 2.0)
        buttonLocal!.alpha = 1.0
        button1v1 = ButtonMesh.createUnlitButton(innerWidth: 10.0 * tileSize, innerHeight: 1.2 * tileSize, borderWidth: tileSize / 2.0)
        button1v1!.alpha = 1.0
        buttonBuyCoffee = ButtonMesh.createLitButton(innerWidth: 11.0 * tileSize, innerHeight: 1.2 * tileSize, borderWidth: tileSize / 2.0)
        buttonBuyCoffee!.alpha = 1.0
        // also create pause button
        buttonPause = ButtonMesh.createPauseButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonPause!.position.x = boardW / 2.0 + tileSize * 4.0
        buttonPause!.position.y = -boardH / 2.0 + tileSize
        // pause button goes on a game screen layer
        baseLayer!.meshes.append(buttonPause!)
        // also create back button
        buttonBack = ButtonMesh.createBackButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonBack!.position.x = -boardW / 2.0 + tileSize * 3.0
        buttonBack!.position.y = -boardH / 2.0 + tileSize * 3.0
        // back button goes to a multiplayer screen lauyer
        multiplayerButtonsLayer.meshes.append(buttonBack!)
        // put them in their correct positions
        buttonLocal!.position.y = -1.5 * tileSize
        buttonBuyCoffee!.position.y = 1.0 * tileSize
        button1v1!.position.y = 3.5 * tileSize
        // add them to the layer
        mainButtonsLayer.meshes.append(buttonLocal!)
        mainButtonsLayer.meshes.append(buttonBuyCoffee!)
        mainButtonsLayer.meshes.append(button1v1!)
        // make texts for the buttons
        let textSize = CGSize(width: 512, height: 64)
        var font = Font.systemFont(ofSize: 40)
        var textLocal = TextQuadMesh(text: "Practice Zapping", font: font, color: Color.white, size: textSize)
        var text1v1 = TextQuadMesh(text: "1v1 Make Most Points", font: font, color: Color.white, size: textSize)
        var textBuyCoffee = TextQuadMesh(text: "Let's Have (Digital) Coffee", font: font, color: Color.white, size: textSize)
        // put them in their correct positions
        textLocal.position.y = -1.5 * tileSize + 6
        textBuyCoffee.position.y = 1.0 * tileSize + 6
        text1v1.position.y = 3.5 * tileSize + 6
        // add them to the layer
        mainButtonsLayer.meshes.append(textLocal)
        mainButtonsLayer.meshes.append(textBuyCoffee)
        mainButtonsLayer.meshes.append(text1v1)
        
        // now some license info
        let licenseInfo = """
        "Itty Bitty 8 Bit" Kevin MacLeod (incompetech.com)
        Licensed under Creative Commons: By Attribution 4.0 License
        http://creativecommons.org/licenses/by/4.0/
        """
        font = Font.systemFont(ofSize: 16)
        var textLicense = TextQuadMesh(text: licenseInfo, font: font, color: Color.white, size: textSize)
        textLicense.position.y = 5.5 * tileSize
        menuLayer.meshes.append(textLicense)
    }

    // function to handle transitions to various screens
    func setCurrentScreen(_ screen: Screen) {
        currentScreen = screen
        if currentScreen === mainMenuScreen {
            gameMgr.clearElectricArcs()
            maxArcDisplacement = 0.1
            makeMenuArcs()
            multiMgr.authenticatePlayer()
        }
        if currentScreen === gameScreen {
            gameMgr.clearElectricArcs()
            // MARK: starting new LOCAL game
            gameMgr.startNewGame(isMultiplayer: false)
            maxArcDisplacement = 0.2
            gameMgr.gameBoard?.checkConnections()
            gameMgr.addElectricArcs()
        }
        if currentScreen === multiplayerScreen {
            gameMgr.clearElectricArcs()
            // TODO: show the game center stuff
        }
    }

    // helper function to generate arcs based on segments list
    func generateArcs(from segments: [Segment], color: SegmentColor, width: Float, powerOfTwo: Int) {
        for segment in segments {
            let arc = ElectricArcMesh(startPoint: segment.startPoint, endPoint: segment.endPoint, powerOfTwo: powerOfTwo, width: width, color: color)
            effectsLayer.meshes.append(arc)
        }
    }

    // function to write ZAPZAP in the main manu, with electric arcs
    func makeMenuArcs(shiftx1: Float = 0.0, shifty1: Float = 0.0, shiftx2: Float = 0.0, shifty2: Float = 0.0) {
        // Segments for letter Z1
        let zSegments1 = [
            Segment(startPoint: SIMD2<Float>(-300.0-50.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-200.0-50.0 + shiftx1  , -250.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-200.0-50.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-300.0-50.0 + shiftx1  , -150.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-300.0-50.0 + shiftx1, -150.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-200.0-50.0 + shiftx1  , -150.0-25.0 + shifty1))
        ]
        generateArcs(from: zSegments1, color: .orange, width: 8, powerOfTwo: 4)

        // Segments for letter A1
        let aSegments1 = [
            Segment(startPoint: SIMD2<Float>(-150.0-30.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-200.0-30.0 + shiftx1  , -150.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-150.0-30.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-100.0-30.0 + shiftx1  , -150.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-175.0-30.0 + shiftx1, -200.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-125.0-30.0 + shiftx1  , -200.0-25.0 + shifty1))
        ]
        generateArcs(from: aSegments1, color: .orange, width: 8, powerOfTwo: 4)

        // Segments for letter P1
        let pSegments1 = [
            Segment(startPoint: SIMD2<Float>(-100.0-10.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(0.0-10.0 + shiftx1     , -250.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-100.0-10.0 + shiftx1, -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(-100.0-10.0 + shiftx1  , -150.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(0.0-10.0 + shiftx1   , -250.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(0.0-10.0 + shiftx1     , -200.0-25.0 + shifty1)),
            Segment(startPoint: SIMD2<Float>(-100.0-10.0 + shiftx1, -200.0-25.0 + shifty1),
                    endPoint: SIMD2<Float>(0.0-10.0 + shiftx1     , -200.0-25.0 + shifty1))
        ]
        generateArcs(from: pSegments1, color: .orange, width: 8, powerOfTwo: 4)

        // Segments for letter Z2
        let zSegments2 = [
            Segment(startPoint: SIMD2<Float>(0.0+10.0 + shiftx2  , -250.0 + shifty2),
                    endPoint: SIMD2<Float>(100.0+10.0 + shiftx2  , -250.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(100.0+10.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(0.0+10.0 + shiftx2    , -150.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(0.0+10.0 + shiftx2  , -150.0 + shifty2),
                    endPoint: SIMD2<Float>(100.0+10.0 + shiftx2  , -150.0 + shifty2))
        ]
        generateArcs(from: zSegments2, color: .indigo, width: 8, powerOfTwo: 4)

        // Segments for letter A2
        let aSegments2 = [
            Segment(startPoint: SIMD2<Float>(150.0+30.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(100.0+30.0 + shiftx2  , -150.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(150.0+30.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(200.0+30.0 + shiftx2  , -150.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(125.0+30.0 + shiftx2, -200.0 + shifty2),
                    endPoint: SIMD2<Float>(175.0+30.0 + shiftx2  , -200.0 + shifty2))
        ]
        generateArcs(from: aSegments2, color: .indigo, width: 8, powerOfTwo: 4)

        // Segments for letter P2
        let pSegments2 = [
            Segment(startPoint: SIMD2<Float>(200.0+50.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(300.0+50.0 + shiftx2  , -250.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(200.0+50.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(200.0+50.0 + shiftx2  , -150.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(300.0+50.0 + shiftx2, -250.0 + shifty2),
                    endPoint: SIMD2<Float>(300.0+50.0 + shiftx2  , -200.0 + shifty2)),
            Segment(startPoint: SIMD2<Float>(200.0+50.0 + shiftx2, -200.0 + shifty2),
                    endPoint: SIMD2<Float>(300.0+50.0 + shiftx2  , -200.0 + shifty2))
        ]
        generateArcs(from: pSegments2, color: .indigo, width: 8, powerOfTwo: 4)
    }

    // this sets up the screen projection matrix
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
    
    // Function to start a random tile rotation in the menu
    func startRandomTileRotation() {
        guard let animationManager = gameMgr.animationManager else { return }
        if animationManager.simpleRotateAnimations.isEmpty && Int.random(in: 0...40) == 0 {
            // Randomly pick a QuadMesh from the menuLayer
            if let randomQuad = menuLayer.meshes.randomElement() as? QuadMesh {
                // Create and add a simple rotate animation for the picked quad
                let rotateAnimation = SimpleRotateAnimation(quad: randomQuad, fingerQuad: animationManager.fingerQuad, duration: 1.0, effectsLayer: effectsLayer)
                
                // Add the animation to a list to be updated every frame
                animationManager.addSimpleRotation(rotateAnimation)
            }  
        }
    }

    // function to convert from viewport CGPoint to game model coordinates
    func getGameXY(fromPoint: CGPoint) -> SIMD2<Float> {
        // converting from screen coordinates to game coordinates
        let screenW = Float(self.view.drawableSize.width)
        let screenH = Float(self.view.drawableSize.height)
        let horizRatio = screenW / needW
        let vertRatio = screenH / needH
        var gameX: Float
        var gameY: Float
        if horizRatio < vertRatio {
            gameX = (Float(fromPoint.x) - (screenW / 2.0)) / horizRatio
            gameY = (Float(fromPoint.y) - (screenH / 2.0)) / horizRatio
        } else {
            gameX = (Float(fromPoint.x) - (screenW / 2.0)) / vertRatio
            gameY = (Float(fromPoint.y) - (screenH / 2.0)) / vertRatio
        }
//        print("converted to GAME COORDINATES: ", gameX, ", ", gameY)
        return SIMD2(gameX, gameY)
    }

    // function that updates everything depending on the screen
    func update() {
        // logo screen updates
        if currentScreen === logoScreen {
            // Update elapsed time
            let elapsedTime = Float(frameIndex) / 60.0 // Assuming 60 FPS
            
            if frameIndex == 65 { // at exactly frame X
                print ("this is frame 65")
                initializeGameScreens()
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
                setCurrentScreen(mainMenuScreen)
            }
            gameMgr.lastInput = nil
        }

        // game screen updates
        if currentScreen === gameScreen {
            // verify pause button first
            if gameMgr.lastInput != nil {
                if buttonPause!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    // temporarily go back to main menu
                    // TODO go to pause menu screen
                    setCurrentScreen(mainMenuScreen)
                }
            }
            gameMgr.update()
            // update the GameObjects in the objectLayer
            if objectsLayer != nil {
                for mesh in objectsLayer.meshes {
                    if let gameObject = mesh as? GameObject {
                        gameObject.update()
                    }
                }
            }
            gameMgr.lastInput = nil
        }
        
        // main menu screen updates
        if currentScreen === mainMenuScreen {
            // make some tile in the background rotate
            startRandomTileRotation()
            // only update the simple rotations in the main menu
            gameMgr.animationManager?.updateSimpleRotateAnimations()
//            gameMgr.animationManager?.updateAnimations()
            // check user input
            if gameMgr.lastInput != nil {
                if buttonLocal!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    gameMgr.zapGameState = .waitingForInput
                    // TODO: reset the game - right now it goes to the already existing game
                    setCurrentScreen(gameScreen)
                }
                if button1v1!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    setCurrentScreen(multiplayerScreen)
                    // TODO: maybe here show the game center stuff?
                    multiMgr.presentGameCenterMatchmaking()
                }
            }
            gameMgr.lastInput = nil
        }
        
        // multiplayer screen updates
        if currentScreen === multiplayerScreen {
            // same stuff with the tiles in the back
            startRandomTileRotation()
            // only update the simple rotations in the main menu
            gameMgr.animationManager?.updateSimpleRotateAnimations()
//            gameMgr.animationManager?.updateAnimations()
            // check user input -- back button goes to the main menu
            if gameMgr.lastInput != nil {
                if buttonBack!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    setCurrentScreen(mainMenuScreen)
                }
            }
            gameMgr.lastInput = nil
        }
    }

    // this is the main draw function for the application
    // better to not modify it, use rendering of layers, meshes, set up various screens
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

