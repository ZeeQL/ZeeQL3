//
//  AdaptorOperation.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * Represents a single database 'change' operation, eg an UPDATE, a DELETE or
 * an INSERT. The object keeps all the relevant information to calculate the
 * SQL for the operation.
 */
public struct AdaptorOperation: Comparable, EquatableType, SmartDescription {
  // Note: an object because we also return values using this
  
  @inlinable
  public static func update(_ e: Entity, set: AdaptorRow, where q: Qualifier)
                     -> Self
  {
    var me = AdaptorOperation(entity: e)
    me.adaptorOperator = .update
    me.changedValues   = set
    me.qualifier       = q
    return me
  }
  
  @inlinable
  public static func insert(_ values: AdaptorRow, into e: Entity) -> Self {
    var me = AdaptorOperation(entity: e)
    me.adaptorOperator = .insert
    me.changedValues   = values
    return me
  }
  
  @inlinable
  public static func delete(from e: Entity, where q: Qualifier) -> Self {
    var me = AdaptorOperation(entity: e)
    me.adaptorOperator = .delete
    me.qualifier       = q
    return me
  }

  public enum Operator : Int { /* Note: sequence is relevant for comparison */
    case none   = 0
    case lock   = 1
    case insert = 2
    case update = 3
    case delete = 4
  }
  
  public let entity          : Entity
  public var adaptorOperator : Operator = .none
  public var attributes      : [ Attribute ]?
  public var qualifier       : Qualifier?
  
  /// Values for an Update or Insert operation
  public var changedValues   : AdaptorRow?
  
  /// Contains the values of the new record that got inserted.
  public var resultRow       : AdaptorRow?
  
  /// Run when the operation did complete
  public var completionBlock : (() -> ())?
  
  @inlinable
  public init(entity: Entity) {
    self.entity = entity
  }
  @inlinable
  public init(_ op: AdaptorOperation) {
    entity          = op.entity
    adaptorOperator = op.adaptorOperator
    attributes      = op.attributes
    qualifier       = op.qualifier
    changedValues   = op.changedValues
    resultRow       = op.resultRow
  }
  
  
  // MARK: - Comparable

  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let oa = object as? AdaptorOperation else { return false }
    return self == oa
  }

  @inlinable
  public static func ==(lhs: AdaptorOperation, rhs: AdaptorOperation) -> Bool {
    guard lhs.entity           === rhs.entity,
          lhs.adaptorOperator   == rhs.adaptorOperator,
          lhs.attributes?.count ?? 0 == rhs.attributes?.count ?? 0 
     else { return false }
    
    // TBD: we should probably sort
    if let lhs = lhs.attributes, let rhs = rhs.attributes {
      guard lhs.count == rhs.count else { return false } // already checked ^^^
      for i in lhs.indices {
        // TBD: we might actually want to compare them
        guard lhs[i] === rhs[i] else { return false } // identity check only
      }
    }
    
    if let lhs = lhs.qualifier {
      guard let rhs = rhs.qualifier, eq(lhs, rhs) else { return false }
    }
    else if rhs.qualifier != nil { return false }
    
    if let lhs = lhs.changedValues {
      guard let rhs = rhs.changedValues, eq(lhs, rhs) else { return false }
    }
    else if rhs.changedValues != nil { return false }

    if let lhs = lhs.resultRow {
      guard let rhs = rhs.resultRow, eq(lhs, rhs) else { return false }
    }
    else if rhs.resultRow != nil { return false }

    // Not comparing the completion-closure.
    return true
  }
  
  @inlinable
  public static func < (lhs: AdaptorOperation, rhs: AdaptorOperation) -> Bool {
    let lhsName = lhs.entity.name
    let rhsName = rhs.entity.name
    if lhsName != rhsName { return lhsName < rhsName }
    
    let lhsOperator = lhs.adaptorOperator.rawValue
    let rhsOperator = rhs.adaptorOperator.rawValue
    return lhsOperator < rhsOperator
  }

  
  // MARK: - bindings
  
  @inlinable
  func operationWithBindings(_ bindings: Any?) throws -> AdaptorOperation? {
    guard let q = qualifier else { return self }
    
    let bq = try q.qualifierWithBindings(bindings, requiresAll: true)
    
    if bq == q { return self } // no change
    
    var ao = AdaptorOperation(self) // copy
    ao.qualifier = bq
    return ao
  }

  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    ms += " \(entity.name)"
    ms += " \(adaptorOperator)"
    
    if let attrs = attributes {
      ms += " " + attrs.map({$0.name}).joined(separator: ",")
    }
    
    if let q = qualifier { ms += " q=\(q)" }
    
    if let values = changedValues {
      ms += " values=\(values)"
    }
    if let values = resultRow {
      ms += " result=\(values)"
    }
  }
}

#if swift(>=5.5)
// AdaptorOperation itself can't be sent yet due to the closure.
extension AdaptorOperation.Operator: Sendable {}
#endif
