//
//  Property.swift
//  ZeeQL
//
//  Created by Helge Heß on 18.02.17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

/**
 * A property of an `Entity`: Either an `Attribute` or a `Relationship`.
 */
public protocol Property : class, EquatableType {
  // `class` because we use identity in some places
  
  var name             : String  { get }
  var relationshipPath : String? { get }
  
}
