//
//  SQLite3AdaptorChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.Data
import CSQLite3

#if os(Linux)
  import func Glibc.strdup
  import func Glibc.free
#else
  import func Darwin.strdup
  import func Darwin.free
#endif

open class SQLite3AdaptorChannel : AdaptorChannel {

  public enum Error : Swift.Error {
    case CannotPrepareSQL(Int32, String?)
    case RowFetchFailed  (Int32, String?)
    case BindFailed      (Int32, String?, SQLExpression.BindVariable)
  }

  open   var log               : ZeeQLLogger
  public let expressionFactory : SQLExpressionFactory
  public let handle            : OpaquePointer
  final  let closeHandle       : Bool
  final  let doLogSQL          = true
  
  init(adaptor: Adaptor, handle: OpaquePointer, closeHandle: Bool = true) {
    self.log               = adaptor.log
    self.expressionFactory = adaptor.expressionFactory
    self.handle      = handle
    self.closeHandle = closeHandle
    
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
        throw Error.RowFetchFailed(rc, message(for: rc))
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
      throw Error.CannotPrepareSQL(rc, message(for: rc))
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
        if let blob = sqlite3_column_blob(stmt, column) {
          let count = sqlite3_column_bytes(stmt, column)
          let data  = Data(bytes: blob, count: Int(count))
          return data
        }
        else {
          return Optional<Data>.none
        }
      
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
    guard rc == SQLITE_OK else {
      throw Error.CannotPrepareSQL(rc, message(for: rc))
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
      throw Error.CannotPrepareSQL(rc, message(for: rc))
    }
    defer { if let stmt = stmt { sqlite3_finalize(stmt) } }
    
    let pool = Pool()
    try withExtendedLifetime(pool) {
      try bindVariables(sqlexpr.bindVariables, to: stmt!, pool: pool)
    
      try fetchRows(stmt) { row in }  // of no interest, loop until DONE
    }
    
    return Int(sqlite3_changes(handle))
  }
  
  open func insertRow(_ row: AdaptorRow, _ entity: Entity?, refetchAll: Bool)
              throws -> AdaptorRow
  {
    if refetchAll && entity == nil {
      throw AdaptorError.InsertRefetchRequiresEntity
    }
    
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
        throw AdaptorError.OperationDidNotAffectOne
      }

      if let entity = entity {
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
          throw AdaptorError.FailedToGrabNewPrimaryKey(entity: entity, row: row)
        }
        
        if refetchAll {
          let q  = qualifierToMatchAllValues(pkey)
          let fs = ModelFetchSpecification(entity: entity, qualifier: q,
                                           sortOrderings: nil, limit: 2)
          var rec : AdaptorRecord? = nil
          try selectAttributes(entity.attributes, fs, lock: false, entity) {
            record in
            guard rec == nil else { // multiple matched!
              throw AdaptorError.FailedToRefetchInsertedRow(
                                   entity: entity, row: row)
            }
            rec = record
          }
          guard let rrec = rec else { // none matched!
            throw AdaptorError.FailedToRefetchInsertedRow(
                                 entity: entity, row: row)
          }
          
          result = rrec.asAdaptorRow
        }
        else {
          result = pkey
        }
      }
      else {
        // Note: we don't know the pkey w/o entity and we don't want to reflect in
        //       here
        result = row
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
    for bind in binds {
      idx += 1
      // if doLogSQL { log.log("  BIND[\(idx)]: \(bind)") }
      if let attr = bind.attribute {
        if doLogSQL { log.log("  BIND[\(idx)]: \(attr.name)") }
      }
      
      // TODO: Add a protocol to do this?
      let rc : Int32
      if let value = bind.value {
        if let value = value as? String {
          if doLogSQL { log.log("      [\(idx)]> bind string \"\(value)\"") }
          rc = sqlite3_bind_text(stmt, idx, pool.pstrdup(value), -1, nil)
        }
        else if let value = value as? SingleIntKeyGlobalID { // hacky
          if doLogSQL { log.log("      [\(idx)]> bind key \(value)") }
          rc = sqlite3_bind_int64(stmt, idx, sqlite3_int64(value.value))
        }
        else if let value = value as? Int { // TODO: Other Integers
          if doLogSQL { log.log("      [\(idx)]> bind int \(value)") }
          rc = sqlite3_bind_int64(stmt, idx, sqlite3_int64(value))
        }
        else { // TODO
          if doLogSQL { log.log("      [\(idx)]> bind other \(value)") }
          rc = sqlite3_bind_text(stmt, idx, pool.pstrdup(value), -1, nil)
        }
      }
      else {
        if doLogSQL { log.log("      [\(idx)]> bind NULL") }
        rc = sqlite3_bind_null(stmt, idx)
      }
      
      guard rc == SQLITE_OK
       else { throw Error.BindFailed(rc, message(for: rc), bind) }
    }
  }
  

  // MARK: - Transactions
  
  public var isTransactionInProgress : Bool = false
  
  public func begin() throws {
    guard !isTransactionInProgress
     else { throw AdaptorChannelError.TransactionInProgress }
    
    try performSQL("BEGIN TRANSACTION;")
    isTransactionInProgress = true
  }
  public func commit() throws {
    isTransactionInProgress = false
    try performSQL("COMMIT TRANSACTION;")
  }
  public func rollback() throws {
    isTransactionInProgress = false
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
    
    func pstrdup(_ s: String) -> UnsafeMutablePointer<Int8> {
      let p = strdup(s)! // assume it never fails ...
      pointers.append(p)
      return p
    }
    func pstrdup(_ value: Any) -> UnsafeMutablePointer<Int8> {
      return pstrdup(String(describing: value))
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
