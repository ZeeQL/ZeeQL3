//
//  Constant.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

class Constant : Expression {
}

class ConstantValue<T> : Constant, ExpressionEvaluation {
  
  let value : T
  
  init(value: T) {
    self.value = value
  }

  func valueFor(object: Any?) -> Any? {
    return value
  }
}

class NullExpression : Constant, ExpressionEvaluation {
  
  static let shared = NullExpression()
  
  func valueFor(object: Any?) -> Any? {
    return nil
  }
}

/**
 * RawSQLValue
 *
 * This is used to insert some raw SQL for example as values in an
 * AdaptorOperation.
 * Also used by SQLQualifier to represent the SQL sections of its value.
 */
struct RawSQLValue {
  
  let value : String
  
}
