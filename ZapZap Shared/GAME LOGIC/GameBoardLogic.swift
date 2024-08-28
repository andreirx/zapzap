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

enum AnimationMarking: UInt8 {
    case falling = 2
    case rotating = 1
    case none = 0
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
    var animationMarkings: [[AnimationMarking]]

    var leftPinsConnect: Int = 0
    var leftConquered: Int = 0
    var rightPinsConnect: Int = 0
    var rightConquered: Int = 0
    
    private var missingLinks: Int = 0
    private var newElements: Int = 0
    private var missingLinkElements: Int = 0
    
    init(width: Int, height: Int, missingLinks: Int) {
        self.width = width
        self.height = height
        self.missingLinks = missingLinks
        self.connections = Array(repeating: Array(repeating: nil, count: width), count: height)
        self.connectMarkings = Array(repeating: Array(repeating: .none, count: width), count: height)
        self.animationMarkings = Array(repeating: Array(repeating: .none, count: width), count: height)
        self.resetTable(percentMissingLinks: missingLinks)
    }
    
    func setTile(at x: Int, y: Int, tile: Tile) {
        connections[x][y] = tile
    }

    // internal function used in checkConnections
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
    
    // method to paint connecting tiles from the left, from the right
    // and then both sides if applicable
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
                expandConnectionsMarkings(cx: width - 1, cy: j, ctype: .right, marker: .right)
            }
        }
        
        // check connections from the leftmost pins
        for j in 0..<height {
            if let tile = connections[0][j], tile.hasConnection(direction: .left) {
                // if you encounter markings from the right, start marking as "ok"
                // which means both sides connect
                // otherwise continue marking as "left"
                if connectMarkings[0][j] == .right || connectMarkings[0][j] == .ok {
                    expandConnectionsMarkings(cx: 0, cy: j, ctype: .left, marker: .ok)
                } else {
                    expandConnectionsMarkings(cx: 0, cy: j, ctype: .left, marker: .left)
                }
            }
        }
        // see if both sides connect and count the "score"
        for j in 0..<height {
            if let tile = connections[0][j], tile.hasConnection(direction: .left) {
                // if any of the connections are "ok" then both sides connect
                if connectMarkings[0][j] == .ok {
                    rVal = 1
                    // count one more connecting pin from this side
                    // (LEFT)
                    leftPinsConnect += 1
                }
            }
            if let tile = connections[width - 1][j], tile.hasConnection(direction: .right) {
                // count one more connecting pin from this side
                // (RIGHT)
                if connectMarkings[width - 1][j] == .ok {
                    rightPinsConnect += 1
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
    
    // method to remove "ok" tiles and shift down - to call when zapping
    // - but don't touch the markings, not yet!
    // - because they are needed to apply the same algorithm on the tileQuads
    func removeAndShiftConnectingTiles() {
        //
        for x in 0..<width {
            var shiftedItems = 0 // remember how many tiles we shift as we go
            // because we will have to compensate the copying position by this number
            for y in (0..<height).reversed() {
                if connectMarkings[x][y] == .ok {
                    // Shift tiles above down
                    if y >= 1 {
                        for shiftY in (1...y).reversed() {
                            // remember to compensate copying position by shiftedItems
                            connections[x][shiftY + shiftedItems] = connections[x][shiftY + shiftedItems - 1]
                        }
                    }
                    // Create new tile at the top
                    connections[x][0] = Tile(connections: getNewElement())
                    // one more disappeared so far
                    shiftedItems += 1
                }
                // make new ones
                for y in (0..<shiftedItems).reversed() {
                    connections[x][y] = Tile(connections: getNewElement())
                }
            }
//            print("GBL column ", x, " shifted: ", shiftedItems, " connections")
        }
    }
    
    // another method that has to be called IN SYNC and useing the SAME ALGORITHM as
    // what you will be doing to the graphics tiles
    func bombTable(ati: Int, atj: Int) {
        // make sure we're not bombing outside
        if ati < 0 || ati >= width || atj < 0 || atj >= height {
            return
        }
        // will remove the tiles around ati, atj
        // will "fall down" the ones above
        // will generate new ones from above
        var starti = ati - 2
        var endi = ati + 2
        var startj = atj - 2
        var endj = atj + 2
        // clip
        if starti < 0 {
            starti = 0
        }
        if endi >= width {
            endi = width - 1
        }
        if startj < 0 {
            startj = 0
        }
        if endj >= height {
            endj = height - 1
        }
        // shift down and generate
        for x in starti..<endi {
            var shiftedItems = 0 // remember how many tiles we shift as we go
            // because we will have to compensate the copying position by this number
            // now do it for each column, bottom-up
            for y in (startj..<endj).reversed() {
                // Shift tiles above down
                if y >= 1 {
                    for shiftY in (1...y).reversed() {
                        // remember to compensate copying position by shiftedItems
                        connections[x][shiftY + shiftedItems] = connections[x][shiftY + shiftedItems - 1]
                    }
                }
                // Create new tile at the top
                connections[x][0] = Tile(connections: getNewElement())
                // one more disappeared so far
                shiftedItems += 1
            }
            // make new ones
            for y in (0..<shiftedItems).reversed() {
                connections[x][y] = Tile(connections: getNewElement())
            }
        }
    }

    // method to reset the entire table
    func resetTable(percentMissingLinks: Int) {
        missingLinks = percentMissingLinks
        newElements = 0
        missingLinkElements = 0
        
        for i in 0..<width {
            for j in 0..<height {
                let newConnection = getNewElement()
                connections[i][j] = Tile(connections: newConnection)
                connectMarkings[i][j] = .none
            }
        }
    }
}
