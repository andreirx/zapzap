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
let tutorialImages = 6


// // // // // // // // // // // // // // // // // // // // //
//
// ResourceTextures - class for managing textures
//

class ResourceTextures {
    private var textures: [String: MTLTexture] = [:]
    private let textureLoader: MTKTextureLoader
    private var ambience: String = ""
    
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
    
    func setAmbience(named amb: String = "") {
        self.ambience = amb
    }
    
    func getTexture(named name: String) -> MTLTexture? {
        // Try to get the texture with the ambience modifier
        if let ambienceTexture = textures[name + "_\(ambience)"] {
            return ambienceTexture
        }
        // Fallback to base texture if ambience texture is not available
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
    var purchaseScreen: Screen!
    var gameScreen: Screen!
    var tutorialScreen: Screen!
    var pauseScreen: Screen!
    
    var currentScreen: Screen?

    // buttons
    var buttonLocal: ButtonMesh?
    var buttonPurchase: ButtonMesh?
    var buttonTutorial: ButtonMesh?
    var buttonVsBot: ButtonMesh?
    
    var buttonPause: ButtonMesh?
    var buttonBack: ButtonMesh?
    
    var buttonPrev: ButtonMesh?
    var buttonNext: ButtonMesh?
    var buttonClose: ButtonMesh?
    
    var buttonLBomb: ButtonMesh?
    var buttonLCross: ButtonMesh?
    var buttonLArrow: ButtonMesh?
    var buttonRBomb: ButtonMesh?
    var buttonRCross: ButtonMesh?
    var buttonRArrow: ButtonMesh?

    var buttonMainMenu: ButtonMesh?
    var buttonToggleMusic: ButtonMesh?
    var buttonToggleEffects: ButtonMesh?
    var checkMusic: ButtonMesh?
    var checkEffects: ButtonMesh?
    var uncheckMusic: ButtonMesh?
    var uncheckEffects: ButtonMesh?
    
    // object button meshes
    var objLBomb: Bomb?
    var objLCross: Cross?
    var objLArrow: Arrow?
    var objRBomb: Bomb?
    var objRCross: Cross?
    var objRArrow: Arrow?

    // tutorial image meshes - 6 of them
    var tutMesh: [QuadMesh?] = Array(repeating: nil, count: tutorialImages)
    var tutIndex: Int = 0

    // layers
    var backgroundLayer: GraphicsLayer!
    var menuLayer: GraphicsLayer!
    var mainButtonsLayer: GraphicsLayer!
    var purchaseButtonsLayer: GraphicsLayer!
    var fingerLayer: GraphicsLayer!
    var baseLayer: GameBoardLayer? // this one won't be ready at creation time, will have to add it later after getting a GameManager
    var objectsLayer: GraphicsLayer!
    var buttonObjLayer: GraphicsLayer!
    var textLayer: GraphicsLayer!
    var effectsLayer: EffectsLayer!
    var tutorialLayer: GraphicsLayer!
    var tutButtonsLayer: GraphicsLayer!
    var pauseButtonsLayer: GraphicsLayer!

    
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
        purchaseScreen = Screen()
        gameScreen = Screen()
        pauseScreen = Screen()
        tutorialScreen = Screen()

        // Setup logo screen
        setupLogoScreen()
        
        // Set logo screen as the initial screen
        setCurrentScreen(logoScreen)
    }
    
    static var isHalloween: Bool {
        let calendar = Calendar.current
        let today = Date()

        let halloweenStartComponents = DateComponents(month: 10, day: 27)
        let halloweenEndComponents = DateComponents(month: 11, day: 2)
        
        // Get today's month and day components
        let todayComponents = calendar.dateComponents([.month, .day], from: today)
        
        // Check if today's date is within the Halloween period
        if (todayComponents.month == halloweenStartComponents.month && todayComponents.day! >= halloweenStartComponents.day!) ||
            (todayComponents.month == halloweenEndComponents.month && todayComponents.day! <= halloweenEndComponents.day!) ||
            (todayComponents.month! > halloweenStartComponents.month! && todayComponents.month! < halloweenEndComponents.month!) {
            return true
        } else {
            return false
        }
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
/*
        // Call checkConnections and recreate connections
        gameMgr.gameBoard?.checkConnections()

        // remake all electric arcs according to their markers
        gameMgr.remakeElectricArcs(forMarker: .left, withColor: .indigo, po2: 4, andWidth: 4.0)
        gameMgr.remakeElectricArcs(forMarker: .right, withColor: .orange, po2: 4, andWidth: 4.0)
        */
    }
    
    // function does what it says - sets up game screens, with their layers and contents
    func initializeGameScreens() {
        guard let animationManager = gameMgr.animationManager else { return }
        let textureNames = ["arrows", "base_tiles", "stars", "superhero", "tutorials", "base_tiles_haloween", "arrows_haloween"]
        Renderer.textures = ResourceTextures(device: Renderer.device, textureNames: textureNames)
        
        // Set up layers and initialize game screen
        backgroundLayer = GraphicsLayer()
        objectsLayer = GraphicsLayer()
        buttonObjLayer = GraphicsLayer()
        effectsLayer = EffectsLayer()
        textLayer = GraphicsLayer()
        menuLayer = GraphicsLayer()
        mainButtonsLayer = GraphicsLayer()
        purchaseButtonsLayer = GraphicsLayer()
        fingerLayer = GraphicsLayer()
        tutorialLayer = GraphicsLayer()
        tutButtonsLayer = GraphicsLayer()
        pauseButtonsLayer = GraphicsLayer()

        gameMgr.createTiles()
        if Renderer.isHalloween {
            Renderer.textures.setAmbience(named: "haloween")
            SoundManager.shared.setAmbience(named: "haloween")
        }
        backgroundLayer.texture = Renderer.textures.getTexture(named: "stars")
        objectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        buttonObjLayer.texture = Renderer.textures.getTexture(named: "arrows")
        effectsLayer.texture = Renderer.textures.getTexture(named: "arrows")
        menuLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        mainButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        purchaseButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        fingerLayer.texture = Renderer.textures.getTexture(named: "arrows")
        tutorialLayer.texture = Renderer.textures.getTexture(named: "tutorials")
        tutButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")
        pauseButtonsLayer.texture = Renderer.textures.getTexture(named: "base_tiles")

        for i in 0..<tutorialImages {
            tutMesh[i] = QuadMesh(size: boardH - tileSize,
              topLeftUV: SIMD2(x: Float(i % 3) / 3.0, y: Float(i / 3) / 2.0),
              bottomRightUV: SIMD2(x: (0.995 + Float(i % 3)) / 3.0, y: (0.995 + Float(i / 3)) / 2.0))
            tutMesh[i]?.alpha = 1.0
        }

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
        gameScreen.addLayer(buttonObjLayer)
//        gameScreen.addLayer(superheroLayer)
//        gameScreen.addLayer(superheroExtraLayer)

        // add layers to menu screen
        mainMenuScreen.addLayer(menuLayer)
        mainMenuScreen.addLayer(mainButtonsLayer)
        mainMenuScreen.addLayer(fingerLayer)
        mainMenuScreen.addLayer(effectsLayer)
//        gameScreen.addLayer(textLayer)
        
        // add layers to tutorial screen
        tutorialScreen.addLayer(menuLayer)
        tutorialScreen.addLayer(tutorialLayer)
        tutorialScreen.addLayer(tutButtonsLayer)
//        tutorialScreen.addLayer(fingerLayer)
//        tutorialScreen.addLayer(effectsLayer)

        // add layers to multiplayer screen
        purchaseScreen.addLayer(menuLayer)
        purchaseScreen.addLayer(purchaseButtonsLayer)
        purchaseScreen.addLayer(fingerLayer)
        purchaseScreen.addLayer(effectsLayer)
        
        // add layers to the pause screen
        pauseScreen.addLayer(menuLayer)
        pauseScreen.addLayer(pauseButtonsLayer)
        pauseScreen.addLayer(fingerLayer)
//        pauseScreen.addLayer(effectsLayer)

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
        
        // also create pause button
        buttonPause = ButtonMesh.createPauseButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonPause!.position.x = boardW / 2.0 + tileSize * 2.0
        buttonPause!.position.y = -boardH / 2.0 + tileSize
        buttonPause!.alpha = 1.0
        // and the powers buttons
        buttonLBomb = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonLBomb!.position.x = -boardW / 2.0 - tileSize * 2.0
        buttonLBomb!.position.y = tileSize * 1.5
        buttonLBomb!.alpha = 0.5
        objLBomb = Bomb()
        objLBomb!.position.x = -boardW / 2.0 - tileSize * 2.0
        objLBomb!.position.y = tileSize * 1.5
        objLBomb!.alpha = 0.15
        buttonLCross = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonLCross!.position.x = -boardW / 2.0 - tileSize * 1.0
        buttonLCross!.position.y = tileSize * 2.7
        buttonLCross!.alpha = 0.5
        objLCross = Cross()
        objLCross!.position.x = -boardW / 2.0 - tileSize * 1.0
        objLCross!.position.y = tileSize * 2.7
        objLCross!.alpha = 0.15
        buttonLArrow = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonLArrow!.position.x = -boardW / 2.0 - tileSize * 1.0
        buttonLArrow!.position.y = tileSize * 4.2
        buttonLArrow!.alpha = 0.5
        objLArrow = Arrow()
        objLArrow!.position.x = -boardW / 2.0 - tileSize * 1.0
        objLArrow!.position.y = tileSize * 4.2
        objLArrow!.alpha = 0.15
        buttonRBomb = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonRBomb!.position.x = boardW / 2.0 + tileSize * 2.0
        buttonRBomb!.position.y = tileSize * 1.5
        buttonRBomb!.alpha = 0.5
        objRBomb = Bomb()
        objRBomb!.position.x = boardW / 2.0 + tileSize * 2.0
        objRBomb!.position.y = tileSize * 1.5
        objRBomb!.alpha = 0.15
        buttonRCross = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonRCross!.position.x = boardW / 2.0 + tileSize * 1.0
        buttonRCross!.position.y = tileSize * 2.7
        buttonRCross!.alpha = 0.5
        objRCross = Cross()
        objRCross!.position.x = boardW / 2.0 + tileSize * 1.0
        objRCross!.position.y = tileSize * 2.7
        objRCross!.alpha = 0.15
        buttonRArrow = ButtonMesh.createThinOutlineButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        buttonRArrow!.position.x = boardW / 2.0 + tileSize * 1.0
        buttonRArrow!.position.y = tileSize * 4.2
        buttonRArrow!.alpha = 0.5
        objRArrow = Arrow()
        objRArrow!.position.x = boardW / 2.0 + tileSize * 1.0
        objRArrow!.position.y = tileSize * 4.2
        objRArrow!.alpha = 0.15
        // pause button and superpower buttons go on a game screen layer
        baseLayer!.meshes.append(buttonPause!)
        baseLayer!.meshes.append(buttonLBomb!)
        baseLayer!.meshes.append(buttonLCross!)
        baseLayer!.meshes.append(buttonLArrow!)
        baseLayer!.meshes.append(buttonRBomb!)
        baseLayer!.meshes.append(buttonRCross!)
        baseLayer!.meshes.append(buttonRArrow!)
        buttonObjLayer!.meshes.append(objLBomb!)
        buttonObjLayer!.meshes.append(objLCross!)
        buttonObjLayer!.meshes.append(objLArrow!)
        buttonObjLayer!.meshes.append(objRBomb!)
        buttonObjLayer!.meshes.append(objRCross!)
        buttonObjLayer!.meshes.append(objRArrow!)

        // also create back button
        buttonBack = ButtonMesh.createBackButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonBack!.position.x = -boardW / 2.0 + tileSize * 2.5
        buttonBack!.position.y = -boardH / 2.0 + tileSize * 2.5
        buttonBack!.alpha = 1.0
        // back button goes to a multiplayer screen lauyer
        purchaseButtonsLayer.meshes.append(buttonBack!)
        pauseButtonsLayer.meshes.append(buttonBack!)
        
        // create pause menu buttons
        buttonMainMenu = ButtonMesh.createRedButton(innerWidth: 7.0 * tileSize, innerHeight: 0.8 * tileSize, borderWidth: tileSize / 3.0)
        buttonMainMenu!.alpha = 1.0
        buttonMainMenu!.position.y = 3.0 * tileSize
        buttonToggleMusic = ButtonMesh.createThickOutlineButton(innerWidth: 8.0 * tileSize, innerHeight: 0.8 * tileSize, borderWidth: tileSize / 2.0)
        buttonToggleMusic!.alpha = 1.0
        buttonToggleMusic!.position.y = -1.0 * tileSize
        buttonToggleEffects = ButtonMesh.createThickOutlineButton(innerWidth: 8.0 * tileSize, innerHeight: 0.8 * tileSize, borderWidth: tileSize / 2.0)
        buttonToggleEffects!.alpha = 1.0
        buttonToggleEffects!.position.y = 1.0 * tileSize
        checkEffects = ButtonMesh.createCheckButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        checkEffects!.position.x = boardW / 4.5
        checkEffects!.position.y = 1.0 * tileSize
        checkEffects!.alpha = 1.0
        checkMusic = ButtonMesh.createCheckButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        checkMusic!.position.x = boardW / 4.5
        checkMusic!.position.y = -1.0 * tileSize
        checkMusic!.alpha = 1.0
        uncheckEffects = ButtonMesh.createUncheckButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        uncheckEffects!.position.x = boardW / 4.5
        uncheckEffects!.position.y = 1.0 * tileSize
        uncheckEffects!.alpha = 1.0
        uncheckMusic = ButtonMesh.createUncheckButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize * 0.8)
        uncheckMusic!.position.x = boardW / 4.5
        uncheckMusic!.position.y = -1.0 * tileSize
        uncheckMusic!.alpha = 1.0
        // add them to the pause menu layer
        pauseButtonsLayer.meshes.append(buttonMainMenu!)
        pauseButtonsLayer.meshes.append(buttonToggleMusic!)
        pauseButtonsLayer.meshes.append(buttonToggleEffects!)

        // make texts for the buttons
        let textSize = CGSize(width: 512, height: 64)
        var font = Font.systemFont(ofSize: 40)
        let textOffset: Float = 6.0

        //
        var textMusic = TextQuadMesh(text: "MUSIC", font: font, color: Color.white, size: textSize)
        var textEffects = TextQuadMesh(text: "EFFECTS", font: font, color: Color.white, size: textSize)
        var textMenu = TextQuadMesh(text: "Quit Game", font: font, color: Color.white, size: textSize)
        // put them in their correct positions
        textMusic.position.y = -1.0 * tileSize + textOffset
        textEffects.position.y = 1.0 * tileSize + textOffset
        textMenu.position.y = 3.0 * tileSize + textOffset
        // add them to the layer
        pauseButtonsLayer.meshes.append(checkMusic!)
        pauseButtonsLayer.meshes.append(checkEffects!)
        pauseButtonsLayer.meshes.append(textMusic)
        pauseButtonsLayer.meshes.append(textEffects)
        pauseButtonsLayer.meshes.append(textMenu)

        // create tutorial screen buttons
        buttonPrev = ButtonMesh.createBackButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonPrev!.position.x = -boardH / 2.0
        buttonPrev!.position.y = boardH / 2.0 - tileSize
        buttonNext = ButtonMesh.createFrontButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonNext!.position.x = boardH / 2.0
        buttonNext!.position.y = boardH / 2.0 - tileSize
        buttonClose = ButtonMesh.createCancelButton(innerWidth: 0.0, innerHeight: 0.0, borderWidth: tileSize)
        buttonClose!.position.x = boardH / 2.0
        buttonClose!.position.y = -boardH / 2.0 + tileSize
        // add them to the tutorial buttons layer
        tutButtonsLayer.meshes.append(buttonPrev!)
        tutButtonsLayer.meshes.append(buttonNext!)
        tutButtonsLayer.meshes.append(buttonClose!)

        // create special abilities buttons

        // add buttons to menuLayer
        buttonLocal = ButtonMesh.createUnlitButton(innerWidth: 5.0 * tileSize, innerHeight: 1.0 * tileSize, borderWidth: tileSize / 3.0)
        buttonLocal!.alpha = 1.0
        buttonPurchase = ButtonMesh.createUnlitButton(innerWidth: 10.0 * tileSize, innerHeight: 1.0 * tileSize, borderWidth: tileSize / 3.0)
        buttonPurchase!.alpha = 1.0
        buttonTutorial = ButtonMesh.createLitButton(innerWidth: 7.0 * tileSize, innerHeight: 1.0 * tileSize, borderWidth: tileSize / 3.0)
        buttonTutorial!.alpha = 1.0
        buttonVsBot = ButtonMesh.createUnlitButton(innerWidth: 5.0 * tileSize, innerHeight: 1.0 * tileSize, borderWidth: tileSize / 3.0)
        buttonVsBot!.alpha = 1.0
        // put them in their correct positions
        buttonLocal!.position.y = -1.0 * tileSize
        buttonLocal!.position.x = -3.0 * tileSize
        buttonVsBot!.position.y = -1.0 * tileSize
        buttonVsBot!.position.x = 3.0 * tileSize
        buttonTutorial!.position.y = 1.0 * tileSize
        buttonPurchase!.position.y = 3.0 * tileSize
        // add them to the layer
        mainButtonsLayer.meshes.append(buttonLocal!)
        mainButtonsLayer.meshes.append(buttonVsBot!)
        mainButtonsLayer.meshes.append(buttonTutorial!)
//        mainButtonsLayer.meshes.append(buttonPurchase!)
        // make texts for the buttons
//        let textSize = CGSize(width: 512, height: 64)
//        var font = Font.systemFont(ofSize: 40)
        var textLocal = TextQuadMesh(text: "Zen Mode", font: font, color: Color.white, size: textSize)
        var textVsBot = TextQuadMesh(text: "Vs Bot", font: font, color: Color.white, size: textSize)
        var textBuy = TextQuadMesh(text: "Purchase Ambiances", font: font, color: Color.white, size: textSize)
        var textTutorial = TextQuadMesh(text: "Tutorial", font: font, color: Color.white, size: textSize)
        // put them in their correct positions
        textLocal.position.y = -1.0 * tileSize + textOffset
        textLocal.position.x = -3.0 * tileSize
        textVsBot.position.y = -1.0 * tileSize + textOffset
        textVsBot.position.x = 3.0 * tileSize
        textTutorial.position.y = 1.0 * tileSize + textOffset
        textBuy.position.y = 3.0 * tileSize + textOffset
        // add them to the layer
        mainButtonsLayer.meshes.append(textLocal)
        mainButtonsLayer.meshes.append(textVsBot)
        mainButtonsLayer.meshes.append(textTutorial)
//        mainButtonsLayer.meshes.append(textBuy)
        
        // now some license info
        /*
        let licenseInfo = """
        "Itty Bitty 8 Bit" Kevin MacLeod (incompetech.com)
        Licensed under Creative Commons: By Attribution 4.0 License
        http://creativecommons.org/licenses/by/4.0/
        """
        */
        var licenseInfo = """
        "Itty Bitty 8 Bit" Kevin MacLeod (incompetech.com)
        Licensed under Creative Commons: By Attribution 4.0 License
        http://creativecommons.org/licenses/by/4.0/
        """
        if Renderer.isHalloween {
            var licenseInfo = """
            "The Machine Thinks" Kevin MacLeod (incompetech.com)
            Licensed under Creative Commons: By Attribution 4.0 License
            http://creativecommons.org/licenses/by/4.0/
            """
        }
        font = Font.systemFont(ofSize: 14)
        var textLicense = TextQuadMesh(text: licenseInfo, font: font, color: Color.white, size: textSize)
        textLicense.position.y = 4.8 * tileSize
        menuLayer.meshes.append(textLicense)
    }

    // function to handle transitions to various screens
    func setCurrentScreen(_ screen: Screen) {
        currentScreen = screen
        if currentScreen === mainMenuScreen {
            gameMgr.clearElectricArcs()
            effectsLayer.meshes.removeAll()
            maxArcDisplacement = 0.1
            makeMenuArcs()
        }
        if currentScreen === gameScreen {
            gameMgr.clearElectricArcs()
            maxArcDisplacement = 0.2
            gameMgr.gameBoard?.checkConnections()
            gameMgr.addElectricArcs()
            if let textQuadMesh = menuLayer.meshes.first(where: { $0 is TextQuadMesh }) as? TextQuadMesh {
                textQuadMesh.alpha = 1.0
            }
        }
        if currentScreen === purchaseScreen || currentScreen === tutorialScreen {
            gameMgr.clearElectricArcs()
//            multiMgr.errorMsg = ""
        }
        if currentScreen === tutorialScreen {
            tutIndex = 0
            tutorialLayer.meshes.removeAll()
            tutorialLayer.meshes.append(tutMesh[tutIndex]!)
            if let textQuadMesh = menuLayer.meshes.first(where: { $0 is TextQuadMesh }) as? TextQuadMesh {
                textQuadMesh.alpha = 0.0
            }
        }
        if currentScreen === pauseScreen {
            //
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
    func makeMenuArcs(shiftx1: Float = 0.0, shifty1: Float = 25.0, shiftx2: Float = 0.0, shifty2: Float = 25.0) {
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
                multiMgr.authenticatePlayer()
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
                    // TODO: move the leaderboard reporting to the end of the game
                    setCurrentScreen(pauseScreen)
                }
                // check for powers deployments
                // TODO: differentiate local vs multiplayer
                // also
                // TODO: just change the acquired and armed status
                // and update the alphas based on these
                // because the armed and acquired status can change elsewhere too
                if gameMgr.powerLBomb {
                    // if the bomb is "acquired" and you tap on it, it will ARM it
                    // but DISARM the others if they were armed before
                    if buttonLBomb!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armLBomb = !gameMgr.armLBomb
                        if gameMgr.armLBomb {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armLCross = false
                        gameMgr.armLArrow = false
                    }
                }
                if gameMgr.powerLCross {
                    // if the cross is "acquired" and you tap on it, it will ARM it
                    // but DISARM the others if they were armed before
                    if buttonLCross!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armLCross = !gameMgr.armLCross
                        if gameMgr.armLCross {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armLBomb = false
                        gameMgr.armLArrow = false
                    }
                }
                if gameMgr.powerLArrow {
                    // if the arrow is "acquired" and you tap on it, it will ARM it
                    // but DISARM the others if they were armed before
                    if buttonLArrow!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armLArrow = !gameMgr.armLArrow
                        if gameMgr.armLArrow {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armLCross = false
                        gameMgr.armLBomb = false
                    }
                }
                if gameMgr.powerRBomb {
                    // same as above for the right buttons group
                    if buttonRBomb!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armRBomb = !gameMgr.armRBomb
                        if gameMgr.armRBomb {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armRCross = false
                        gameMgr.armRArrow = false
                    }
                }
                if gameMgr.powerRCross {
                    // same as above for the right buttons group
                    if buttonRCross!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armRCross = !gameMgr.armRCross
                        if gameMgr.armRCross {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armRBomb = false
                        gameMgr.armRArrow = false
                    }
                }
                if gameMgr.powerRArrow {
                    // same as above for the right buttons group
                    if buttonRArrow!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                        gameMgr.armRArrow = !gameMgr.armRArrow
                        if gameMgr.armRArrow {
                            SoundManager.shared.playSoundEffect(filename: "alarm")
                        }
                        gameMgr.armRBomb = false
                        gameMgr.armRCross = false
                    }
                }
            }
            // update buttons alphas based on acquired and armed status
            if gameMgr.powerLBomb {
                if gameMgr.armLBomb {
                    buttonLBomb!.alpha = 3.0
                    objLBomb!.alpha = 3.0
                } else {
                    buttonLBomb!.alpha = 1.0
                    objLBomb!.alpha = 1.0
                }
            } else {
                gameMgr.armLBomb = false
                buttonLBomb!.alpha = 1.0
                objLBomb!.alpha = 0.15
            }
            
            if gameMgr.powerRBomb {
                if gameMgr.armRBomb {
                    buttonRBomb!.alpha = 3.0
                    objRBomb!.alpha = 3.0
                } else {
                    buttonRBomb!.alpha = 1.0
                    objRBomb!.alpha = 1.0
                }
            } else {
                gameMgr.armRBomb = false
                buttonRBomb!.alpha = 1.0
                objRBomb!.alpha = 0.15
            }
            
            if gameMgr.powerLCross {
                if gameMgr.armLCross {
                    buttonLCross!.alpha = 3.0
                    objLCross!.alpha = 3.0
                } else {
                    buttonLCross!.alpha = 1.0
                    objLCross!.alpha = 1.0
                }
            } else {
                gameMgr.armLCross = false
                buttonLCross!.alpha = 1.0
                objLCross!.alpha = 0.15
            }
            
            if gameMgr.powerRCross {
                if gameMgr.armRCross {
                    buttonRCross!.alpha = 3.0
                    objRCross!.alpha = 3.0
                } else {
                    buttonRCross!.alpha = 1.0
                    objRCross!.alpha = 1.0
                }
            } else {
                gameMgr.armRCross = false
                buttonRCross!.alpha = 1.0
                objRCross!.alpha = 0.15
            }
            
            if gameMgr.powerLArrow {
                if gameMgr.armLArrow {
                    buttonLArrow!.alpha = 3.0
                    objLArrow!.alpha = 3.0
                } else {
                    buttonLArrow!.alpha = 1.0
                    objLArrow!.alpha = 1.0
                }
            } else {
                gameMgr.armLArrow = false
                buttonLArrow!.alpha = 1.0
                objLArrow!.alpha = 0.15
            }
            
            if gameMgr.powerRArrow {
                if gameMgr.armRArrow {
                    buttonRArrow!.alpha = 3.0
                    objRArrow!.alpha = 3.0
                } else {
                    buttonRArrow!.alpha = 1.0
                    objRArrow!.alpha = 1.0
                }
            } else {
                gameMgr.armRArrow = false
                buttonRArrow!.alpha = 1.0
                objRArrow!.alpha = 0.15
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
            // update the GameObjects in the objectLayer
            if buttonObjLayer != nil {
                for mesh in buttonObjLayer.meshes {
                    if let gameObject = mesh as? GameObject {
                        gameObject.update()
                    }
                }
            }
            gameMgr.lastInput = nil
        }
        
        // common menu updates
        if currentScreen === mainMenuScreen || currentScreen === purchaseScreen || currentScreen === tutorialScreen || currentScreen === pauseScreen {
            // make some tile in the background rotate
            startRandomTileRotation()
            // only update the simple rotations in the main menu
            gameMgr.animationManager?.updateSimpleRotateAnimations()
        }

        // main menu screen updates
        if currentScreen === mainMenuScreen {
            // check user input
            if gameMgr.lastInput != nil {
                if buttonLocal!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    gameMgr.zapGameState = .waitingForInput
                    // MARK: starting new ZEN game
                    gameMgr.startNewGame(isMultiplayer: false)
                    gameMgr.bot = nil
                    setCurrentScreen(gameScreen)
                }
                if buttonVsBot!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    gameMgr.zapGameState = .waitingForInput
                    // MARK: starting new VS BOT game
                    gameMgr.startNewGame(isMultiplayer: false)
                    gameMgr.addBot()
                    setCurrentScreen(gameScreen)
                }
                if buttonPurchase!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    // TODO: make purchases or play multiplayer
//                    setCurrentScreen(purchaseScreen)
//                    multiMgr.presentGameCenterMatchmaking()
                }
                if buttonTutorial!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    setCurrentScreen(tutorialScreen)
                }
            }
            gameMgr.lastInput = nil
        }
        
        // multiplayer screen updates
        if currentScreen === purchaseScreen {
            // check user input -- back button goes to the main menu
            if gameMgr.lastInput != nil {
                if buttonBack!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    setCurrentScreen(mainMenuScreen)
                }
            }
            gameMgr.lastInput = nil
        }
        
        // tutorials screen updates
        if currentScreen === tutorialScreen {
            // check user input -- back button goes to the main menu
            if gameMgr.lastInput != nil {
                if buttonPrev!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    if tutIndex > 0 {
                        tutIndex -= 1
                    }
                    tutorialLayer.meshes.removeAll()
                    tutorialLayer.meshes.append(tutMesh[tutIndex]!)
                }
                if buttonNext!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    if tutIndex < tutorialImages-1 {
                        tutIndex += 1
                    }
                    tutorialLayer.meshes.removeAll()
                    tutorialLayer.meshes.append(tutMesh[tutIndex]!)
                }
                if buttonClose!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    setCurrentScreen(mainMenuScreen)
                }
            }
            gameMgr.lastInput = nil
        }
        
        // pause screen updates
        if currentScreen === pauseScreen {
            if gameMgr.lastInput != nil {
                if buttonBack!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    // get back to the game as it was
                    currentScreen = gameScreen
                }
                if buttonMainMenu!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    if !gameMgr.multiplayer && gameMgr.bot == nil {
                        // for ZEN mode submit the combined score
                        multiMgr.reportScoreToGameCenter(score: gameMgr.leftScore + gameMgr.rightScore)
                        // for ZEN mode show the leaderboard
                        multiMgr.presentGameCenterLeaderboard()
                    }
                    // quit the game and go to the main menu
                    setCurrentScreen(mainMenuScreen)
                }
                if buttonToggleMusic!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    // toggle the music
                    if SoundManager.shared.isBackgroundMusicEnabled {
                        if let index = pauseButtonsLayer.meshes.firstIndex(where: { $0 === checkMusic }) {
                            pauseButtonsLayer.meshes[index] = uncheckMusic!
                        }
                    } else {
                        if let index = pauseButtonsLayer.meshes.firstIndex(where: { $0 === uncheckMusic }) {
                            pauseButtonsLayer.meshes[index] = checkMusic!
                        }
                    }
                    
                    SoundManager.shared.toggleBackgroundMusic()
                }
                if buttonToggleEffects!.tappedInside(point: getGameXY(fromPoint: gameMgr.lastInput!)) {
                    // toggle the music
                    if SoundManager.shared.isSoundEffectsEnabled {
                        if let index = pauseButtonsLayer.meshes.firstIndex(where: { $0 === checkEffects }) {
                            pauseButtonsLayer.meshes[index] = uncheckEffects!
                        }
                    } else {
                        if let index = pauseButtonsLayer.meshes.firstIndex(where: { $0 === uncheckEffects }) {
                            pauseButtonsLayer.meshes[index] = checkEffects!
                        }
                    }
                    
                    SoundManager.shared.toggleSoundEffects()
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

