//
//  CompoundQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

public struct CompoundQualifier : Qualifier, QualifierEvaluation, Equatable {
  
  public enum Operator {
    case and
    case or
    
    @available(*, deprecated, message: "Using `and` is recommended.")
    public static let And = Operator.and
    @available(*, deprecated, message: "Using `or` is recommended.")
    public static let Or  = Operator.or

    @inlinable
    var stringRepresentation : String {
      switch self {
        case .and: return "AND"
        case .or:  return "OR"
      }
    }
  }
  
  public let op         : Operator
  public let qualifiers : [ Qualifier ]
  
  @inlinable
  public init(qualifiers: [ Qualifier ], op: Operator) {
    self.qualifiers = qualifiers
    self.op         = op
  }
  
  @inlinable
  public var isEmpty : Bool { return qualifiers.isEmpty }

  @inlinable
  public func addReferencedKeys(to set: inout Set<String>) {
    for q in qualifiers {
      q.addReferencedKeys(to: &set)
    }
  }
  
  
  // MARK: - Bindings

  @inlinable
  public func addBindingKeys(to set: inout Set<String>) {
    for q in qualifiers {
      q.addBindingKeys(to: &set)
    }
  }
  
  @inlinable
  public var hasUnresolvedBindings : Bool {
    for q in qualifiers { if q.hasUnresolvedBindings { return true } }
    return false
  }
  
  @inlinable
  public func keyPathForBindingKey(_ variable: String) -> String? {
    for q in qualifiers {
      if let kp = q.keyPathForBindingKey(variable) { return kp }
    }
    return nil
  }

  @inlinable
  public func qualifierWithBindings(_ bindings: Any?, requiresAll: Bool)
    throws -> Qualifier
  {
    if qualifiers.isEmpty { return self }
    if qualifiers.count == 1 {
      return try qualifiers[0]
        .qualifierWithBindings(bindings, requiresAll: requiresAll)
    }
    
    var didChange = false
    var boundQualifiers = [ Qualifier ]()
    boundQualifiers.reserveCapacity(qualifiers.count)
    
    for q in qualifiers {
      /* This is interesting. If _requiresAll is false, we are supposed to
       * *leave out* qualifiers which have a binding we can't deal with.
       *
       * This way we can have a 'lastname = $la AND firstname = '$fa'. Eg if
       * 'fa' is missing, only 'lastname = $fa' will get executed. Otherwise
       * we would have 'firstname IS NULL' which is unlikely the thing we
       * want.
       */
      let bound = // this throws if requiresAll is not satisfied
            try q.qualifierWithBindings(bindings, requiresAll: requiresAll)
      if !didChange { didChange = !q.isEqual(to: bound) }
      boundQualifiers.append(bound)
    }
    
    if !didChange { return self }
    return CompoundQualifier(qualifiers: boundQualifiers, op: op)
  }

  @inlinable
  public var operatorAsString : String { return op.stringRepresentation }
  
  
  // MARK: - QualifierEvaluation

  @inlinable
  public func evaluateWith(object: Any?) -> Bool {
    for q in qualifiers {
      guard let qe = q as? QualifierEvaluation else {
        // TODO: what should we do. Just assert and log in non-debug?
        return false
      }
      
      switch op {
        case .or:  if  qe.evaluateWith(object: object) { return true  }
        case .and: if !qe.evaluateWith(object: object) { return false }
      }
    }
    switch op {
      case .or:  return false
      case .and: return true
    }
  }

  
  // MARK: - Equality
  
  @inlinable
  public static func ==(lhs: CompoundQualifier, rhs: CompoundQualifier)
                     -> Bool
  {
    guard lhs.op == rhs.op else { return false }
    
    let qs    = lhs.qualifiers
    let count = qs.count
    guard count == rhs.qualifiers.count else { return false }
    
    if count == 0 { return true }
    if count == 1 { return qs[0].isEqual(to: rhs.qualifiers[0]) }
    
    // TODO: order doesn't matter for .Or?
    for i in 0..<count {
      let a = qs[i]
      let b = rhs.qualifiers[i]
      guard a.isEqual(to: b) else { return false }
    }
    
    return true
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? CompoundQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    // TODO: improve
    ms += " \(op.stringRepresentation)(\(qualifiers))"
  }
  
  public func appendToStringRepresentation(_ ms: inout String) {
    guard !qualifiers.isEmpty else { return }
    if qualifiers.count == 1 {
      qualifiers[0].appendToStringRepresentation(&ms)
    }
    else {
      let separator = " \(operatorAsString) "
      for i in 0..<qualifiers.count {
        let q = qualifiers[i]
        if i > 0 { ms += separator }
        
        if q is CompoundQualifier {
          ms += "("
          q.appendToStringRepresentation(&ms)
          ms += ")"
        }
        else {
          q.appendToStringRepresentation(&ms)
        }
      }
    }
  }
  
  
  // MARK: - Convenience Optimization

  @inlinable
  public func or(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    switch op {
      case .or:
        if let oq = q as? CompoundQualifier, oq.op == .or {
          return CompoundQualifier(qualifiers: qualifiers + oq.qualifiers,
                                   op: .or)
        }
        return CompoundQualifier(qualifiers: qualifiers + [ q ], op: .or)
      
      case .and:
        return CompoundQualifier(qualifiers: [ self, q ], op: .or)
    }
  }

  @inlinable
  public func and(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    switch op {
      case .and:
        if let oq = q as? CompoundQualifier, oq.op == .and {
          return CompoundQualifier(qualifiers: qualifiers + oq.qualifiers,
                                   op: .and)
        }
        return CompoundQualifier(qualifiers: qualifiers + [ q ], op: .and)
      
      case .or:
        return CompoundQualifier(qualifiers: [ self, q ], op: .and)
    }
  }
}
