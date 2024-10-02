//
//  UIMeshes.swift
//  ZapZap
//
//  Created by apple on 05.09.2024.
//

import Foundation
import Metal
import simd

class ButtonMesh: Mesh {
    private var halfWidth: Float
    private var halfHeight: Float
    
    init(innerWidth: Float, innerHeight: Float, borderWidth: Float, u1: Float, v1: Float, u2: Float, v2: Float) {
        let (vertices, indices) = ButtonMesh.generateVerticesAndIndices(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: u1, v1: v1, u2: u2, v2: v2)

        // initialize button sizes
        self.halfWidth = innerWidth / 2.0 + borderWidth
        self.halfHeight = innerHeight / 2.0 + borderWidth
        
        // Call the Mesh initializer with generated vertices and indices
        super.init(vertices: vertices, indices: indices, primitiveType: .triangle)
    }
    
    // Helper function to generate vertices and indices
    static func generateVerticesAndIndices(innerWidth: Float, innerHeight: Float, borderWidth: Float, u1: Float, v1: Float, u2: Float, v2: Float) -> ([Float], [UInt16]) {
        let innerHalfWidth = innerWidth / 2.0
        let innerHalfHeight = innerHeight / 2.0
        let outerHalfWidth = innerHalfWidth + borderWidth
        let outerHalfHeight = innerHalfHeight + borderWidth
        
        let uMid = u1 + (u2 - u1) / 2.0
        let vMid = v1 + (v2 - v1) / 2.0
        
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        // Top-left corner
        addQuadVertices(vertices: &vertices, x: -outerHalfWidth + borderWidth / 2.0, y: outerHalfHeight - borderWidth / 2.0, width: borderWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(u1, v1), uvBottomRight: SIMD2<Float>(uMid, vMid))
        
        // Top side
        addQuadVertices(vertices: &vertices, x: 0, y: outerHalfHeight - borderWidth / 2.0, width: innerWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(uMid, v1), uvBottomRight: SIMD2<Float>(uMid, vMid))
        
        // Top-right corner
        addQuadVertices(vertices: &vertices, x: outerHalfWidth - borderWidth / 2.0, y: outerHalfHeight - borderWidth / 2.0, width: borderWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(uMid, v1), uvBottomRight: SIMD2<Float>(u2, vMid))
        
        // Left side
        addQuadVertices(vertices: &vertices, x: -outerHalfWidth + borderWidth / 2.0, y: 0, width: borderWidth, height: innerHeight,
                        uvTopLeft: SIMD2<Float>(u1, vMid), uvBottomRight: SIMD2<Float>(uMid, vMid))
        
        // Center piece
        addQuadVertices(vertices: &vertices, x: 0, y: 0, width: innerWidth, height: innerHeight,
                        uvTopLeft: SIMD2<Float>(uMid, vMid), uvBottomRight: SIMD2<Float>(uMid, vMid))
        
        // Right side
        addQuadVertices(vertices: &vertices, x: outerHalfWidth - borderWidth / 2.0, y: 0, width: borderWidth, height: innerHeight,
                        uvTopLeft: SIMD2<Float>(uMid, vMid), uvBottomRight: SIMD2<Float>(u2, vMid))
        
        // Bottom-left corner
        addQuadVertices(vertices: &vertices, x: -outerHalfWidth + borderWidth / 2.0, y: -outerHalfHeight + borderWidth / 2.0, width: borderWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(u1, vMid), uvBottomRight: SIMD2<Float>(uMid, v2))
        
        // Bottom side
        addQuadVertices(vertices: &vertices, x: 0, y: -outerHalfHeight + borderWidth / 2.0, width: innerWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(uMid, vMid), uvBottomRight: SIMD2<Float>(uMid, v2))
        
        // Bottom-right corner
        addQuadVertices(vertices: &vertices, x: outerHalfWidth - borderWidth / 2.0, y: -outerHalfHeight + borderWidth / 2.0, width: borderWidth, height: borderWidth,
                        uvTopLeft: SIMD2<Float>(uMid, vMid), uvBottomRight: SIMD2<Float>(u2, v2))
        
        // Generate indices for all 9 quads
        let quadCount = vertices.count / 5 / 4 // Number of quads
        for i in 0..<quadCount {
            let baseIndex = UInt16(i * 4)
            indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2, baseIndex + 2, baseIndex + 3, baseIndex])
        }
        
        return (vertices, indices)
    }
    
    // Helper function to add a quad's vertices and UV coordinates
    private static func addQuadVertices(vertices: inout [Float], x: Float, y: Float, width: Float, height: Float,
                                        uvTopLeft: SIMD2<Float>, uvBottomRight: SIMD2<Float>) {
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        
        // Define the vertices for the quad
        vertices.append(contentsOf: [
            x - halfWidth, y - halfHeight, 0, uvTopLeft.x, uvBottomRight.y,  // Bottom-left
            x + halfWidth, y - halfHeight, 0, uvBottomRight.x, uvBottomRight.y, // Bottom-right
            x + halfWidth, y + halfHeight, 0, uvBottomRight.x, uvTopLeft.y,  // Top-right
            x - halfWidth, y + halfHeight, 0, uvTopLeft.x, uvTopLeft.y   // Top-left
        ])
    }
    
    // function to create a new "lit" button with texcoords 11/16, 7/8, 12/16, 8/8
    static func createLitButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 11.0/16.0, v1: 7.0/8.0, u2: 12.0/16.0, v2: 8.0/8.0)
    }
    
    // function to create a new "unlit" button with texcoords 11/16, 4/8, 12/16, 5/8
    static func createUnlitButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 11.0/16.0, v1: 4.0/8.0, u2: 12.0/16.0, v2: 5.0/8.0)
    }
    
    // function to create a new "red" button with texcoords 11/16, 3/8, 12/16, 4/8
    static func createRedButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 11.0/16.0, v1: 3.0/8.0, u2: 12.0/16.0, v2: 4.0/8.0)
    }
    
    // function to create a new "thin outline" button with texcoords 4/8, 5/8, 0/4, 1/4
    static func createThinOutlineButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 4.0/8.0, v1: 0.0/4.0, u2: 5.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "thick outline" button with texcoords 6/8, 7/8, 0/4, 1/4
    static func createThickOutlineButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 6.0/8.0, v1: 0.0/4.0, u2: 7.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "pause" button with texcoords 0/8, 1/8, 0/4, 1/4
    static func createPauseButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 0.0/8.0, v1: 0.0/4.0, u2: 1.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "coffee" button with texcoords 1/8, 2/8, 0/4, 1/4
    static func createCoffeeButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 1.0/8.0, v1: 0.0/4.0, u2: 2.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "back" button with texcoords 2/8, 3/8, 0/4, 1/4
    static func createBackButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 2.0/8.0, v1: 0.0/4.0, u2: 3.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "front" button with texcoords 3/8, 2/8, 0/4, 1/4
    static func createFrontButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 3.0/8.0, v1: 0.0/4.0, u2: 2.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "switch" button with texcoords 3/8, 4/8, 0/4, 1/4
    static func createSwitchButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 3.0/8.0, v1: 0.0/4.0, u2: 4.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "uncheck" button with texcoords 4/8, 5/8, 0/4, 1/4
    static func createUncheckButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 4.0/8.0, v1: 0.0/4.0, u2: 5.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "check" button with texcoords 5/8, 6/8, 0/4, 1/4
    static func createCheckButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 5.0/8.0, v1: 0.0/4.0, u2: 6.0/8.0, v2: 1.0/4.0)
    }

    // function to create a new "cancel" button with texcoords 7/8, 8/8, 0/4, 1/4
    static func createCancelButton(innerWidth: Float, innerHeight: Float, borderWidth: Float) -> ButtonMesh {
        return ButtonMesh(innerWidth: innerWidth, innerHeight: innerHeight, borderWidth: borderWidth, u1: 7.0/8.0, v1: 0.0/4.0, u2: 8.0/8.0, v2: 1.0/4.0)
    }

    // function to check whether input point is inside the button or not
    func tappedInside(point: SIMD2<Float>) -> Bool {
        let x = (point.x)
        let y = (point.y)
        if x > position.x - halfWidth && x < position.x + halfWidth &&
            y > position.y - halfHeight && y < position.y + halfHeight {
            return true
        } else {
            return false
        }
    }
}

