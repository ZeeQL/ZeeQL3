//
//  Expression.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * ``Expression``'s are:
 * - ``Qualifier``
 * - ``SortOrdering``
 * - ``Constant``
 * - ``Key``
 */
public protocol Expression {
  // TBD: Collides w/ Swift 6 `Expression` in Foundation?

  func addReferencedKeys(to set: inout Set<String>)
  
  var  hasUnresolvedBindings : Bool { get }
  func addBindingKeys(to set: inout Set<String>)
  func keyPathForBindingKey(_ variable: String) -> String?
  
}

public struct QualifierBindingNotFound : Swift.Error, Hashable {
  public let binding : String
  
  @inlinable
  init(binding: String) { self.binding = binding }
}

#if swift(>=5.5)
extension QualifierBindingNotFound : Sendable {}
#endif


public extension Expression {
  
  @inlinable
  var allReferencedKeys : [ String ] {
    var keys = Set<String>()
    addReferencedKeys(to: &keys)
    return Array(keys)
  }
  
  
  // MARK: - Bindings
  
  @inlinable
  var bindingKeys : [ String ] {
    var keys = Set<String>()
    addBindingKeys(to: &keys)
    return Array(keys)
  }
}

public extension Expression { // default implementations 

  @inlinable
  func addReferencedKeys(to set: inout Set<String>) {}

  @inlinable
  var  hasUnresolvedBindings : Bool { return !bindingKeys.isEmpty }
  @inlinable
  func addBindingKeys(to set: inout Set<String>) { } // noop
  @inlinable
  func keyPathForBindingKey(_ variable: String) -> String? { return nil }
}
