//
//  GameViewController.swift
//  ZapZap iOS
//
//  Created by apple on 19.07.2024.
//

import UIKit
import MetalKit
import Metal

class GameViewController: UIViewController {

    var renderer: Renderer!
    var gameManager: GameManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }

        Renderer.device = MTLCreateSystemDefaultDevice()
        guard let defaultDevice = Renderer.device else {
            print("Metal is not supported")
            return
        }

        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black

        if #available(iOS 15.0, *) {
            if let currentLayer = mtkView.layer as? CAMetalLayer {
                currentLayer.device = defaultDevice
                currentLayer.pixelFormat = .rgba16Float
                currentLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                currentLayer.wantsExtendedDynamicRangeContent = true
            }
        }

        // must initialize gamemanager somewhere
        gameManager = GameManager()

        guard let newRenderer = Renderer(metalKitView: mtkView, gameManager: gameManager) else {
            print("Renderer cannot be initialized")
            return
        }

        newRenderer.viewController = self
        renderer = newRenderer
        gameManager.renderer = newRenderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // start the music
        if Renderer.isHalloween {
            SoundManager.shared.setAmbience(named: "haloween")
        }
        SoundManager.shared.playBackgroundMusic(filename: "IttyBitty")
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first {
            let scaleFactor = view.contentScaleFactor
            let touchLocation = CGPoint(x: touch.location(in: view).x * scaleFactor,
                                        y: touch.location(in: view).y * scaleFactor)
            gameManager.notifyInput(at: touchLocation)
        }
    }
}
