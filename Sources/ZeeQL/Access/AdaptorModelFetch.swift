//
//  AdaptorModelFetch.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Wraps queries which do schema reflection on the database.
 *
 * This protocol is used by adaptors to implement the user facing API, do not
 * directly use it. Instead check out the methods provided by `Adaptor` and/or
 * `AdaptorChannel`.
 */
public protocol AdaptorModelFetch {
  
  var channel : AdaptorChannel { get }

  func fetchModel() throws -> Model
  
  func fetchModelTag() throws -> ModelTag
  
  /**
   * Check whether the schema changed since the tag which is being passed in.
   * If it didn't change, return nil, if it did change, return the new tag.
   */
  func didChangeSinceModelTag(_ tag: ModelTag?) throws -> ModelTag?


  // MARK: - Old-style reflection methods
  
  func describeModelWithTableNames(_ names: [ String ], tagged: Bool) throws
       -> Model

  func describeSequenceNames() throws -> [ String ]
  func describeDatabaseNames() throws -> [ String ]
  func describeTableNames()    throws -> [ String ]
  func describeEntityWithTableName(_ table: String) throws -> Entity
}

public extension AdaptorModelFetch { // default imp
  
  // MARK: - Model fetch
  
  public func fetchModel() throws -> Model {
    // simple version first. We may be able to do better :-)
    // TODO: include in Entity whether it was a view
    // Note: Looks like we cannot UNION PRAGMA table_info statements.
    
    let didOpenTX = !channel.isTransactionInProgress
    if didOpenTX { try channel.begin() }
    
    let model : Model
    do {
      let tableNames = try describeTableNames()
      model = try describeModelWithTableNames(tableNames, tagged: true)
    }
    catch {
      if didOpenTX { try? channel.rollback() } // throw the other error
      throw error
    }
    
    if didOpenTX { try channel.rollback() }
    
    model.connectRelationships()
    
    return model
  }
  
  /**
   * Check whether the schema changed since the tag which is being passed in.
   * If it didn't change, return nil, if it did change, return the new tag.
   */
  public func didChangeSinceModelTag(_ tag: ModelTag?) throws
              -> ModelTag?
  {
    // the idea behind this is that sometimes there may be a faster way to
    // compare partial tags.
    guard let tag = tag else { return try fetchModelTag() }
    let currentTag = try fetchModelTag()
    if tag.isEqual(to: currentTag) { return nil }
    return currentTag
  }
  
  // MARK: - Old-style reflection methods
  
  func describeModelWithTableNames(_ names : [ String ]) throws -> Model {
    return try describeModelWithTableNames(names, tagged: true)
  }

  public func describeModelWithTableNames(_ names : [ String ],
                                          tagged  : Bool = true) throws -> Model
  {
    let didOpenTX = !channel.isTransactionInProgress
    if didOpenTX { try channel.begin() }
    
    let model : Model
    do {
      let entities   = try names.map {
        try describeEntityWithTableName($0)
      }
      if tagged {
        let tag = try fetchModelTag()
        model = Model(entities: entities, tag: tag)
      }
      else {
        model = Model(entities: entities)
      }
    }
    catch {
      if didOpenTX {
        try? channel.rollback() // throw the other error
      }
      throw error
    }
    
    if didOpenTX {
      try channel.rollback()
    }
    
    return model
  }
  
}
