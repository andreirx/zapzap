//
//  GameBoardLogic.swift
//  ZapZap
//
//  Created by apple on 23.07.2024.
//

import Foundation

enum Connection: UInt8 {
    case animating = 4
    case none = 3
    case ok = 2
    case right = 1
    case left = 0
}

class Tile {
    // Using 4-bit representation for connections
    var connections: UInt8
    
    init(connections: UInt8) {
        // Ensure only the lower 4 bits are used
        self.connections = connections & 0x0F
    }
    
    func rotate() {
        var rVal = connections << 1
        rVal = (rVal & 0x0F) | (rVal >> 4)
        // Ensure only the lower 4 bits are used
        connections = rVal & 0x0F
    }
    
    func hasConnection(direction: Direction) -> Bool {
        return (connections & direction.rawValue) != 0
    }
}

struct Direction: OptionSet {
    let rawValue: UInt8
    
    static let right = Direction(rawValue: 1 << 0) // 0001
    static let up    = Direction(rawValue: 1 << 1) // 0010
    static let left  = Direction(rawValue: 1 << 2) // 0100
    static let down  = Direction(rawValue: 1 << 3) // 1000
}

class GameBoard {
    let width: Int
    let height: Int
    var connections: [[Tile?]]
    var connectMarkings: [[Connection]]
    var leftPinsConnect: Int = 0
    var rightPinsConnect: Int = 0
    
    private var missingLinks: Int = 0
    private var newElements: Int = 0
    private var missingLinkElements: Int = 0
    
    init(width: Int, height: Int, missingLinks: Int) {
        self.width = width
        self.height = height
        self.missingLinks = missingLinks
        self.connections = Array(repeating: Array(repeating: nil, count: width), count: height)
        self.connectMarkings = Array(repeating: Array(repeating: .none, count: width), count: height)
        self.resetTable(percentMissingLinks: missingLinks)
    }
    
    func setTile(at x: Int, y: Int, tile: Tile) {
        connections[x][y] = tile
    }
    
    func expandConnectionsMarkings(cx: Int, cy: Int, ctype: Direction, marker: Connection) {
        // recursive until you get out of the board or you get to animating tiles
        guard cx >= 0, cy >= 0, cx < width, cy < height,
              marker.rawValue <= Connection.none.rawValue else {
            return
        }
        // also stop recursion when you encounter the marker
        // this means this tile has already been visited
        if connectMarkings[cx][cy] == marker {
            return
        }
        
        // mark the current tile with the current marker, then explore around
        // check wire going from this tile, and wire coming from the other tile, to mark a connection
        if let currentTile = connections[cx][cy], currentTile.hasConnection(direction: ctype) {
            connectMarkings[cx][cy] = marker
            
            // look from this tile to the left
            // then look from the left tile to the right (which is this tile)
            if currentTile.hasConnection(direction: .left) {
                expandConnectionsMarkings(cx: cx - 1, cy: cy, ctype: .right, marker: marker)
            }
            // look from this tile upwards
            // then look from the upper tile downwards (which is this tile)
            if currentTile.hasConnection(direction: .up) {
                expandConnectionsMarkings(cx: cx, cy: cy - 1, ctype: .down, marker: marker)
            }
            // look from this tile to the right
            // then look from the right tile to the left (which is this tile)
            if currentTile.hasConnection(direction: .right) {
                expandConnectionsMarkings(cx: cx + 1, cy: cy, ctype: .left, marker: marker)
            }
            // look from this tile downwards
            // then look from the bottom tile upwards (which is this tile)
            if currentTile.hasConnection(direction: .down) {
                expandConnectionsMarkings(cx: cx, cy: cy + 1, ctype: .up, marker: marker)
            }
        }
    }
    
    func checkConnections() -> Int {
        var rVal = 0
        leftPinsConnect = 0
        rightPinsConnect = 0
        
        // reset all info
        for j in 0..<height {
            for i in 0..<width {
                // clear the markings except for animations
                // although it's hard to pretend the tile is not there...
                // TODO - clear this up
                if connectMarkings[i][j] != .animating
                {
                    connectMarkings[i][j] = .none
                }
            }
        }
        
        // check connections from the rightmost pins
        for j in 0..<height {
            if let tile = connections[width - 1][j], tile.hasConnection(direction: .right) {
                // count one more connecting pin from this side
                // (RIGHT)
                rightPinsConnect += 1
                
                expandConnectionsMarkings(cx: width - 1, cy: j, ctype: .right, marker: .right)
            }
        }
        
        // check connections from the leftmost pins
        for j in 0..<height {
            if let tile = connections[0][j], tile.hasConnection(direction: .left) {
                // count one more connecting pin from this side
                // (LEFT)
                leftPinsConnect += 1
                
                // if you encounter markings from the right, start marking as "ok"
                // which means both sides connect
                // otherwise continue marking as "left"
                if connectMarkings[0][j] == .right || connectMarkings[0][j] == .ok {
                    expandConnectionsMarkings(cx: 0, cy: j, ctype: .left, marker: .ok)
                } else {
                    expandConnectionsMarkings(cx: 0, cy: j, ctype: .left, marker: .left)
                }
                
                // if any of the connections are "ok" then both sides connect
                if connectMarkings[0][j] == .ok {
                    rVal = 1
                }
            }
        }
        
        // if both sides connect, compute a score
        // in fact you can use leftPinsConnect and rightPinsConnect for this
        
        return rVal
    }
    
    func getNewElement() -> UInt8 {
        var k = UInt8((Int.random(in: 1...15)))
        newElements += 1
        
        if (100 * missingLinkElements / newElements) > missingLinks {
            // if there are too many "missing links"
            // make sure the next onw is NOT one
            while k == 1 || k == 2 || k == 4 || k == 8 {
                k = UInt8((Int.random(in: 1...15)))
            }
        }
        
        if k == 1 || k == 2 || k == 4 || k == 8 {
            missingLinkElements += 1
        }
        
        return k
    }
    
    func resetTable(percentMissingLinks: Int) {
        missingLinks = percentMissingLinks
        newElements = 0
        missingLinkElements = 0
        
        for i in 0..<width {
            for j in 0..<height {
                let newConnection = getNewElement()
                connections[j][i] = Tile(connections: newConnection)
                connectMarkings[i][j] = .none
            }
        }
    }
}
