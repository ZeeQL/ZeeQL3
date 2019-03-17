//
//  SQLite3Adaptor.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.TimeInterval
import CSQLite3

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
      if readonly        { self = .readOnly }
      else if autocreate { self = .autocreate }
      else               { self = .readWrite }
    }
    
    var flags : Int32 {
      switch self {
        case .readOnly:   return SQLITE_OPEN_READONLY
        case .readWrite:  return SQLITE_OPEN_READWRITE
        case .autocreate: return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
      }
    }
  }
  
  let path     : String
  let openMode : OpenMode
  let options  : RuntimeOptions
  
  public init(_ path: String, autocreate: Bool = false, readonly: Bool = false,
              options: RuntimeOptions = RuntimeOptions())
  {
    self.path     = path
    self.openMode = OpenMode(autocreate: autocreate, readonly: readonly)
    self.options  = options
  }
  
  
  // MARK: - Support
  
  public var expressionFactory : SQLExpressionFactory
                               = SQLite3ExpressionFactory.shared
  public var model             : Model? = nil
  
  
  // MARK: - Channels

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
  
  public func releaseChannel(_ channel: AdaptorChannel) {
    // not maintaing a pool
  }
  
  
  // MARK: - Model
  
  public func fetchModel() throws -> Model {
    let channel = try openChannelFromPool()
    defer { releaseChannel(channel) }
    
    return try SQLite3ModelFetch(channel: channel).fetchModel()
  }
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

