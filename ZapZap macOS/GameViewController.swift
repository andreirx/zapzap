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

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
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

        guard let newRenderer = Renderer(metalKitView: mtkView, gameManager: gameManager) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        gameManager.renderer = newRenderer
        gameManager.createTiles()
        renderer.addTilesFromGameManager()
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let location = event.locationInWindow
        let convertedLocation = view.convert(location, from: nil)
        gameManager.notifyInput(at: convertedLocation)
    }
}
