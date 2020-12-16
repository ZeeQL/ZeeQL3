//
//  AdaptorChannelPool.swift
//  ZeeQL3
//
//  Created by Helge Heß on 16.12.20.
//  Copyright © 2020 ZeeZide GmbH. All rights reserved.
//

import Foundation

public protocol AdaptorChannelPool {

  func grab() -> AdaptorChannel?
  func add(_ channel: AdaptorChannel)

}

/**
 * A naive pool which keeps open just a single connection.
 *
 * Usage:
 *
 *     private var connectionPool = SingleConnectionPool(maxAge: 10)
 *
 *     open func openChannelFromPool() throws -> AdaptorChannel {
 *       return connectionPool.grab() ?? (try openChannel())
 *     }
 *
 *     open func releaseChannel(_ channel: AdaptorChannel) {
 *       guard let pgChannel = channel as? PostgreSQLAdaptorChannel else {
 *         assertionFailure("unexpected channel type!")
 *         return
 *       }
 *       guard pgChannel.handle != nil else { return } // closed
 *
 *       connectionPool.add(pgChannel)
 *     }
 *
 */
public final class SingleConnectionPool: AdaptorChannelPool {
  
  struct Entry {
    let releaseDate : Date
    let connection  : AdaptorChannel
    
    var age : TimeInterval { return -(releaseDate.timeIntervalSinceNow) }
  }

  private let maxAge          : TimeInterval
  private let lock            = NSLock()
  private let expirationQueue = DispatchQueue(label: "de.zeezide.zeeql.pck.expire")
  private var entry           : Entry? // here we just pool one :-)
  private var gc              : DispatchWorkItem?
  
  init(maxAge: TimeInterval) {
    self.maxAge = maxAge
  }
  
  public func grab() -> AdaptorChannel? {
    lock.lock(); defer { entry = nil; lock.unlock() }
    return entry?.connection
  }
  
  public func add(_ channel: AdaptorChannel) {
    guard !channel.isTransactionInProgress else {
      globalZeeQLLogger.warn("release a channel w/ an option TX:", channel)
      do {
        try channel.rollback()
      }
      catch {
        globalZeeQLLogger.warn("failed to rollback TX in released channel:",
                               error)
      }
      return // do not pool such
    }
    
    lock.lock()
    let doAdd = entry == nil
    if doAdd {
      entry = Entry(releaseDate: Date(), connection: channel)
    }
    lock.unlock()
    
    if doAdd {
      globalZeeQLLogger.info("adding connection to pool:", channel)
    }
    else {
      globalZeeQLLogger.info("did not add connection to pool:", channel)
    }
    
    expirationQueue.async {
      if self.gc != nil { return } // already running
      self.gc = DispatchWorkItem(block: self.expire)
      self.expirationQueue.asyncAfter(deadline: .now() + .seconds(1),
                                      execute: self.gc!)
    }
  }
  private func expire() {
    let rerun : Bool
    do {
      lock.lock(); defer { lock.unlock() }
      if let entry = entry {
        rerun = entry.age > maxAge
        if !rerun { self.entry = nil }
      }
      else { rerun = false }
    }
      
    if rerun {
      gc = DispatchWorkItem(block: self.expire)
      expirationQueue.asyncAfter(deadline: .now() + .seconds(1),
                                 execute: gc!)
    }
    else {
      gc = nil
    }
  }
}
