//
//  Property.swift
//  ZeeQL
//
//  Created by Helge Heß on 18.02.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol Property : class {
  // `class` because we use identity in some places
  
  var name             : String  { get }
  var relationshipPath : String? { get }
  
}
