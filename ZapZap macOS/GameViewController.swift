//
//  GameViewController.swift
//  ZapZap macOS
//
//  Created by apple on 19.07.2024.
//

import Cocoa
import MetalKit

class GameViewController: NSViewController {

    var renderer: Renderer!
    var gameManager: GameManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        Renderer.device = MTLCreateSystemDefaultDevice()
        guard let defaultDevice = Renderer.device else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        if let currentLayer = mtkView.layer as? CAMetalLayer {
            currentLayer.device = defaultDevice
            currentLayer.pixelFormat = .rgba16Float
            currentLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            currentLayer.framebufferOnly = currentLayer.framebufferOnly
            currentLayer.contentsScale = currentLayer.contentsScale
            currentLayer.drawableSize = currentLayer.drawableSize
            currentLayer.wantsExtendedDynamicRangeContent = true
        } else {
            print("View's layer is not a CAMetalLayer")
        }

        // must initialize gamemanager somewhere
        gameManager = GameManager()
        print ("created a GameManager")

        guard let newRenderer = Renderer(metalKitView: mtkView, gameManager: gameManager) else {
            print("Renderer cannot be initialized")
            return
        }
        print ("created a Renderer")

        renderer = newRenderer
        gameManager.renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // start the music
        SoundManager.shared.playBackgroundMusic(filename: "IttyBitty")
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let location = view.convert(event.locationInWindow, from: nil)
        let scaleFactor = view.window?.backingScaleFactor ?? 1.0
        let convertedLocation = CGPoint(x: location.x * scaleFactor, y: renderer.view.drawableSize.height - location.y * scaleFactor)
        gameManager.notifyInput(at: convertedLocation)
    }
}
