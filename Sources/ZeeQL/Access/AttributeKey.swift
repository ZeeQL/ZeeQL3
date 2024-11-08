//
//  AttributeKey.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * A ``Key`` that has access to an ``Attribute`` (an potentially the associated
 * ``Entity``).
 *
 * The ``Key/key`` is the ``Attribute/name``.
 */
public struct AttributeKey : Key, Equatable {

  public var key : String { return attribute.name }
  
  public let entity    : Entity?
  public let attribute : Attribute
  
  @inlinable
  public init(_ attribute: Attribute, entity: Entity? = nil) {
    self.attribute = attribute
    self.entity    = entity
  }

  @inlinable
  public static func ==(lhs: AttributeKey, rhs: AttributeKey) -> Bool {
    return lhs.key == rhs.key
  }
}
