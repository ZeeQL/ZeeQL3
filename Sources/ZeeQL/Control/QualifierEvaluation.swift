//
//  QualifierEvaluation.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

public protocol QualifierEvaluation : ExpressionEvaluation {
  
  func evaluateWith(object: Any?) -> Bool
  
}

public extension QualifierEvaluation {

  func valueFor(object: Any?) -> Any? {
    return evaluateWith(object: object) ? true : false
  }
  
}

extension KeyValueQualifier: QualifierEvaluation {
  public func evaluateWith(object: Any?) -> Bool {
    let objectValue =
          KeyValueCoding.value(forKeyPath: keyExpr.key, inObject: object)
    return operation.compare(objectValue, value)
  }
}

extension KeyComparisonQualifier: QualifierEvaluation {
  public func evaluateWith(object: Any?) -> Bool {
    let a = KeyValueCoding.value(forKeyPath: leftKeyExpr .key, inObject: object)
    let b = KeyValueCoding.value(forKeyPath: rightKeyExpr.key, inObject: object)
    return operation.compare(a, b)
  }
}
