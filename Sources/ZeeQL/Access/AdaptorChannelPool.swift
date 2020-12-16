//
//  AdaptorChannelPool.swift
//  ZeeQL3
//
//  Copyright © 2018-2020 ZeeZide GmbH. All rights reserved.
//

import Foundation

public protocol AdaptorChannelPool {

  func grab() -> AdaptorChannel?
  func add(_ channel: AdaptorChannel)

}

// Those are not great, but OKayish.
// The expiration queue probably forks an own thread.

/**
 * A naive pool which keeps open just a single connection.
 *
 * Usage:
 *
 *     private var pool = SingleConnectionPool(maxAge: 10)
 *
 *     open func openChannelFromPool() throws -> AdaptorChannel {
 *       return pool.grab() ?? (try openChannel())
 *     }
 *
 *     open func releaseChannel(_ channel: AdaptorChannel) {
 *       guard let pgChannel = channel as? PostgreSQLAdaptorChannel else {
 *         assertionFailure("unexpected channel type!")
 *         return
 *       }
 *       guard pgChannel.handle != nil else { return } // closed
 *
 *       pool.add(pgChannel)
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
  private let expirationQueue = DispatchQueue(label: "de.zeezide.zeeql.expire")
  private var entry           : Entry? // here we just pool one :-)
  private var gc              : DispatchWorkItem?
  
  public init(maxAge: TimeInterval) {
    self.maxAge = maxAge
    assert(maxAge > 0)
  }
  
  public func grab() -> AdaptorChannel? {
    lock.lock(); defer { entry = nil; lock.unlock() }
    return entry?.connection
  }
  
  public func add(_ channel: AdaptorChannel) {
    guard !channel.isTransactionInProgress else {
      globalZeeQLLogger.warn("releasing a channel w/ an open TX:", channel)
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
      globalZeeQLLogger.info("adding channel to pool:", channel)
    }
    else {
      globalZeeQLLogger.info("did not add channel to pool:", channel)
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

/**
 * A naive pool which keeps open a number of connections.
 *
 * Usage:
 *
 *     private var pool = SimpleAdaptorChannelPool(maxAge: 10)
 *
 *     open func openChannelFromPool() throws -> AdaptorChannel {
 *       return pool.grab() ?? (try openChannel())
 *     }
 *
 *     open func releaseChannel(_ channel: AdaptorChannel) {
 *       guard let pgChannel = channel as? PostgreSQLAdaptorChannel else {
 *         assertionFailure("unexpected channel type!")
 *         return
 *       }
 *       guard pgChannel.handle != nil else { return } // closed
 *       pool.add(pgChannel)
 *     }
 *
 */
public final class SimpleAdaptorChannelPool: AdaptorChannelPool {
  
  struct Entry {
    let releaseDate : Date
    let connection  : AdaptorChannel
    
    var age : TimeInterval { return -(releaseDate.timeIntervalSinceNow) }
  }

  private let maxSize         : Int
  private let maxAge          : TimeInterval
  private let lock            = NSLock()
  private let expirationQueue = DispatchQueue(label: "de.zeezide.zeeql.expire")
  private var entries         = [ Entry ]()
  private var gc              : DispatchWorkItem?
  
  public init(maxSize: Int, maxAge: TimeInterval) {
    assert(maxSize >= 0)
    assert(maxSize > 0 && maxSize < 128) // weird size
    assert(maxAge  > 0)
    self.maxSize = max(0, maxSize)
    self.maxAge  = maxAge
  }
  
  public func grab() -> AdaptorChannel? {
    lock.lock()
    let entry = entries.popLast()
    lock.unlock()
    return entry?.connection
  }
  
  public func add(_ channel: AdaptorChannel) {
    guard !channel.isTransactionInProgress else {
      globalZeeQLLogger.warn("release a channel w/ an open TX:", channel)
      assertionFailure("releasing a channel w/ an open TX")
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
    let doAdd = entries.count < maxSize
    if doAdd {
      let entry = Entry(releaseDate: Date(), connection: channel)
      entries.append(entry)
    }
    lock.unlock()
    
    if doAdd {
      globalZeeQLLogger.info("adding channel to pool:", channel)
    }
    else {
      globalZeeQLLogger.info("did not add channel to pool:", channel)
    }
    
    expirationQueue.async {
      if self.gc != nil { return } // already running
      
      let now = Date()
      self.lock.lock()
      let hasContent = !self.entries.isEmpty
      let maxAge = self.entries.reduce(0) {
        max($0, -($1.releaseDate.timeIntervalSince(now)))
      }
      self.lock.unlock()
      
      guard hasContent else { return } // no entries
      
      if maxAge > self.maxAge {
        return self.expire()
      }

      let left = self.maxAge - maxAge
      self.gc = DispatchWorkItem(block: self.expire)
      self.expirationQueue
        .asyncAfter(deadline: .now() + .milliseconds(Int(left * 1000)),
                    execute: self.gc!)
    }
  }
  private func expire() { // Q: expirationQueue
    let rerun  : Bool
    var maxAge : TimeInterval = 0
    var stats  : ( expired: Int, alive: Int ) = ( 0, 0 )
    do {
      lock.lock(); defer { lock.unlock() }
      
      let count = entries.count
      
      if count > 0 {
        let now = Date()
        for ( idx, entry ) in entries.enumerated().reversed() {
          let age = -(entry.releaseDate.timeIntervalSince(now))
          if age >= self.maxAge {
            entries.remove(at: idx)
            stats.expired += 1
          }
          else {
            maxAge = max(maxAge, age)
            stats.alive += 1
          }
        }
        
        rerun = !entries.isEmpty
      }
      else {
        rerun = false
      }
    }

    if stats.expired > 0 && stats.alive > 0 {
      globalZeeQLLogger
        .info("pool expired #\(stats.expired) alive #\(stats.alive)",
              rerun ? "rerun" : "done")
    }
      
    if rerun {
      let left = self.maxAge - maxAge
      gc = DispatchWorkItem(block: self.expire)
      expirationQueue
        .asyncAfter(deadline: .now() + .milliseconds(Int(left * 1000)),
                    execute: self.gc!)
    }
    else {
      gc = nil
    }
  }
}
