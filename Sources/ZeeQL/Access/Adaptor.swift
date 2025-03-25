//
//  Adaptor.swift
//  ZeeQL
//
//  Created by Helge Hess on 21/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.URL

/**
 * An adaptor is a low level object coordinating access to a specific database.
 * It is similar to a JDBC or ODBC driver.
 * 
 * In user level code you usually work with `Database` and `DataSource` objects,
 * but you can drop down to the Adaptor level if you need/want more direct
 * access to the databases.
 *
 * ### Available Adaptors
 *
 * Various concrete implementations of the protocol are provided, and anyone can
 * write additional ones.
 *
 * ZeeQL itself comes with the `SQLite3Adaptor` for accessing SQLite3 databases.
 * We also provide adaptors for PostgreSQL on top of libpq (ZeeQL3PG package)
 * as well as adaptors for the database support in the Apache Portable Runtime
 * (APR).
 *
 * ### Channels
 *
 * To run queries, an adaptor creates `AdaptorChannel` objects. Those represent
 * a single connection to the backend database. An adaptor can also maintain a
 * pool of those channel objects.
 *
 * ### AdaptorQueryType
 *
 * Finally Adaptor itself is (like `AdaptorChannel`) an `AdaptorQueryType`.
 * Which means, you can queries directly against the adaptor. The adaptor will
 * then auto-create and release channels from the pool.
 *
 * Example, type-safe query:
 * ```swift
 * try adaptor.select("SELECT name, count FROM pets") {
 *   (name : String, count : Int) in
 *   print("\(name): #\(count)")
 * }
 * ```
 *
 * ### AdaptorDataSource
 *
 * If you don't want object mapping, but still want to use datasources, you
 * can use an `AdaptorDataSource`. With or without an attached entity. See
 * the `AdaptorDataSource` class for more info.
 *
 * AdaptorDataSources return raw `AdaptorRecord` objects.
 *
 * Example:
 * ```swift
 * let ds = AdaptorDataSource(adaptor: adaptor, entity: entity)
 * let user = ds.findBy(id: 9999)
 * ```
 */
public protocol Adaptor : AnyObject, AdaptorQueryType, EquatableType {
  
  func openChannelFromPool() throws -> AdaptorChannel
  func openChannel()         throws -> AdaptorChannel
  func releaseChannel(_ channel: AdaptorChannel)

  var expressionFactory      : SQLExpressionFactory         { get }
  var synchronizationFactory : SchemaSynchronizationFactory { get }
  var model                  : Model?                       { get set }
  
  func fetchModel()    throws -> Model
  func fetchModelTag() throws -> ModelTag
  
  var log : ZeeQLLogger { get }
  
  var url : URL? { get }
}

public extension Adaptor {
  
  @inlinable
  func openChannelFromPool() throws -> AdaptorChannel {
    return try openChannel()
  }
  @inlinable
  func releaseChannel(_ channel: AdaptorChannel) {}
  
  @inlinable
  var log : ZeeQLLogger { return globalZeeQLLogger }
  
  @inlinable
  var url : URL? { return nil }
  
  /// Note: Returns a stateful object (a new one every time it is accessed).
  @inlinable
  var synchronizationFactory : SchemaSynchronizationFactory {
    return SchemaSynchronizationFactory(adaptor: self)
  }
  
  @inlinable
  func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Adaptor else { return false }
    return other.isEqual(to: self)
  }
  @inlinable
  func isEqual(to other: Self) -> Bool {
    return self === other
  }
  
  @inlinable
  static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}


// MARK: - Adaptor as a AdaptorQueryType

public extension Adaptor { // AdaptorQueryType
  
  @inlinable
  func querySQL(_ sql: String, _ optAttrs : [ Attribute ]? = nil,
                cb: ( AdaptorRecord ) throws -> Void) throws
  {
    let ch = try openChannelFromPool()
    defer { releaseChannel(ch) }
    
    try ch.querySQL(sql, optAttrs, cb: cb)
  }
  
  @inlinable
  @discardableResult
  func performSQL(_ sql: String) throws -> Int {
    let ch = try openChannelFromPool()
    defer { releaseChannel(ch) }
    
    return try ch.performSQL(sql)
  }
  
}
