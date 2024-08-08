//
//  ObjectPool.swift
//  ZapZap
//
//  Created by apple on 08.08.2024.
//

import Foundation

class ObjectPool<T> {
    private var availableObjects: [T] = []
    private let createObject: () -> T

    init(createObject: @escaping () -> T) {
        self.createObject = createObject
    }

    func getObject() -> T {
        if let object = availableObjects.popLast() {
            return object
        }
        return createObject()
    }

    func returnObject(_ object: T) {
        availableObjects.append(object)
    }
}
