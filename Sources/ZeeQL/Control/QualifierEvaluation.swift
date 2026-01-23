//
//  QualifierEvaluation.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

public protocol QualifierEvaluation : ExpressionEvaluation {

  func evaluate(with object: Any?) -> Bool

}

public extension QualifierEvaluation {

  @inlinable
  func valueForObject(_ object: Any?) -> Any? {
    return evaluate(with: object) ? true : false
  }

  @available(*, deprecated, renamed: "evaluate(with:)")
  @inlinable
  func evaluateWith(object: Any?) -> Bool {
    return evaluate(with: object)
  }

}

extension KeyValueQualifier: QualifierEvaluation {
  
  @inlinable
  public func evaluate(with object: Any?) -> Bool {
    let objectValue =
          KeyValueCoding.valueForKeyPath(keyExpr.key, inObject: object)
    return operation.compare(objectValue, value)
  }
}

extension KeyComparisonQualifier: QualifierEvaluation {
  
  @inlinable
  public func evaluate(with object: Any?) -> Bool {
    let a = KeyValueCoding.valueForKeyPath(leftKeyExpr .key, inObject: object)
    let b = KeyValueCoding.valueForKeyPath(rightKeyExpr.key, inObject: object)
    return operation.compare(a, b)
  }
}
