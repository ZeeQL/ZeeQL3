//
//  Adaptor+Async.swift
//  ZeeQL
//
//  Created by Helge Hess on 12/04/2026.
//  Copyright © 2026 ZeeZide GmbH. All rights reserved.
//

#if swift(>=5.5)

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public extension Adaptor {

  /**
   * Run SQL, return AdaptorRecord's.
   *
   * - Parameters:
   *   - sql:      The SQL query to execute.
   *   - optAttrs: Optional ``Attribute``s describing the result columns.
   *               When `nil`, the column metadata is inferred from the
   *               statement.
   * - Throws:     Any error raised by the underlying ``AdaptorChannel``.
   * - Returns:    The fetched rows as an array of ``AdaptorRecord``.
   */
  @inlinable
  func querySQL(_ sql: String, _ optAttrs: [ Attribute ]? = nil) async throws
       -> [ AdaptorRecord ]
  {
    try await asyncRunner.run {
      try self.querySQL(sql, optAttrs) as [ AdaptorRecord ]
    }
  }

  /**
   * Run non-query SQL statement (e.g. `INSERT`, `UPDATE`, `DELETE`, DDL).
   *
   * Runs on the adaptor's ``Adaptor/asyncRunner``.
   *
   * - Parameter sql: The SQL statement to execute.
   * - Throws:        Any error raised by the underlying ``AdaptorChannel``.
   * - Returns:       The number of rows affected by the statement.
   */
  @inlinable
  @discardableResult
  func performSQL(_ sql: String) async throws -> Int {
    try await asyncRunner.run { try self.performSQL(sql) as Int }
  }

  /**
   * Execute a SQL query that returns a typed single-column result.
   *
   * - Parameter sql: The SQL query to execute.
   * - Throws:        Any error raised by the underlying ``AdaptorChannel``,
   *                  or a conversion error if a value can't be mapped to `T0`.
   * - Returns:       An array of `T0` values, one per result row.
   */
  @inlinable
  func select<T0>(_ sql: String) async throws -> [ T0 ]
    where T0: AdaptorQueryColumnRepresentable
  {
    try await asyncRunner.run { try self.select(sql) as [ T0 ] }
  }

  /**
   * Execute a SQL query that returns a typed two-column result.
   *
   * - Parameter sql: The SQL query to execute.
   * - Throws:        Any error raised by the underlying ``AdaptorChannel``,
   *                  or a conversion error if a value can't be mapped.
   * - Returns:       An array of `(T0, T1)` tuples, one per result row.
   */
  @inlinable
  func select<T0, T1>(_ sql: String) async throws -> [ ( T0, T1 ) ]
    where T0: AdaptorQueryColumnRepresentable,
          T1: AdaptorQueryColumnRepresentable
  {
    try await asyncRunner.run { try self.select(sql) as [ ( T0, T1 ) ] }
  }

  /**
   * Execute a block with a channel checked out from the pool. The channel is
   * automatically returned to the pool when the closure returns (or throws).
   *
   * Example:
   * ```swift
   * let names = try await adaptor.withChannel { ch in
   *   try ch.querySQL("SELECT name FROM person")
   * }
   * ```
   *
   * Channel is not released into the pool if an exception got thrown. So if the
   * body intends to throw and keep the channel, it needs to do that manually.
   *
   * - Parameter body: A closure that receives the ``AdaptorChannel`` and
   *                   returns a value.
   * - Throws:         Anything thrown by `body`, or by opening the channel.
   * - Returns:        The value returned by `body`.
   */
  @inlinable
  @discardableResult
  func withChannel<R>(_ body: @Sendable @escaping
                        (any AdaptorChannel) throws -> R) async throws -> R
    where R: Sendable
  {
    try await asyncRunner.run {
      let channel = try self.openChannelFromPool()
      do {
        let result = try body(channel)
        self.releaseChannel(channel)
        return result
      }
      catch {
        try? channel.rollback() // ch will be GC'ed?
        throw error
      }
    }
  }

  /**
   * Execute a block within a database transaction.
   *
   * The channel is checked out from the pool, a transaction is begun, the
   * closure is invoked with the channel, and the transaction is committed.
   * If the closure throws, the transaction is rolled back before the error
   * is re-raised. A failing rollback is suppressed in favor of the
   * original error.
   *
   * Example:
   * ```swift
   * try await adaptor.transaction { channel in
   *   try channel.performSQL("INSERT INTO pets VALUES (1, 'Cat')")
   *   try channel.performSQL("INSERT INTO pets VALUES (2, 'Dog')")
   * }
   * ```
   *
   * Releases the channel on successful commit, or if the rollback succeeded on
   * error.
   *
   * - Parameter body: A closure that performs work inside the transaction.
   * - Throws:         Anything thrown by `body`, or by `BEGIN` / `COMMIT`
   *                   on the channel.
   * - Returns:        The value returned by `body`, after `COMMIT` succeeds.
   */
  @inlinable
  @discardableResult
  func transaction<R>(_ body: @Sendable @escaping
                                (any AdaptorChannel) throws -> R)
         async throws -> R
         where R: Sendable
  {
    try await asyncRunner.run {
      let ch = try self.openChannelFromPool()
      try ch.begin()
      do {
        let result = try body(ch)
        try ch.commit()
        self.releaseChannel(ch)
        return result
      }
      catch {
        do {
          try ch.rollback()
          self.releaseChannel(ch)
        }
        catch {} // do not release channel
        throw error
      }
    }
  }
}

#endif
