//
//  AttributeKey.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct AttributeKey : Key, Equatable {

  public var key : String { return attribute.name }
  
  public let entity    : Entity?
  public let attribute : Attribute
  
  public init(_ attribute: Attribute, entity: Entity? = nil) {
    self.attribute = attribute
    self.entity    = entity
  }

  public static func ==(lhs: AttributeKey, rhs: AttributeKey) -> Bool {
    return lhs.key == rhs.key
  }
  
}
