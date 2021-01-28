//
//  AdaptorQueryType.swift
//  ZeeQL
//
//  Created by Helge Hess on 01/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Objects you can throw SQL queries against. Those are usually `AdaptorChannel`
 * objects, but the `Adaptor` itself is one too (it automatically opens a
 * channel for you and runs the query).
 */
public protocol AdaptorQueryType { // TBD: betta name
  
  // MARK: - Raw Queries

  /**
   * Execute the SQL and call the result callback for every record returned.
   *
   * TODO: document use of attributes.
   *
   * Note: there is a set of convenience methods for this.
   */
  func querySQL(_ sql: String, _ optAttrs : [ Attribute ]?,
                cb: ( AdaptorRecord ) throws -> Void) throws
  
  /**
   * Execute the SQL, throw away any tuples returned. But return the number of
   * affected rows.
   *
   * Usually used statements used to modify database content, like INSERT,
   * UPDATE or CREATE TABLE.
   */
  @discardableResult
  func performSQL(_ sql: String) throws -> Int
  
}

public extension AdaptorQueryType {
  
  /**
   * Execute the SQL with the given attributes and return the results as an
   * array of `AdaptorRecord`s.
   *
   * TODO: document use of attributes.
   */
  @inlinable
  func querySQL(_ sql: String, _ optAttrs: [ Attribute ]?)
         throws -> [ AdaptorRecord ]
  {
    var results = [ AdaptorRecord ]()
    try querySQL(sql, optAttrs) { results.append($0) }
    return results
  }
  
  /**
   * Execute the raw SQL and return the results as an array of `AdaptorRecord`s.
   */
  @inlinable
  func querySQL(_ sql: String) throws -> [ AdaptorRecord ] {
    var results = [ AdaptorRecord ]()
    try querySQL(sql, nil) { results.append($0) }
    return results
  }

  /**
   * Execute the raw SQL and call the result callback for every record returned.
   */
  @inlinable
  func querySQL(_ sql: String, cb: ( AdaptorRecord ) throws -> Void) throws {
    try querySQL(sql, nil, cb: cb)
  }
}


// MARK: - Typed SQL queries

public extension AdaptorQueryType { // typed SQL queries
  // Well, yes, I think we need to create one function for each argument count
  // :->
  
  /**
   * Select columns in a type-safe way.
   *
   * Example, note how the type is derived from what the closure expects:
   *
   *     adaptor.select("SELECT name, count FROM pets") {
   *       (name : String, count : Int?) in
   *       print("\(name): #\(count)")
   *     }
   */
  @inlinable
  func select<T0>(_ sql: String, cb : ( T0 ) throws -> Void) throws
        where T0 : AdaptorQueryColumnRepresentable
  {
    try querySQL(sql) { result in
      try cb(try T0.fromAdaptorQueryValue(result[0]))
    }
  }
  
  @inlinable
  func select<T0, T1>(_ sql: String, cb : ( T0, T1 ) throws -> Void) throws
        where T0 : AdaptorQueryColumnRepresentable,
              T1 : AdaptorQueryColumnRepresentable
  {
    try querySQL(sql) { result in
      try cb(try T0.fromAdaptorQueryValue(result[0]),
             try T1.fromAdaptorQueryValue(result[1]))
    }
  }
  
  @inlinable
  func select<T0, T1, T2>(_ sql: String,
                          cb : ( T0, T1, T2 ) throws -> Void) throws
        where T0 : AdaptorQueryColumnRepresentable,
              T1 : AdaptorQueryColumnRepresentable,
              T2 : AdaptorQueryColumnRepresentable
  {
    try querySQL(sql) { result in
      try cb(try T0.fromAdaptorQueryValue(result[0]),
             try T1.fromAdaptorQueryValue(result[1]),
             try T2.fromAdaptorQueryValue(result[2]))
    }
  }
  
  @inlinable
  func select<T0, T1, T2, T3>(_ sql: String,
                              cb: ( T0, T1, T2, T3 ) throws -> Void) throws
        where T0 : AdaptorQueryColumnRepresentable,
              T1 : AdaptorQueryColumnRepresentable,
              T2 : AdaptorQueryColumnRepresentable,
              T3 : AdaptorQueryColumnRepresentable
  {
    try querySQL(sql) { result in
      try cb(try T0.fromAdaptorQueryValue(result[0]),
             try T1.fromAdaptorQueryValue(result[1]),
             try T2.fromAdaptorQueryValue(result[2]),
             try T3.fromAdaptorQueryValue(result[3]))
    }
  }
  
  @inlinable
  func select<T0, T1, T2, T3, T4>(_ sql: String,
                                  cb: ( T0, T1, T2, T3, T4 ) throws -> Void)
        throws
        where T0 : AdaptorQueryColumnRepresentable,
              T1 : AdaptorQueryColumnRepresentable,
              T2 : AdaptorQueryColumnRepresentable,
              T3 : AdaptorQueryColumnRepresentable,
              T4 : AdaptorQueryColumnRepresentable
  {
    try querySQL(sql) { result in
      try cb(try T0.fromAdaptorQueryValue(result[0]),
             try T1.fromAdaptorQueryValue(result[1]),
             try T2.fromAdaptorQueryValue(result[2]),
             try T3.fromAdaptorQueryValue(result[3]),
             try T4.fromAdaptorQueryValue(result[4]))
    }
  }
  
  // TODO: someone else pleaze :-)


  // MARK: - And return typed based variants
  
  @inlinable
  func select<T0>(_ sql: String) throws -> [ T0 ]
        where T0 : AdaptorQueryColumnRepresentable
  {
    var records = [ T0 ]()
    try querySQL(sql) { result in
      records.append(try T0.fromAdaptorQueryValue(result[0]))
    }
    return records
  }
  
  @inlinable
  func select<T0, T1>(_ sql: String) throws -> [ ( T0, T1 ) ]
        where T0 : AdaptorQueryColumnRepresentable,
              T1 : AdaptorQueryColumnRepresentable
  {
    var records = [ ( T0, T1 ) ]()
    try querySQL(sql) { result in
      records.append(
        ( try T0.fromAdaptorQueryValue(result[0]),
          try T1.fromAdaptorQueryValue(result[1]) ) )
    }
    return records
  }
  
}

public extension AdaptorQueryType {
  
  @inlinable
  func fetchOne<T0>(_ sql: String) throws -> T0
         where T0 : AdaptorQueryColumnRepresentable
  {
    var optResult : T0? = nil
    
    try querySQL(sql) { result in
      optResult = try T0.fromAdaptorQueryValue(result[0])
    }
    
    guard let result = optResult else {
      throw AdaptorChannelError.RecordNotFound
    }
    return result
  }
}
