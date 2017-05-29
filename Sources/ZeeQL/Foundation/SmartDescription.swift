//
//  SmartDescription.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol SmartDescription : CustomStringConvertible {
  
  var descriptionPrefix : String { get }
  func appendToDescription(_ ms: inout String)
}

public extension SmartDescription { // default-imp
  
  public var descriptionPrefix : String {
    return "\(type(of: self))"
  }
  
  public var description: String {
    var s = "<\(descriptionPrefix)"
    appendToDescription(&s)
    s += ">"
    return s
  }
  
}
