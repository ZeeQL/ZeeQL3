//
//  DatabaseContext.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * DatabaseContext
 *
 * This is an object store which works on top of Database. It just manages the
 * database channels to fetch objects.
 *
 * E.g. it can be wrapped in an `ObjectTrackingContext` which serves as an
 * object uniquer.
 */
public class DatabaseContext : ObjectStore, SmartDescription {
  
  public enum Error : Swift.Error {
    case FetchSpecificationHasUnresolvedBindings(FetchSpecification)
    case TODO
  }

  public let database : Database

  public init(_ database: Database) {
    self.database = database
  }
  
  /* fetching objects */
  
  // public struct TypedFetchSpecification<Object: DatabaseObject>

  public func objectsWith<T>(fetchSpecification fs : TypedFetchSpecification<T>,
                             in tc                 : ObjectTrackingContext,
                             _ cb                  : ( T ) -> Void) throws
  {
    if fs.requiresAllQualifierBindingVariables {
      if let keys = fs.qualifier?.bindingKeys, !keys.isEmpty {
        throw Error.FetchSpecificationHasUnresolvedBindings(fs)
      }
    }
    
    let ch = TypedDatabaseChannel<T>(database: database)
    try ch.selectObjectsWithFetchSpecification(fs, tc)
    
    while let o : T = ch.fetchObject() {
      cb(o)
    }
  }

  @inlinable
  public func objectsWithFetchSpecification<O>(
    _  fetchSpecification : FetchSpecification,
    in    trackingContext : ObjectTrackingContext,
    _               yield : ( O ) throws -> Void
  ) throws
    where O: DatabaseObject
  {
    if fetchSpecification.requiresAllQualifierBindingVariables {
      if let keys = fetchSpecification.qualifier?.bindingKeys, !keys.isEmpty {
        throw Error.FetchSpecificationHasUnresolvedBindings(fetchSpecification)
      }
    }
    
    let ch = TypedDatabaseChannel<O>(database: database)
    try ch
      .selectObjectsWithFetchSpecification(fetchSpecification, trackingContext)
    
    while let o = ch.fetchObject() {
      assert(o is O)
      guard let typed = o as? O else { continue }
      try yield(typed)
    }
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    ms += " \(database)"
  }
}
