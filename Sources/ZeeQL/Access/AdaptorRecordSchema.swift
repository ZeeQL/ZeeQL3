//
//  AdaptorRecordSchema.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * The schema is used for `AdaptorRecord` objects. It represents the
 * keys in the record.
 *
 * This is a class because the same schema is used for all objects.
 *
 * There are two builtin implementations for this:
 * - ``AdaptorRecordSchemaWithAttributes`` (w/ resolved Attribute values)
 * - ``AdaptorRecordSchemaWithNames``      (just the attribute names)
 */
public protocol AdaptorRecordSchema : AnyObject, SmartDescription {
  // TBD: Should that also just require Sendable, if Swift>=5? Probably.
  
  // often shared between all records of a single query, hence a class
  var attributes     : [ Attribute ]? { get }
  var attributeNames : [ String ]     { get }
  var count          : Int            { get }

  @discardableResult
  func switchKey(_ oldKey: String, to newKey: String) -> Bool
}

public extension AdaptorRecordSchema {
  
  var descriptionPrefix : String { return "pschema" }
  
  func appendToDescription(_ ms: inout String) {
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
  
  @usableFromInline
  var _attributeNames        : [ String    ]? = nil // cache them
  
  @inlinable
  public var attributeNames  : [ String ] {
    if _attributeNames == nil { // build cache
      _attributeNames = attributes?.map { $0.name }
    }
    return _attributeNames ?? []
  }
  
  @inlinable
  public var count : Int { return attributes?.count ?? 0 }

  @inlinable
  public init(_ attributes: [ Attribute ]) {
    self.attributes = attributes
  }
  
  @inlinable
  @discardableResult
  public func switchKey(_ oldKey: String, to newKey: String) -> Bool {
    // I don't think we need or want this here.
    return true
  }
  
  // MARK: - Description

  @inlinable
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
    #if swift(>=5)
      guard let index = attributeNames.firstIndex(of: oldKey) else {
        return false
      }
    #else
      guard let index = attributeNames.index(of: oldKey) else { return false }
    #endif
    attributeNames[index] = newKey
    return true
  }

  // MARK: - Description
  
  public var descriptionPrefix : String {
    return "nschema"
  }
}


#if swift(>=5.5)
// TBD: I think the protocol should just require Sendable. Also need to check
//      how the switch is being used.
// @unchecked because the protocol requires AnyObject (class ref).
// Schemas are created once per query result set and are
// effectively immutable after construction. The `switchKey`
// mutation happens before records are handed to the caller.
extension AdaptorRecordSchemaWithAttributes : @unchecked Sendable {}
extension AdaptorRecordSchemaWithNames      : @unchecked Sendable {}
#endif
