//
//  Constant.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public protocol Constant : Expression {
}

public final class ConstantValue<T> : Constant, ExpressionEvaluation {
  
  public let value : T
  
  @inlinable
  public init(value: T) { self.value = value }

  @inlinable
  public func valueFor(object: Any?) -> Any? { return value }
}


public final class NullExpression : Constant, ExpressionEvaluation {
  
  static let shared = NullExpression()
  
  @inlinable
  public func valueFor(object: Any?) -> Any? { return nil }
}

/**
 * This is used to insert some raw SQL for example as values in an
 * ``AdaptorOperation``.
 * Also used by ``SQLQualifier`` to represent the SQL sections of its value.
 */
public struct RawSQLValue: Hashable {
  
  public let value : String
  
  @inlinable
  public init(_ value: String) { self.value = value }
}

#if swift(>=5.5)
extension ConstantValue  : Sendable where T: Sendable {}
extension NullExpression : Sendable {}
extension RawSQLValue    : Sendable {}
#endif
