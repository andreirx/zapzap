//
//  Screen.swift
//  ZapZap
//
//  Created by apple on 03.08.2024.
//

import Foundation
import MetalKit
import Metal

// // // // // // // // // // // // // // // // // // // // //
//
// Screen - generic class designed to organize layers together
//

class Screen {
    var layers: [GraphicsLayer] = []

    init() {
        // Use the static device from Renderer
        // Initialize any other properties if needed
    }

    func addLayer(_ layer: GraphicsLayer) {
        layers.append(layer)
    }

    func removeLayer(_ layer: GraphicsLayer) {
        layers.removeAll { $0 === layer }
    }

    func render(encoder: MTLRenderCommandEncoder) {
        for layer in layers {
            layer.render(encoder: encoder)
        }
    }
}
