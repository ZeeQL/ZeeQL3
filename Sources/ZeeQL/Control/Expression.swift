//
//  Expression.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

/**
 * Expressions are:
 * - Qualifier
 * - SortOrdering
 * - Constant
 * - Key
 */
public protocol Expression {

  func addReferencedKeys(to set: inout Set<String>)
  
  var  hasUnresolvedBindings : Bool { get }
  func addBindingKeys(to set: inout Set<String>)
  func keyPathForBindingKey(_ variable: String) -> String?
  
}

public struct QualifierBindingNotFound : Swift.Error {
  let binding : String
}


public extension Expression {
  
  var allReferencedKeys : [ String ] {
    var keys = Set<String>()
    addReferencedKeys(to: &keys)
    return Array(keys)
  }
  
  
  // MARK: - Bindings
  
  var bindingKeys : [ String ] {
    var keys = Set<String>()
    addBindingKeys(to: &keys)
    return Array(keys)
  }
}

public extension Expression { // default implementations 

  func addReferencedKeys(to set: inout Set<String>) {}

  var  hasUnresolvedBindings : Bool { return !bindingKeys.isEmpty }
  func addBindingKeys(to set: inout Set<String>) { } // noop
  func keyPathForBindingKey(_ variable: String) -> String? { return nil }
}
