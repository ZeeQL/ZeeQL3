//
//  SQLite3Expression.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

// MARK: - Expressions

open class SQLite3ExpressionFactory: SQLExpressionFactory {
  
  static let shared = SQLite3ExpressionFactory()
  
  override open func createExpression(_ entity: Entity?) -> SQLExpression {
    return SQLite3Expression(entity: entity)
  }
}

open class SQLite3Expression: SQLExpression {

  override open var lockClause : String? {
    return nil // SQLite has no 'FOR UPDATE', other means for locking?
  }

  override open func limitClause(offset: Int = -1, limit: Int = -1) -> String? {
    guard offset >= 0 || limit >= 0 else { return nil }
    if offset > 0 && limit >= 0 { return "LIMIT \(limit) OFFSET \(offset)" }
    if offset > 0 { return "LIMIT -1 OFFSET \(offset)" }
    return "LIMIT \(limit)"
  }
}
