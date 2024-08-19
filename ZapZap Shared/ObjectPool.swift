//
//  ObjectPool.swift
//  ZapZap
//
//  Created by apple on 08.08.2024.
//

import Foundation

// Poolable - protocol for classes that you want to put in ObjectPools

protocol Poolable {
    var available: Bool { get set }
    init()
    func resetToUnused()
}

// ObjectPool - pre-allocate, get, release
// made to reuse objects instead of allocating and deallocating them

class ObjectPool<T: Poolable> {
    private var availableObjects: [T] = []
    private let factory: () -> T
    
    init(factory: @escaping () -> T, preAllocate: Int = 0) {
        self.factory = factory
        preallocate(count: preAllocate)
    }
    
    private func preallocate(count: Int) {
        for _ in 0..<count {
            var obj = factory()
            obj.available = true
            availableObjects.append(obj)
        }
    }
    
    func getObject() -> T {
        if var object = availableObjects.first(where: { $0.available }) {
            object.available = false
            return object
        } else {
            var newObject = factory()
            newObject.available = false
            availableObjects.append(newObject)
//            print("enlarging pool ", availableObjects.count)
            return newObject
        }
    }
    
    func releaseObject(_ object: T) {
        object.resetToUnused()
    }
}

// Useful static object pools
class AnimationPools {
    static let rotateAnimationPool = ObjectPool<RotateAnimation>(factory: { RotateAnimation() }, preAllocate: 10)
    static let particleAnimationPool = ObjectPool<ParticleAnimation>(factory: { ParticleAnimation() }, preAllocate: 50)
    static let fallAnimationPool = ObjectPool<FallAnimation>(factory: { FallAnimation() }, preAllocate: 50)
    static let freezeFrameAnimationPool = ObjectPool<FreezeFrameAnimation>(factory: { FreezeFrameAnimation() }, preAllocate: 10)
    static let particlePool = ObjectPool<Particle>(factory: { Particle() }, preAllocate: 1000)
}
