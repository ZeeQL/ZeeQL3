//
//  SQLite3Adaptor.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/17.
//  Copyright © 2017-2020 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.TimeInterval
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
#if canImport(SQLite3)
  import SQLite3
#elseif canImport(CSQLite3)
  import CSQLite3
#endif

/**
 * The ZeeQL database adaptor for SQLite3.
 * 
 * An adaptor is a low level object coordinating access to a specific database.
 * It is similar to a JDBC or ODBC driver.
 * 
 * In user level code you usually work with `Database` and `DataSource` objects,
 * but you can drop down to the Adaptor level if you need/want more direct
 * access to the databases.
 *
 * Since SQLite3 is available on essentially all platforms, this is a standard
 * component of ZeeQL.
 *
 * The SQLite adaptor supports schema reflection using `fetchModel` (and
 * `fetchModelTag`).
 *
 * ### Adaptor creation
 *
 * Initializing the adaptor doesn't touch the filesystem/database yet. This
 * only happens when a channel is opened.
 *
 *     let adaptor = SQLite3Adaptor(url.path, autocreate: true, readonly: false,
 *                                  options: .init())
 *     try adaptor.select("SELECT name, count FROM pets") {
 *       (name : String, count : Int) in
 *       print("\(name): #\(count)")
 *     }
 *
 * The options can be used to enable things like WAL mode or auto-vacuum.
 *
 * ### Channels
 *
 * To run queries the adaptor creates `AdaptorChannel` objects. Those represent
 * a single connection to the database (i.e. a `sqlite_open`).
 *
 * ### AdaptorQueryType
 *
 * `Adaptor` itself is an `AdaptorQueryType` (like `AdaptorChannel`).
 * Which means, you can queries directly against the adaptor. The adaptor will
 * then auto-create and release channels.
 *
 * Example, type-safe query:
 *
 *     try adaptor.select("SELECT name, count FROM pets") {
 *       (name : String, count : Int) in
 *       print("\(name): #\(count)")
 *     }
 *
 * ### AdaptorDataSource
 *
 * If you don't want object mapping, but still want to use datasources, you
 * can use an `AdaptorDataSource`. With or without an attached entity. See
 * the `AdaptorDataSource` class for more info.
 *
 * `AdaptorDataSources` return raw `AdaptorRecord` objects.
 *
 * Example:
 *
 *     let ds = AdaptorDataSource(adaptor: adaptor, entity: entity)
 *     let user = ds.findBy(id: 9999)
 *
 */
open class SQLite3Adaptor : Adaptor, SmartDescription {
  
  public enum Error : Swift.Error {
    case OpenFailed(errorCode: Int32, message: String?,
                    path: String, mode: OpenMode)
  }
  
  public enum OpenMode {
    
    case readOnly
    case readWrite
    case autocreate
    
    init(autocreate: Bool = false, readonly: Bool = false) {
      if readonly        { self = .readOnly   }
      else if autocreate { self = .autocreate }
      else               { self = .readWrite  }
    }
    
    fileprivate var flags : Int32 {
      switch self {
        case .readOnly:   return SQLITE_OPEN_READONLY
        case .readWrite:  return SQLITE_OPEN_READWRITE
        case .autocreate: return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
      }
    }
  }
  
  public  let path     : String
  public  let openMode : OpenMode
  public  let options  : RuntimeOptions
  private let pool     : AdaptorChannelPool?
  
  public init(_  path    : String,
              autocreate : Bool = false, readonly: Bool = false,
              options    : RuntimeOptions = RuntimeOptions(),
              pool       : AdaptorChannelPool? = nil)
  {
    self.path     = path
    self.openMode = OpenMode(autocreate: autocreate, readonly: readonly)
    self.options  = options
    self.pool     = pool
  }
  
  /**
   * Returns a URL representing the connection info.
   *
   * Example:
   *
   *     sqlite3:///tmp/mydb.sqlite?mode=readonly
   *
   */
  public var url: URL? {
    var url    = URLComponents()
    url.scheme = "sqlite3"
    url.path   = path
    
    // TBD: runtime options
    switch openMode {
      case .readWrite: break
      case .readOnly:
        url.queryItems = [ .init(name: "mode", value: "readonly") ]
      case .autocreate:
        url.queryItems = [ .init(name: "mode", value: "autocreate") ]
    }
    return url.url
  }
  
  
  // MARK: - Support
  
  public var expressionFactory : SQLExpressionFactory
                               = SQLite3ExpressionFactory.shared
  public var model             : Model? = nil
  
  
  // MARK: - Channels

  /**
   * Open a SQLite channel and execute the SQL required for the runtime options.
   */
  open func openChannel() throws -> AdaptorChannel {
    var db : OpaquePointer? = nil
    let rc = sqlite3_open_v2(path, &db, openMode.flags, nil)
    guard rc == SQLITE_OK else {
      var errorMessage : String? = nil
      if let db = db {
        if let cmsg = sqlite3_errmsg(db) {
          errorMessage = String(cString: cmsg)
        }
        sqlite3_close(db)
      }
      
      log.trace("Could not open SQLite database:", path, "mode:", openMode,
                "error:", rc, errorMessage)
      throw AdaptorError.CouldNotOpenChannel(
        Error.OpenFailed(errorCode: rc, message: errorMessage,
                         path: path, mode: openMode)
      )
    }
    
    assert(db != nil, "Lost DB handle mid-flight?! \(self)")
    let channel = SQLite3AdaptorChannel(adaptor: self, handle: db!)
    
    if let busyTimeout = options.busyTimeout {
      // Needs to be set early, so that the PRAGMA calls do not trigger the
      // lock-issue already!
      sqlite3_busy_timeout(db, Int32(busyTimeout * 1000))
    }

    do {
      for sql in options.sqlStatements {
        guard !sql.isEmpty else { continue }
        
        try channel.performSQL(sql)
      }
    }
    catch {
      throw error
    }
    
    return channel
  }
  
  public func openChannelFromPool() throws -> AdaptorChannel {
    if let channel = pool?.grab() {
      log.info("reusing pooled channel:", channel)
      return channel
    }
    do {
      let channel = try openChannel()
      if pool != nil {
        log.info("opened new channel:", channel)
      }
      return channel
    }
    catch {
      throw error
    }
  }
  
  public func releaseChannel(_ channel: AdaptorChannel) {
    guard let pool = pool else {
      return
    }
    if let channel = channel as? SQLite3AdaptorChannel {
      log.info("releasing channel:", ObjectIdentifier(channel))
      pool.add(channel)
    }
    else {
      log.info("invalid channel type:", channel)
      assert(channel is SQLite3AdaptorChannel)
    }
  }
  
  
  // MARK: - Model
  
  /**
   * Fetches a database model based on the SQL catalog of the database.
   *
   * Note: The `FancyModelMaker` can be used to convert the Model to one with
   *       Swiftier model names.
   */
  public func fetchModel() throws -> Model {
    let channel = try openChannelFromPool()
    defer { releaseChannel(channel) }
    
    return try SQLite3ModelFetch(channel: channel).fetchModel()
  }
  /**
   * Fetches the current database 'model tag'. The model tag is an indicator
   * whether the database catalog may have changed (i.e. whether the model
   * should be rebuilt).
   */
  public func fetchModelTag() throws -> ModelTag {
    let channel = try openChannelFromPool()
    defer { releaseChannel(channel) }
    
    return try SQLite3ModelFetch(channel: channel).fetchModelTag()
  }
  
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    if !path.isEmpty { ms += " '\(path)'" }
    
    switch openMode {
      case .readOnly:   ms += " r/o"
      case .autocreate: ms += " autocreate"
      case .readWrite:  break
    }
  }


  // MARK: - Runtime Options
  
  public struct RuntimeOptions {
    // Note: values unset result in the default behavior
    
    public init() {}
    
    public enum AutoVacuumMode {
      case none, full, incremental
    }
    public enum JournalMode {
      case delete, truncate, persist, memory, wal, off
    }
    public enum JournalSizeLimit {
      case none
      case limit(Int)
    }
    public enum LockingMode {
      case normal, exclusive
    }
    public enum SyncMode {
      case off, normal, full, extra
    }
    
    public var autoVacuum             : AutoVacuumMode? = .incremental
    public var automaticIndex         : Bool?
    public var busyTimeout            : TimeInterval?
    public var fullfsync              : Bool?
    public var ignoreCheckConstraints : Bool?
    public var journalMode            : JournalMode?
    public var journalSizeLimit       : JournalSizeLimit?
    public var lockingMode            : LockingMode?
    public var deferForeignKeys       : Bool? = true
    public var foreignKeys            : Bool? = true
    public var secureDelete           : Bool?
    public var synchronous            : SyncMode?
    public var userVersion            : Int?
    public var maxPageCount           : Int?
    
    var sqlStatements : [ String ] {
      var statements = [ String ]()
      
      statements.pragma("auto_vacuum",        autoVacuum?.sqlString)
      statements.pragma("automatic_index",    automaticIndex?.sqlString)
      statements.pragma("busy_timeout",       busyTimeout?.milliseconds)
      statements.pragma("fullfsync",          fullfsync?.sqlString)
      statements.pragma("ignore_check_constraints",
                                              ignoreCheckConstraints?.sqlString)
      statements.pragma("journal_mode",       journalMode?.sqlString)
      statements.pragma("journal_size_limit", journalSizeLimit?.sqlString)
      statements.pragma("locking_mode",       lockingMode?.sqlString)
      statements.pragma("defer_foreign_keys", deferForeignKeys?.sqlString)
      statements.pragma("foreign_keys",       foreignKeys?.sqlString)
      statements.pragma("secure_delete",      secureDelete?.sqlString)
      statements.pragma("synchronous",        synchronous?.sqlString)
      statements.pragma("user_version",       userVersion)
      statements.pragma("max_page_count",     maxPageCount)
      
      return statements
    }
  }
}


// MARK: - Helpers

extension SQLite3Adaptor.RuntimeOptions.AutoVacuumMode {
  var sqlString : String {
    switch self {
      case .none:        return "NONE"
      case .full:        return "FULL"
      case .incremental: return "INCREMENTAL"
    }
  }
}

extension SQLite3Adaptor.RuntimeOptions.JournalMode {
  var sqlString : String {
    switch self {
      case .delete:   return "DELETE"
      case .persist:  return "PERSIST"
      case .truncate: return "TRUNCATE"
      case .memory:   return "MEMORY"
      case .wal:      return "WAL"
      case .off:      return "OFF"
    }
  }
}
extension SQLite3Adaptor.RuntimeOptions.JournalSizeLimit {
  var sqlString : String {
    switch self {
      case .none:             return "-1"
      case .limit(let limit): return String(limit)
    }
  }
}
extension SQLite3Adaptor.RuntimeOptions.LockingMode {
  var sqlString : String {
    switch self {
      case .normal:    return "NORMAL"
      case .exclusive: return "EXCLUSIVE"
    }
  }
}
extension SQLite3Adaptor.RuntimeOptions.SyncMode {
  var sqlString : String {
    switch self {
      case .off:    return "OFF"
      case .normal: return "NORMAL"
      case .full:   return "FULL"
      case .extra:  return "EXTRA"
    }
  }
}

fileprivate extension TimeInterval {
  var milliseconds : Int {
    return Int(self * 1000.0)
  }
}

fileprivate extension Bool {
  var sqlString : String { return self ? "on" : "off" }
}

fileprivate extension RangeReplaceableCollection
                        where Iterator.Element == String
{
  
  mutating func pragma<T>(_ name: String, _ value: T?)
                   where T: CustomStringConvertible
  {
    guard let value = value else { return }
    self.append("PRAGMA \(name) = \(value);")
  }
}

