//
//  AdaptorOperation.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * Represents a single database 'change' operation, eg an UPDATE, a DELETE or
 * an INSERT. The object keeps all the relevant information to calculate the
 * SQL for the operation.
 */
public class AdaptorOperation: Comparable, EquatableType, SmartDescription {
  // Note: an object because we also return values using this
  
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
  open   var completionBlock : (() -> ())?
  
  init(entity: Entity) {
    self.entity = entity
  }
  init(_ op: AdaptorOperation) {
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
    guard lhs.entity === rhs.entity                  else { return false }
    guard lhs.adaptorOperator == rhs.adaptorOperator else { return false }
    
    // TODO: the rest.
    
    return true
  }
  
  @inlinable
  public static func < (lhs: AdaptorOperation, rhs: AdaptorOperation) -> Bool {
    // first order by entity name
    if lhs.entity.name < rhs.entity.name { return true }
    
    // then by operation
    if lhs.adaptorOperator.rawValue < rhs.adaptorOperator.rawValue {
      return true
    }
    
    return false
  }

  
  // MARK: - bindings
  
  @inlinable
  func operationWith(bindings: Any?) throws -> AdaptorOperation? {
    guard let q = qualifier else { return self }
    
    guard let bq = try q.qualifierWith(bindings: q, requiresAll: true) else {
      return nil /* not all bindings could be resolved */
    }
    
    if bq == q { return self } // no change
    
    let ao = AdaptorOperation(self) // copy
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
