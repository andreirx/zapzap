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

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
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

        renderer = newRenderer
        renderer = newRenderer
        gameManager.renderer = newRenderer
        gameManager.createTiles()
        renderer.addTilesFromGameManager()
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first {
            let touchLocation = touch.location(in: view)
            gameManager.notifyInput(at: touchLocation)
        }
    }
}
