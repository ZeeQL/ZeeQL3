//
//  Qualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol Qualifier : Expression, EquatableType, SmartDescription {
  // TBD: A protocol because there are multiple different, and extendable versions
  //      of this. You cannot add new qualifiers to an enum. 
  //      (Apart from .Other(Any))
  
  var isEmpty : Bool { get }

  func qualifierWith(bindings: Any?, requiresAll: Bool) throws
                     -> Qualifier?

  // MARK: - String Representation
  
  func appendToStringRepresentation(_ ms: inout String)

  // MARK: - Convenience
  
  var  not : Qualifier { get }
  func or (_ q: Qualifier?) -> Qualifier
  func and(_ q: Qualifier?) -> Qualifier
  
}

public extension Qualifier { // default imp

  func isEqual(to object: Any?) -> Bool { return false }
  
  var isEmpty : Bool { return false }
  
  func qualifierWith(bindings: Any?, requiresAll: Bool) throws -> Qualifier? {
    return self
  }
  func qualifierWith(bindings: Any?) throws -> Qualifier? {
    return try qualifierWith(bindings: bindings, requiresAll: false)
  }
  
  
  // MARK: - String Representation
  
  var stringRepresentation : String {
    var ms = ""
    appendToStringRepresentation(&ms)
    return ms
  }
  
  
  // MARK: - Convenience

  var not : Qualifier { return NotQualifier(qualifier: self) }
  
  func or(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    if let bq = q as? BooleanQualifier {
      return bq.value ? BooleanQualifier.trueQualifier : self
    }
    return CompoundQualifier(qualifiers: [ self, q ], op: .Or)
  }
  func and(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    if let bq = q as? BooleanQualifier {
      return bq.value ? self : BooleanQualifier.falseQualifier
    }
    return CompoundQualifier(qualifiers: [ self, q ], op: .And)
  }

}

// TODO: can we add Equatable to Qualifier or does it make it generic?
public func ==(lhs: Qualifier, rhs: Qualifier) -> Bool {
  return lhs.isEqual(to: rhs)
}


// MARK: - Comparison Operation



// MARK: - Factory

// public extension Qualifier { }
//   Cannot nest in Qualifier protocol in Swift 3.0, maybe later
//   And static functions on protocol types do not work either.
  
public func and(_ a: Qualifier?, _ b: Qualifier?) -> Qualifier? {
  if let a = a, let b = b { return a.and(b) }
  if let a = a { return a }
  return b
}
public func or(_ a: Qualifier?, _ b: Qualifier?) -> Qualifier? {
  if let a = a, let b = b { return a.or(b) }
  if let a = a { return a }
  return b
}

public extension Sequence where Element == Qualifier {
  
  func and() -> Qualifier {
    return reduce(nil, { ZeeQL.and($0, $1) }) ?? BooleanQualifier.falseQualifier
  }
  func or() -> Qualifier {
    return reduce(nil, { ZeeQL.or($0, $1) }) ?? BooleanQualifier.falseQualifier
  }
}
public extension Collection where Element == Qualifier {
  
  func and() -> Qualifier {
    if isEmpty { return BooleanQualifier.falseQualifier }
    if count == 1 { return self[self.startIndex] }
    return CompoundQualifier(qualifiers: Array(self), op: .And)
  }
  func or() -> Qualifier {
    if isEmpty { return BooleanQualifier.falseQualifier }
    if count == 1 { return self[self.startIndex] }
    return CompoundQualifier(qualifiers: Array(self), op: .Or)
  }
}

/**
 * This method returns a set of KeyValueQualifiers combined with an
 * AndQualifier. The keys/values for the KeyValueQualifier are taken
 * from the record.
 *
 * Example:
 *
 *     { lastname = 'Duck'; firstname = 'Donald'; city = 'Hausen' }
 *
 * Results in:
 *
 *     lastname = 'Duck' AND firstname = 'Donald' AND city = 'Hausen'
 *   
 * - returns: a Qualifier for the given record, or null if the record was empty
 */
public func qualifierToMatchAllValues(_ values: [ String : Any? ]?,
                                      _ op: ComparisonOperation = .EqualTo)
            -> Qualifier?
{
  guard let values = values, !values.isEmpty else { return nil }
  let kvq = values.map { KeyValueQualifier(StringKey($0), op, $1) }
  if kvq.count == 1 { return kvq[0] }
  return CompoundQualifier(qualifiers: kvq, op: .And)
}

/**
 * This method returns a set of KeyValueQualifiers combined with an
 * OrQualifier. The keys/values for the KeyValueQualifier are taken
 * from the Map.
 *
 * Example:
 *
 *     { lastname = 'Duck'; firstname = 'Duck'; city = 'Duck' }
 *
 * Results in:
 *
 *     lastname = 'Duck' OR firstname = 'Duck' OR city = 'Duck'
 *   
 * - returns: an Qualifier for the given record, or null if the record was empty
 */
public func qualifierToMatchAnyValue(_ values: [ String : Any? ]?,
                                     _ op: ComparisonOperation = .EqualTo)
            -> Qualifier?
{
  guard let values = values, !values.isEmpty else { return nil }
  let kvq = values.map { KeyValueQualifier(StringKey($0), op, $1) }
  if kvq.count == 1 { return kvq[0] }
  return CompoundQualifier(qualifiers: kvq, op: .Or)
}
