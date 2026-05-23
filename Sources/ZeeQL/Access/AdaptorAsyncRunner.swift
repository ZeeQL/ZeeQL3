//
//  AdaptorAsyncRunner.swift
//  ZeeQL
//
//  Created by Helge Hess on 12/04/2026.
//  Copyright © 2026 ZeeZide GmbH. All rights reserved.
//

#if swift(>=5.5)
import Foundation // for OperationQueue
#if canImport(Synchronization)
import Synchronization
#endif

/**
 * A thing that can run blocking database operations in the background, could
 * be a GCD queue, an OperationQueue or a NIOFileSystem.
 *
 * This is used by the async/await wrappers to perform operations off the main
 * thread pool.
 *
 * The type itself is unconditionally available so it can be stored / passed
 * on older OS; only the ``run(_:)`` requirement is gated on macOS 10.15+
 * (since it's `async`).
 */
public protocol AdaptorAsyncRunner: Sendable {

  /**
   * Execute a throwing closure on a background thread suitable for
   * blocking database I/O, and return the result.
   */
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  func run<R>(_ operation: @Sendable @escaping () throws -> R) async throws -> R
    where R: Sendable
}

/**
 * An ``AdaptorAsyncRunner`` using an `OperationQueue`.
 *
 * Using OperationQueue to limit the number of concurrent tasks, so that we have
 * no thread explosion.
 * On servers, you'd probably want to configure and own runner, because the
 * shared runner has a max of 4 concurrent ops, which may be too little
 * (though you may want to use a NIOFileSystem/Macro backed runner on servers).
 */
public struct OperationQueueAdaptorRunner: AdaptorAsyncRunner {

  public static let shared = OperationQueueAdaptorRunner()

  public let queue: OperationQueue

  @inlinable
  public init(maxConcurrentOperations: Int = 4,
              qualityOfService: QualityOfService = .default)
  {
    let q                         = OperationQueue()
    q.name                        = "de.zeezide.zeeql.async"
    q.qualityOfService            = qualityOfService
    q.maxConcurrentOperationCount = maxConcurrentOperations
    self.queue = q
  }

  @inlinable
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  public func run<R>(_ operation: @Sendable @escaping () throws -> R)
    async throws -> R
    where R: Sendable
  {
    try await withCheckedThrowingContinuation { c in
      queue.addOperation {
        do    { c.resume(returning: try operation()) }
        catch { c.resume(throwing:  error)           }
      }
    }
  }
}


#if canImport(Synchronization)
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
private let _runnerMutex : Mutex<any AdaptorAsyncRunner>
                         = Mutex(OperationQueueAdaptorRunner.shared)
#endif
#if compiler(>=5.10)
nonisolated(unsafe)
private var _runner: any AdaptorAsyncRunner = OperationQueueAdaptorRunner.shared
#else
private var _runner: any AdaptorAsyncRunner = OperationQueueAdaptorRunner.shared
#endif

public extension Adaptor {

  /**
   * Default async runner. Thread safe i `Mutex` is available, otherwise not.
   * Rather set the runner once at process startup, before any adaptor is
   * created.
   */
  var asyncRunner : any AdaptorAsyncRunner {
    get {
      #if canImport(Synchronization)
      if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, *) {
        return _runnerMutex.withLock { $0 }
      }
      #endif
      return _runner
    }
    set {
      #if canImport(Synchronization)
      if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, *) {
        _runnerMutex.withLock { $0 = newValue }
        return
      }
      #endif
      _runner = newValue
    }
  }
}

#endif
