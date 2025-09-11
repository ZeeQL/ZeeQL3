//
//  Qualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * An ``Expression`` that expresses a condition, usually as part of a SQL
 * `WHERE` statement.
 */
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

  @inlinable
  func isEqual(to object: Any?) -> Bool { return false }
  
  @inlinable
  var isEmpty : Bool { return false }
  
  @inlinable
  func qualifierWith(bindings: Any?, requiresAll: Bool) throws -> Qualifier? {
    return self
  }
  @inlinable
  func qualifierWith(bindings: Any?) throws -> Qualifier? {
    return try qualifierWith(bindings: bindings, requiresAll: false)
  }
  
  
  // MARK: - String Representation
  
  @inlinable
  var stringRepresentation : String {
    var ms = ""
    appendToStringRepresentation(&ms)
    return ms
  }
  
  
  // MARK: - Convenience

  @inlinable
  var not : Qualifier { return NotQualifier(qualifier: self) }
  
  @inlinable
  func or(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    if let bq = q as? BooleanQualifier {
      return bq.value ? BooleanQualifier.trueQualifier : self
    }
    return CompoundQualifier(qualifiers: [ self, q ], op: .Or)
  }
  @inlinable
  func and(_ other: Qualifier?) -> Qualifier {
    guard let other = other else { return self }
    if let bq = other as? BooleanQualifier {
      return bq.value ? self : BooleanQualifier.falseQualifier
    }
    return CompoundQualifier(qualifiers: [ self, other ], op: .And)
  }

}

// TODO: can we add Equatable to Qualifier or does it make it generic?
@inlinable
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
  func compactingOr() -> Qualifier {
    return Array(self).compactingOr()
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
  func compactingOr() -> Qualifier {
    if isEmpty { return BooleanQualifier.falseQualifier }
    if count == 1 { return self[self.startIndex] }
    return Array(self).compactingOr()
  }
}
public extension Array where Element == Qualifier {
  func compactingOr() -> Qualifier {
    if isEmpty { return BooleanQualifier.falseQualifier }
    if count == 1 { return self[self.startIndex] }
    guard let kva = self as? [ KeyValueQualifier ] else {
      return CompoundQualifier(qualifiers: Array(self), op: .Or)
    }
    return kva.compactingOr()
  }
}
public extension Collection where Element == KeyValueQualifier {
  func compactingOr() -> Qualifier {
    if isEmpty { return BooleanQualifier.falseQualifier }
    if count == 1 { return self[self.startIndex] }
    
    var keyToValues = [ String : [ Any? ] ]()
    var extra = [ Qualifier ]()
    
    for kvq in self {
      if kvq.operation != .equalTo {
        extra.append(kvq)
        continue
      }
      
      let key = kvq.key, value = kvq.value
      if keyToValues[key] == nil { keyToValues[key] = [ value ]    }
      else                       { keyToValues[key]!.append(value) }
    }
    
    for ( key, values ) in keyToValues {
      if values.isEmpty { continue }
      if values.count == 1 {
        extra.append(KeyValueQualifier(key, .equalTo, values.first!))
      }
      else {
        extra.append(KeyValueQualifier(key, .in, values))
      }
    }
    
    if extra.count == 1 { return extra[extra.startIndex] }
    return CompoundQualifier(qualifiers: extra, op: .Or)
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
                                      _ op: ComparisonOperation = .equalTo)
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
                                     _ op: ComparisonOperation = .equalTo)
            -> Qualifier?
{
  guard let values = values, !values.isEmpty else { return nil }
  let kvq = values.map { KeyValueQualifier(StringKey($0), op, $1) }
  if kvq.count == 1 { return kvq[0] }
  return CompoundQualifier(qualifiers: kvq, op: .Or)
}
