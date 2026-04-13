//
//  AsyncOperation.swift
//  PiGuard
//
//  Created by Brad Root on 5/26/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

class AsyncOperation: Operation, @unchecked Sendable {
    enum State: String {
        case isReady, isExecuting, isFinished
    }

    override var isAsynchronous: Bool {
        return true
    }

    private let stateLock = NSLock()
    private var _state = State.isReady

    var state: State {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        set {
            let old: State
            let new: State = newValue
            stateLock.lock()
            old = _state
            _state = newValue
            stateLock.unlock()
            willChangeValue(forKey: old.rawValue)
            willChangeValue(forKey: new.rawValue)
            didChangeValue(forKey: old.rawValue)
            didChangeValue(forKey: new.rawValue)
        }
    }

    override var isExecuting: Bool {
        return state == .isExecuting
    }

    override var isFinished: Bool {
        return state == .isFinished
    }

    override func start() {
        guard !isCancelled else {
            state = .isFinished
            return
        }

        state = .isExecuting
        main()
    }
}
