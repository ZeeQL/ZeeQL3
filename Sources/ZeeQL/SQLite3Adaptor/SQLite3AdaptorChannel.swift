//
//  SQLite3AdaptorChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

#if canImport(Foundation)
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.Decimal
import struct Foundation.Locale
import struct Foundation.URL
import struct Foundation.UUID
import func Foundation.NSDecimalString
#endif

#if canImport(SQLite3)
  import SQLite3
#elseif canImport(CSQLite3)
  import CSQLite3
#endif

#if os(Linux)
  import func Glibc.strdup
  import func Glibc.free
  import func Glibc.malloc
#else
  import func Darwin.strdup
  import func Darwin.free
  import func Darwin.malloc
#endif

public enum SQLite3AdaptorChannelError: Swift.Error {

  case cannotPrepareSQL(Int32, String?)
  case rowFetchFailed  (Int32, String?)
  case bindFailed      (Int32, String?, SQLExpression.BindVariable)
}

private let decimalLocale = Locale(identifier: "en_US_POSIX")

open class SQLite3AdaptorChannel : AdaptorChannel {

  open   var log               : ZeeQLLogger
  public let expressionFactory : SQLExpressionFactory
  public let handle            : OpaquePointer
  final  let closeHandle       : Bool
  final  let doLogSQL          : Bool
  final  let doLogBindValues   : Bool
  final  let deferForeignKeys  : Bool?
  
  init(adaptor: Adaptor, handle: OpaquePointer, closeHandle: Bool = true) {
    self.log               = adaptor.log
    self.expressionFactory = adaptor.expressionFactory
    self.handle            = handle
    self.closeHandle       = closeHandle
    let options            = (adaptor as? SQLite3Adaptor)?.options
    self.doLogSQL          = options?.logSQL ?? false
    self.doLogBindValues   = doLogSQL && (options?.logBindValues ?? false)
    self.deferForeignKeys  = options?.deferForeignKeys
    
    // TODO: busy handler?
    // sqlite3_busy_timeout()
    // sqlite3_busy_handler()
  }
  
  deinit {
    if closeHandle {
      sqlite3_close(handle)
    }
  }

  // MARK: - Raw Queries
  
  func fetchRows(_ stmt     : OpaquePointer?,
                 _ optAttrs : [ Attribute ]? = nil,
                 cb         : ( AdaptorRecord ) throws -> Void) throws
  {
    var schema     : AdaptorRecordSchema?
      // assumes uniform results, which should be so
    
    if let attrs = optAttrs {
      schema = AdaptorRecordSchemaWithAttributes(attrs)
    }
    
    repeat {
      let rc = sqlite3_step(stmt)
      guard rc == SQLITE_ROW else {
        if rc == SQLITE_DONE { break }
        throw SQLite3AdaptorChannelError.rowFetchFailed(rc, message(for: rc))
      }
      
      let colCount = sqlite3_column_count(stmt)
      
      // build schema if no attributes have been provided
      if schema == nil {
        // TBD: Do we want to build attributes? Probably not, too expensive for
        //      simple stuff.
        var names = [ String ]()
        names.reserveCapacity(Int(colCount))
        
        for colIdx in 0..<colCount {
          if let attrs = optAttrs, Int(colIdx) < attrs.count,
            let col = attrs[Int(colIdx)].columnName
          {
            names.append(col)
          }
          else if let name = sqlite3_column_name(stmt, colIdx) {
            names.append(String(cString: name))
          }
          else {
            names.append("col[\(colIdx)]")
          }
        }
        schema = AdaptorRecordSchemaWithNames(names)
      }
      
      var values = [ Any? ]()
      values.reserveCapacity(Int(colCount))
      
      for colIdx in 0..<colCount {
        let attr : Attribute?
        if let attrs = optAttrs, Int(colIdx) < attrs.count {
          attr = attrs[Int(colIdx)]
        }
        else {
          attr = nil
        }
        
        let value = valueIn(row: stmt, column: colIdx, attribute: attr)
        values.append(value)
      }
      
      let record = AdaptorRecord(schema: schema!, values: values)
      try cb(record)
    }
    while true
  }
  
  func logSQL(_ sql: String) {
    if doLogSQL { log.log("SQL:", sql) }
  }
  
  public func querySQL(_ sql: String, _ optAttrs : [ Attribute ]?,
                       cb: ( AdaptorRecord ) throws -> Void) throws
  {
    logSQL(sql)
    
    var stmt : OpaquePointer? = nil
    
    let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
    guard rc == SQLITE_OK else {
      throw SQLite3AdaptorChannelError.cannotPrepareSQL(rc, message(for: rc))
    }
    defer { if let stmt = stmt { sqlite3_finalize(stmt) } }

    try fetchRows(stmt, optAttrs, cb: cb)
  }
  
  @discardableResult
  public func performSQL(_ sql: String) throws -> Int {
    try querySQL(sql) { record in } // of no interest, loop until DONE
    return Int(sqlite3_changes(handle))
  }
  
  
  // MARK: - Values
  
  open func valueIn(row: OpaquePointer?, column: Int32,
                    attribute: Attribute?) -> Any?
  {
    guard let stmt = row else { return nil }
    
    // TODO: consider attribute! (e.g. for date, valueType in attr, if set)
    
    let type = sqlite3_column_type(stmt, column)
    switch type {
      case SQLITE_NULL:
        return Optional<String>.none // TODO: consider value type of attr
      
      case SQLITE_INTEGER:
        return sqlite3_column_int64(stmt, column)
      
      case SQLITE_TEXT:
        if let cstr = sqlite3_column_text(stmt, column) {
          return String(cString: cstr)
        }
        else {
          return Optional<String>.none
        }
      
      case SQLITE_FLOAT:
        return sqlite3_column_double(stmt, column)
      
      case SQLITE_BLOB:
        let count = sqlite3_column_bytes(stmt, column)
        #if canImport(Foundation)
        if count == 0 { return Data() }
        if let blob = sqlite3_column_blob(stmt, column) {
          return Data(bytes: blob, count: Int(count))
        }
        else {
          return Optional<Data>.none
        }
        #else
        if count == 0 { return [ UInt8 ]() }
        if let blob = sqlite3_column_blob(stmt, column) {
          return [ UInt8 ](bytes: blob, count: Int(count))
        }
        else {
          return Optional<[ UInt8 ]>.none
        }
        #endif
      
      default:
        if let cstr = sqlite3_column_text(stmt, column) {
          return String(cString: cstr)
        }
        else {
          return Optional<String>.none
      }
    }
  }
  
  
  // MARK: - Model Queries
  
  public func evaluateQueryExpression(_ sqlexpr  : SQLExpression,
                                      _ optAttrs : [ Attribute ]?,
                                      result: ( AdaptorRecord ) throws -> Void)
                throws
  {
    if sqlexpr.bindVariables.isEmpty {
      /* expression has no binds, perform a plain SQL query */
      return try querySQL(sqlexpr.statement, optAttrs, cb: result)
    }

    logSQL(sqlexpr.statement)
    
    var stmt : OpaquePointer? = nil
    
    let rc = sqlite3_prepare_v2(handle, sqlexpr.statement, -1, &stmt, nil)
    guard rc == SQLITE_OK, stmt != nil else {
      throw SQLite3AdaptorChannelError.cannotPrepareSQL(rc, message(for: rc))
    }
    defer { if let stmt = stmt { sqlite3_finalize(stmt) } }
    
    let pool = Pool()
    try withExtendedLifetime(pool) {
      try bindVariables(sqlexpr.bindVariables, to: stmt!, pool: pool)
      
      // query was OK, collect results
      try fetchRows(stmt, optAttrs, cb: result)
    }
  }

  public func evaluateUpdateExpression(_ sqlexpr: SQLExpression) throws -> Int {
    if sqlexpr.bindVariables.isEmpty {
      /* expression has no binds, perform a plain SQL query */
      return try performSQL(sqlexpr.statement)
    }
    
    logSQL(sqlexpr.statement)
    
    var stmt : OpaquePointer? = nil
    
    let rc = sqlite3_prepare_v2(handle, sqlexpr.statement, -1, &stmt, nil)
    guard rc == SQLITE_OK else {
      throw SQLite3AdaptorChannelError.cannotPrepareSQL(rc, message(for: rc))
    }
    defer { if let stmt = stmt { sqlite3_finalize(stmt) } }
    
    let pool = Pool()
    try withExtendedLifetime(pool) {
      try bindVariables(sqlexpr.bindVariables, to: stmt!, pool: pool)
    
      try fetchRows(stmt) { row in }  // of no interest, loop until DONE
    }
    
    return Int(sqlite3_changes(handle))
  }
  
  open func insertRow(_ row: AdaptorRow, _ entity: Entity, refetchAll: Bool)
              throws -> AdaptorRow
  {
    let expr = expressionFactory.insertStatementForRow(row, entity)
    
    // In SQLite we need a transaction for the refetch
    var didOpenTx = false
    if refetchAll && !isTransactionInProgress {
      try begin()
      didOpenTx = true
    }
    
    let result : AdaptorRow
    do {
      guard try evaluateUpdateExpression(expr) == 1 else {
        throw AdaptorError.operationDidNotAffectOne
      }

      let pkey : AdaptorRow
      if let epkey = entity.primaryKeyForRow(row), !epkey.isEmpty {
        // already had the primary key assigned
        pkey = epkey
      }
      else if let pkeys = entity.primaryKeyAttributeNames, pkeys.count == 1 {
        let lastRowId = sqlite3_last_insert_rowid(handle)
        pkey = [ pkeys[0] : lastRowId ]
      }
      else {
        throw AdaptorError.failedToGrabNewPrimaryKey(entity: entity, row: row)
      }
      
      if refetchAll {
        let q  = qualifierToMatchAllValues(pkey)
        let fs = ModelFetchSpecification(entity: entity, qualifier: q,
                                         sortOrderings: [], limit: 2)
        var rec : AdaptorRecord? = nil
        try selectAttributes(entity.attributes, fs, lock: false, entity) {
          record in
          guard rec == nil else { // multiple matched!
            throw AdaptorError.failedToRefetchInsertedRow(
                                 entity: entity, row: row)
          }
          rec = record
        }
        guard let rrec = rec else { // none matched!
          throw AdaptorError.failedToRefetchInsertedRow(
                               entity: entity, row: row)
        }
        
        result = rrec.asAdaptorRow
      }
      else {
        result = pkey
      }
    }
    catch {
      if didOpenTx { try? rollback() } // throw the other error
      didOpenTx = false
      throw error
    }
    
    if didOpenTx { try commit() }
    return result
  }
  
  func bindVariables(_ binds : [ SQLExpression.BindVariable ],
                     to stmt : OpaquePointer,
                     pool    : Pool) throws
  {
    var idx : Int32 = 0
    for variable in binds {
      idx += 1
      // if doLogSQL { log.log("  BIND[\(idx)]: \(variable)") }
      if let attr = variable.attribute {
        if doLogSQL { log.log("  BIND[\(idx)]: \(attr.name)") }
      }

      func bind(_ value: String) -> Int32 {
        guard let text = pool.pstrdup(value) else { return SQLITE_NOMEM }
        return sqlite3_bind_text(stmt, idx, text, -1, nil)
      }

      func bind<I: BinaryInteger>(_ value: I) -> Int32 {
        guard let value = Int64(exactly: value) else { return SQLITE_RANGE }
        return sqlite3_bind_int64(stmt, idx, sqlite3_int64(value))
      }

      #if canImport(Foundation)
      func bind(_ value: Data) -> Int32 {
        guard !value.isEmpty else { return sqlite3_bind_zeroblob(stmt, idx, 0) }
        guard let count = Int32(exactly: value.count) else {
          return SQLITE_TOOBIG
        }
        guard let bytes = pool.copy(value) else { return SQLITE_NOMEM }
        return sqlite3_bind_blob(stmt, idx, bytes, count, nil)
      }

      func bind(_ value: Decimal) -> Int32 {
        var value = value
        return bind(NSDecimalString(&value, decimalLocale))
      }
      #endif

      func bindAnyValue(_ value: Any?) throws -> Int32 {
        guard let value = value else {
          if doLogBindValues { log.log("      [\(idx)]> bind NULL") }
          return sqlite3_bind_null(stmt, idx)
        }
        switch value {
          case let value as String:
            if doLogBindValues {
              log.log("      [\(idx)]> bind string \"\(value)\"")
            }
            return bind(value)
          case let value as Bool:
            if doLogBindValues { log.log("      [\(idx)]> bind bool \(value)") }
            return bind(value ? 1 : 0)
          case let value as Int:
            if doLogBindValues { log.log("      [\(idx)]> bind int \(value)") }
            return bind(value)
          case let value as Int8:
            if doLogBindValues { log.log("      [\(idx)]> bind int8 \(value)") }
            return bind(value)
          case let value as Int32:
            if doLogBindValues { log.log("      [\(idx)]> bind int \(value)") }
            return bind(value)
          case let value as Int64:
            if doLogBindValues { log.log("      [\(idx)]> bind int \(value)") }
            return bind(value)
          case let value as Float:
            return sqlite3_bind_double(stmt, idx, Double(value))
          case let value as Double:
            return sqlite3_bind_double(stmt, idx, value)

          #if canImport(Foundation)
          case let value as Data:
            if doLogBindValues { log.log("      [\(idx)]> bind Data \(value)") }
            return bind(value)
          case let value as Date:
            if doLogBindValues { log.log("      [\(idx)]> bind Date \(value)") }
            return sqlite3_bind_double(stmt, idx, value.timeIntervalSince1970)
          case let value as Decimal:
            if doLogBindValues { log.log("      [\(idx)]> bind Dec. \(value)") }
            return bind(value)
          case let value as UUID:
            if doLogBindValues { log.log("      [\(idx)]> bind UUID \(value)") }
            return bind(value.uuidString)
          case let value as URL:
            if doLogBindValues { log.log("      [\(idx)]> bind URL \(value)") }
            return bind(value.absoluteString)
          #endif

          case let value as GlobalID:
            #if !GLOBALID_AS_OPEN_CLASS
            guard value.keyCount == 1 else { return SQLITE_MISMATCH }
            switch value.value {
              case .singleNil:
                if doLogBindValues { log.log("      [\(idx)]> bind NULL") }
                return sqlite3_bind_null(stmt, idx)
              case .int(let value):
                if doLogBindValues {
                  log.log("      [\(idx)]> bind int \(value)")
                }
                return bind(value)
              case .string(let value):
                if doLogBindValues {
                  log.log("      [\(idx)]> bind string \"\(value)\"") }
                return bind(value)
              case .uuid(let value):
                if doLogBindValues {
                  log.log("      [\(idx)]> bind string \"\(value)\"") }
                return bind(value.uuidString)
              case .values(let values):
                if values.count > 1 {
                  return SQLITE_MISMATCH
                }
                if let value = values.first {
                  return try bindAnyValue(value)
                }
                else {
                  return SQLITE_MISMATCH
                }
            }
            #else
              guard let value = value as? KeyGlobalID,
                    value.keyCount == 1 else
              {
                let rc = SQLITE_MISMATCH
                throw SQLite3AdaptorChannelError
                        .bindFailed(rc, message(for: rc), variable)
              }
              return try bindAnyValue(value[0])
            #endif

          case let value as any BinaryInteger:
            if doLogBindValues { log.log("      [\(idx)]> bind int \(value)") }
            return bind(value)

          default:
            return SQLITE_MISMATCH
        }
      }
      
      // TODO: Add a protocol to do this?
      let rc = try bindAnyValue(variable.value)
      
      guard rc == SQLITE_OK else {
        throw SQLite3AdaptorChannelError.bindFailed(rc, message(for: rc),
                                                    variable)
      }
    }
  }
  

  // MARK: - Transactions
  
  public var isTransactionInProgress : Bool {
    return sqlite3_get_autocommit(handle) == 0
  }
  
  public func begin() throws {
    guard !isTransactionInProgress
     else { throw AdaptorChannelError.transactionInProgress }
    
    try performSQL("BEGIN TRANSACTION;")

    do {
      if let deferForeignKeys {
        let value = deferForeignKeys ? "on" : "off"
        try performSQL("PRAGMA defer_foreign_keys = \(value)")
      }
    }
    catch {
      try? rollback()
      throw error
    }
  }
  public func commit() throws {
    try performSQL("COMMIT TRANSACTION;")
  }
  public func rollback() throws {
    try performSQL("ROLLBACK TRANSACTION;")
  }
  
  
  // MARK: - Reflection
  // TBD: this should rather be part of the adaptor? No need to subclass just
  //      to run custom SQL
  
  public func describeSequenceNames() throws -> [ String ] {
    return try SQLite3ModelFetch(channel: self).describeSequenceNames()
  }
  
  public func describeDatabaseNames() throws -> [ String ] {
    return try SQLite3ModelFetch(channel: self).describeDatabaseNames()
  }
  public func describeTableNames() throws -> [ String ] {
    return try SQLite3ModelFetch(channel: self).describeTableNames()
  }

  public func describeEntityWithTableName(_ table: String) throws -> Entity? {
    return try SQLite3ModelFetch(channel: self)
                 .describeEntityWithTableName(table)
  }
  
  
  
  // MARK: - Persistent Bind Parameters
  
  final class Pool {
    
    final var pointers = [ UnsafeMutableRawPointer ]()
    
    func pstrdup(_ s: String) -> UnsafeMutablePointer<Int8>? {
      guard let p = strdup(s) else { return nil }
      pointers.append(p)
      return p
    }

    func copy(_ data: Data) -> UnsafeMutableRawPointer? {
      guard let pointer = malloc(data.count) else { return nil }
      data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self),
                     count: data.count)
      pointers.append(pointer)
      return pointer
    }
    
    deinit {
      for ptr in pointers {
        free(ptr)
      }
    }
  }
  

  // MARK: - Errors
  
  func message(for error: Int32) -> String? {
    guard error != SQLITE_OK else { return nil }
    guard let cmsg = sqlite3_errmsg(handle) else { return nil }
    return String(cString: cmsg)
  }
}

extension SQLite3AdaptorChannel: CustomStringConvertible {
  
  public var description: String {
    var ms = "<SQLiteChannel: \(handle)"
    if !closeHandle { ms += " not-closing" }
    ms += ">"
    return ms
  }
}

#if swift(>=5.5)
extension SQLite3AdaptorChannelError: Sendable {}
#endif
