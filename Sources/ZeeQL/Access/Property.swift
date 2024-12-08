//
//  Property.swift
//  ZeeQL
//
//  Created by Helge Heß on 18.02.17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * A property of an ``Entity``: Either an ``Attribute`` or a ``Relationship``.
 */
public protocol Property : AnyObject, EquatableType {
  // `class` because we use identity in some places
  
  var name             : String  { get }
  var relationshipPath : String? { get }
  
}

/**
 * A property of an ``Entity``: Either an ``Attribute`` or a ``Relationship``,
 * that knows the static type of the property.
 */
public protocol TypedProperty<T>: Property {
  associatedtype T
}
