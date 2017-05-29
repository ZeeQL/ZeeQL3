//
//  File.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol AdaptorRecordSchema : class, SmartDescription {
  // often shared between all records of a single query, hence a class
  var attributes     : [ Attribute ]? { get }
  var attributeNames : [ String ]     { get }
  var count          : Int            { get }

  @discardableResult
  func switchKey(_ oldKey: String, to newKey: String) -> Bool
}

public extension AdaptorRecordSchema {
  
  public var descriptionPrefix : String {
    return "pschema"
  }
  
  public func appendToDescription(_ ms: inout String) {
    if let attrs = attributes {
      ms += " attrs="
      ms += attrs.map { $0.name }.joined(separator: ",")
    }
    else if !attributeNames.isEmpty {
      ms += " names="
      ms += attributeNames.joined(separator: ",")
    }
    else {
      ms += " empty"
    }
  }
}

public final class AdaptorRecordSchemaWithAttributes
                     : AdaptorRecordSchema, SmartDescription
{
  
  public let attributes      : [ Attribute ]?
  
  var _attributeNames        : [ String    ]? = nil // cache them
  public var attributeNames  : [ String ] {
    if _attributeNames == nil { // build cache
      _attributeNames = attributes?.map { $0.name }
    }
    return _attributeNames ?? []
  }
  
  public var count : Int { return attributes?.count ?? 0 }

  public init(_ attributes: [ Attribute ]) {
    self.attributes = attributes
  }
  
  @discardableResult
  public func switchKey(_ oldKey: String, to newKey: String) -> Bool {
    // I don't think we need or want this here.
    return true
  }
  
  // MARK: - Description

  public var descriptionPrefix : String {
    return "schema"
  }
}

public final class AdaptorRecordSchemaWithNames : AdaptorRecordSchema {
  
  public var attributeNames : [ String ] // 'var' because we hack them below
  public var attributes     : [ Attribute ]? { return nil }
  public var count          : Int { return attributeNames.count }
  
  public init(_ names: [ String ]) {
    self.attributeNames = names
  }

  @discardableResult
  public func switchKey(_ oldKey: String, to newKey: String) -> Bool {
    guard let index = attributeNames.index(of: oldKey) else { return false }
    attributeNames[index] = newKey
    return true
  }

  // MARK: - Description
  
  public var descriptionPrefix : String {
    return "nschema"
  }
}
