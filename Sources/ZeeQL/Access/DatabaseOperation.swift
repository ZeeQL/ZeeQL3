//
//  DatabaseOperation.swift
//  ZeeQL3
//
//  Created by Helge Hess on 15.05.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * This is like an AdaptorOperation at a higher level. It represents an UPDATE,
 * DELETE, INSERT on a DatabaseObject. Technically this could result in multiple
 * adaptor operations.
 */
open class DatabaseOperation : SmartDescription {
  
  open var log : ZeeQLLogger = globalZeeQLLogger
  
  public typealias Operator = AdaptorOperation.Operator
  
  public var entity           : Entity
  public var object           : DatabaseObject // TBD
  public var databaseOperator : Operator = .none
  
  var dbSnapshot  : Snapshot?
  var newRow      : Snapshot?
  
  /// Adaptor operations associated with this database operation. Usually there
  /// is just one, but there can be more.
  /// E.g. an insert may require a sequence fetch.
  var adaptorOperations = [ AdaptorOperation ]()
  
  /// Run when the operation did complete
  open   var completionBlock : (() -> ())?
  
  public init(_ object: DatabaseObject, _ entity: Entity) {
    self.object = object
    self.entity = entity
  }
  public init(_ object: ActiveRecord, _ entity: Entity? = nil) {
    self.object = object
    
    if let entity = entity {
      self.entity = entity
    }
    else {
      self.entity = object.entity
    }
  }
  
  
  // MARK: - mapped operations
  
  func addAdaptorOperation(_ op: AdaptorOperation) {
    // used by adaptorOperationsForDatabaseOperations
    adaptorOperations.append(op)
  }
  
  func didPerformAdaptorOperations() {
    // Note: doesn't say anything about success!
    if let cb = completionBlock {
      completionBlock = nil
      cb()
    }
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    ms += " \(object)"
    ms += " \(entity.name)"
    ms += " \(databaseOperator)"
    
    if let snap = dbSnapshot { ms += " snap=\(snap)" }
    if let snap = newRow     { ms += " new=\(snap)" }
  }
}
