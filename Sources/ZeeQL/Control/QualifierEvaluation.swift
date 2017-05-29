//
//  QualifierEvaluation.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol QualifierEvaluation : ExpressionEvaluation {
  
  func evaluateWith(object: Any?) -> Bool
  
}

public extension QualifierEvaluation {

  public func valueFor(object: Any?) -> Any? {
    return evaluateWith(object: object) ? true : false
  }
  
}
