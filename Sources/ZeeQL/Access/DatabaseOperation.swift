//
//  DatabaseOperation.swift
//  ZeeQL3
//
//  Created by Helge Hess on 15.05.17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * Update, insert, delete or lock a ``DatabaseObject``.
 *
 * This is like an ``AdaptorOperation`` at a higher level.
 * It represents an UPDATE, DELETE, INSERT on a ``DatabaseObject``.
 * Technically this could result in multiple adaptor operations.
 *
 * To execute ``DatabaseOperation``'s, use one of those:
 * - ``Database/performDatabaseOperation(_:)``
 * - ``Database/performDatabaseOperations(_:)``
 * - ``DatabaseChannelBase/performDatabaseOperations(_:)``
 *
 * The ``Database`` variants properly wraps things in a transaction.
 */
open class DatabaseOperation : SmartDescription {
  // TBD: This is not currently subclassed, but it could be.
  
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
  
  @inlinable
  public required init(_ object: DatabaseObject, _ entity: Entity) {
    self.object = object
    self.entity = entity
  }
  @inlinable
  public init(_ object: ActiveRecordType, _ entity: Entity? = nil) {
    self.object = object
    self.entity = entity ?? object.entity
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
  
  
  // MARK: - Generating the operations

  /**
   * Generate the primary ``AdaptorOperation`` for the operator of operation.
   *
   * Side-effects:
   * - sets the `newRow`
   */
  func primaryAdaptorOperation() throws -> AdaptorOperation? {
    var aop    = AdaptorOperation(entity: entity)
    
    var dbop = databaseOperator
    if case .none = databaseOperator {
      if let ar = object as? ActiveRecordType {
        if ar.isNew { databaseOperator = .insert }
        else        { databaseOperator = .update }
        dbop = databaseOperator
      }
    }
    
    if case .none = dbop {
      log.warn("got no operator in db-op:", self)
    }
    aop.adaptorOperator = dbop
    
    switch dbop {
      case .delete:
        // TODO: add attrs used for locking
        let pq : Qualifier?
        if let snapshot = dbSnapshot {
          // The snapshot represents the last known database state. Which is
          // what we want here.
          pq = entity.qualifierForPrimaryKey(snapshot)
        }
        else {
          pq = entity.qualifierForPrimaryKey(object)
        }
        guard pq != nil else {
          log.error("could not calculate primary key qualifier for op:", self)
          throw DatabaseChannelBase.Error.CouldNotBuildPrimaryKeyQualifier
        }
        aop.qualifier = pq
      
      case .insert:
        let props  = entity.classPropertyNames
                  ?? entity.attributes.map { $0.name }
        let values = KeyValueCoding.values(forKeys: props, inObject: object)
        aop.changedValues = values
        newRow            = values // TBD: don't, side effect!!
        
        // TBD: Not sure whether completionBlocks are the best way to
        //      communicate up, maybe make this more formal.
        aop.completionBlock = { [weak self] in // op retains its aop's
          guard let self else { return }
          
          if let rr = aop.resultRow {
            assert(self.newRow != nil)
            for ( key, value ) in rr {
              self.newRow?[key] = value
            }
          }
        }
        
      case .update:
        let snapshot = dbSnapshot
        var pq : Qualifier?

        /* calculate qualifier */
        
        if let snapshot = snapshot {
          // The snapshot represents the last known database state. Which is
          // what we want here.
          pq = entity.qualifierForPrimaryKey(snapshot)
        }
        else {
          pq = entity.qualifierForPrimaryKey(object)
        }
        guard pq != nil else {
          log.error("could not calculate primary key qualifier for op:", self)
          throw DatabaseChannelBase.Error.CouldNotBuildPrimaryKeyQualifier
        }
        
        if let lockAttrs = entity.attributesUsedForLocking,
           !lockAttrs.isEmpty, let snapshot = snapshot
        {
          var qualifiers = [ Qualifier ]()
          qualifiers.reserveCapacity(lockAttrs.count + 1)
          if let pq = pq { qualifiers.append(pq) }
          
          for attr in lockAttrs {
            if let value = snapshot[attr.name] { // value is still an `Any?`!
              let q = KeyValueQualifier(attr.name, .equalTo, value)
              qualifiers.append(q)
            }
            else {
              throw DatabaseChannelBase.Error
                .MissingAttributeUsedForLocking(attr)
            }
          }
          
          pq = CompoundQualifier(qualifiers: qualifiers, op: .And)
        }
        
        aop.qualifier = pq

        /* calculate changed values */
        
        let values : Snapshot
        if let snapshot = snapshot {
          values = object.changesFromSnapshot(snapshot)
        }
        else {
          // no snapshot, need to update all
          let props  = entity.classPropertyNames
                    ?? entity.attributes.map { $0.name }
          values = KeyValueCoding.values(forKeys: props, inObject: object)
        }
        #if false
          // Could work on any KVC object:
          if let dbo = op.object as? DatabaseObject { /*.. code above ..*/ }
          else {
            // update all, no change tracking
            values = KeyValueCoding.values(forKeys: props, inObject: op.object)
            // TODO: changes might include non-class props (like assocs)
          }
        #endif
        
        guard !values.isEmpty else {
          // did not change, no need to update
          return nil
        }

        aop.changedValues = values
        
        /* Note: we need to copy the snapshot because we might ignore it in
         *       case the dbop fails.
         */
        if let snapshot = snapshot {
          var newSnap = snapshot
          for ( key, value ) in values {
            newSnap[key] = value
          }
          dbSnapshot = newSnap
        }
        else {
          dbSnapshot = values
        }
      
      default:
        log.warn("unsupported database operation:", dbop)
        throw DatabaseChannelBase.Error.UnsupportedDatabaseOperator(dbop)
    }
    return aop
  }
  
  
  // MARK: - Description
  
  open func appendToDescription(_ ms: inout String) {
    ms += " \(object)"
    ms += " \(entity.name)"
    ms += " \(databaseOperator)"
    
    if let snap = dbSnapshot { ms += " snap=\(snap)" }
    if let snap = newRow     { ms += " new=\(snap)" }
  }
}

extension DatabaseOperation {
  
  public static func update<O: ActiveRecordType>(_ object: O) -> Self {
    let op = Self(object, object.entity)
    op.databaseOperator = .update
    if let snap = object.snapshot { op.dbSnapshot = snap }
    return op
  }
}
