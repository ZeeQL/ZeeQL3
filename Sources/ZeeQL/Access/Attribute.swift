//
//  Attribute.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Usually represents a column in a database table.
 *
 * ## Pattern Attributes
 *
 * Attributes can be pattern attributes. Pattern attributes have a name
 * which is matched against the database information schema. For example
 * the pattern attribute could be 'name*' which would match name1, name2 and
 * name3 columns.
 *
 * Model example:
 *
 *     <attribute columnNameLike="name*" />
 *
 * ## Write Formats
 *
 * 'Write formats' are very useful to lower- or uppercase a value which is
 * you want to search case-insensitive later on. Eg:
 *
 *     writeformat="LOWER(TRIM(%P))"
 *
 * This should be done at write time because if you use LOWER in a WHERE
 * condition the database might not be able to use the index!
 * (well, at least in PostgreSQL you can put an index on the LOWER
 *  transformation, so it _can_ use an index)
 */
public protocol Attribute : class,
                            Property, SQLValue, ExpressionEvaluation,
                            SmartDescription
{  
  var name            : String  { get }
  var columnName      : String? { get }
  var externalType    : String? { get }
  var allowsNull      : Bool?   { get }
  var isAutoIncrement : Bool?   { get }
  var width           : Int?    { get }
  var precision       : Int?    { get }

  var valueType       : AttributeValue.Type? { get }

  // formatting (used by SQLExpression)
  var readFormat      : String? { get }
  var writeFormat     : String? { get }

  var isPattern       : Bool    { get }
}

public extension Attribute { // default imp
  // Note: dupe those in classes to avoid surprises!
  
  var columnName      : String? { return nil }
  var externalType    : String? { return nil }
  var allowsNull      : Bool?   { return nil }
  var isAutoIncrement : Bool?   { return nil }
  var width           : Int?    { return nil }
  var precision       : Int?    { return nil }
  
  var valueType       : AttributeValue.Type? { return nil }
  
  // formatting (used by SQLExpression)
  var readFormat      : String? { return nil }
  var writeFormat     : String? { return nil }
  
  var isPattern       : Bool    { return false }
  
  // MARK: - Property
  
  public var relationshipPath : String? { // for flattened properties
    return nil
  }
  
  // MARK: - SQLValue
  
  public func valueFor(SQLExpression context: SQLExpression) -> String {
    return context.sqlStringFor(schemaObjectName: columnName ?? name)
  }
  
  // MARK: - ExpressionEvaluation
  
  public func valueFor(object: Any?) -> Any? {
    return KeyValueCoding.value(forKeyPath: name, inObject: object)
  }
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    if let cn = columnName {
      ms += "[\(cn)]"
    }

    // TODO: precision
    let ws : String
    if let w = width {
      ws = "(\(w))"
    }
    else {
      ws = ""
    }
    
    if let vt = valueType, let et = externalType {
      ms += " \(vt)[\(et)\(ws)]"
    }
    else if let vt = valueType {
      ms += " \(vt)\(ws)"
    }
    else if let et = externalType {
      ms += " [\(et)\(ws)]"
    }
    
    if let n = allowsNull, n {
      ms += "?"
    }
    if let n = isAutoIncrement, n {
      ms += " AUTOINC"
    }

    if let f = readFormat  { ms += " read='\(f)'"  }
    if let f = writeFormat { ms += " write='\(f)'" }
  }
}


/**
 * An Attribute description which stores the info as regular variables.
 *
 * Suitable for use with models loaded from XML, or models fetched from a
 * database.
 */
open class ModelAttribute : Attribute {

  public final var name            : String
  public final var columnName      : String?
  public final var externalType    : String?
  open         var allowsNull      : Bool?
  public final var isAutoIncrement : Bool?
  public final var width           : Int?
  public final var precision       : Int?
  
  open         var valueType       : AttributeValue.Type?
  public final var defaultValue    : Any?
  
  // MySQL (PG 8.2 has comments on column, but no column privileges?)
  public final var comment         : String?
  public final var collation       : String?
  public final var privileges      : [ String ]?
  
  // formatting (used by SQLExpression)
  public final var readFormat      : String?
  public final var writeFormat     : String?
  
  // patterns
  public final var isColumnNamePattern = false

  public final var userData        = [ String : Any ]()
  
  public init(name         : String,
              column       : String? = nil,
              externalType : String? = nil,
              allowsNull   : Bool?   = nil,
              width        : Int?    = nil)
  {
    self.name         = name
    self.columnName   = column
    self.externalType = externalType
    self.allowsNull   = allowsNull
    self.width        = width
  }
  public init(attribute attr: Attribute) {
    self.name            = attr.name
    self.columnName      = attr.columnName
    self.externalType    = attr.externalType
    self.allowsNull      = attr.allowsNull
    self.isAutoIncrement = attr.isAutoIncrement
    self.width           = attr.width
    self.precision       = attr.precision
    self.readFormat      = attr.readFormat
    self.writeFormat     = attr.writeFormat
    self.valueType       = attr.valueType
    
    if let ma = attr as? ModelAttribute {
      self.defaultValue        = ma.defaultValue
      self.comment             = ma.comment
      self.collation           = ma.collation
      self.privileges          = ma.privileges
      self.isColumnNamePattern = ma.isColumnNamePattern
      
      self.userData            = ma.userData
    }
  }
  
  
  // MARK: - Property

  public var relationshipPath : String? { // for flattened properties
    return nil
  }
  
  
  // MARK: - Pattern Models
  
  public var isPattern : Bool {
    if isColumnNamePattern { return true }
    if externalType == nil { return true }
    return false
  }
  
  public func doesColumnNameMatchPattern(_ columnName: String) -> Bool {
    if !isColumnNamePattern   { return columnName == self.columnName }
    if self.columnName == "*" { return true } // match all
    
    // TODO: fix pattern handling, properly process '*' etc
    return self.columnName?.contains(columnName) ?? false
  }

  public func resolvePatternWith(attribute attr: ModelAttribute) -> Attribute {
    guard isPattern else { return self }
    
    /* derive info */
    
    let rAttr = ModelAttribute(attribute: self)
    if let v = attr.externalType    { rAttr.externalType    = v }
    if let v = attr.isAutoIncrement { rAttr.isAutoIncrement = v }
    if let v = attr.allowsNull      { rAttr.allowsNull      = v }
    if let v = attr.width           { rAttr.width           = v }
    if let v = attr.readFormat      { rAttr.readFormat      = v }
    if let v = attr.writeFormat     { rAttr.writeFormat     = v }
    if let v = attr.defaultValue    { rAttr.defaultValue    = v }
    if let v = attr.comment         { rAttr.comment         = v }
    if let v = attr.collation       { rAttr.collation       = v }
    if let v = attr.privileges      { rAttr.privileges      = v }
    
    /* construct */
    rAttr.isColumnNamePattern = false // TBD: do we need to fix the colName?
    return rAttr
  }
  
  public func addAttributesMatchingAttributes(to list: inout [ Attribute ],
                                              attributes:    [ Attribute ],
                                              entity: Entity? = nil) -> Bool
  {
    if !isColumnNamePattern {
      /* check whether we are contained */
      // TODO: is this correct, could be more than 1 attribute with the same
      //       column?
      for attr in attributes {
        if columnName == attr.columnName {
          list.append(self)
          return true
        }
      }
      return false
    }
    
    /* OK, now we need to evaluate the pattern and clone ourselves */
    
    for attr in attributes {
      guard let colname = attr.columnName       else { continue }
      guard doesColumnNameMatchPattern(colname) else { continue }
      
      /* check whether we already have an attribute for that column */
      
      if let entity = entity {
        guard entity[columnName: colname] == nil else { continue }
        
        /* eg: 'name'='description' in the model (Company) vs column='name'
         *     in the schema */
        guard entity[attribute: colname] == nil else { // TBD
          // TBD: better keep the other attr and rename it
          continue
        }
      }
      
      /* clone and add */
      
      let attrCopy = ModelAttribute(attribute: self)
      attrCopy.name       = attr.name
      attrCopy.columnName = attr.columnName
      attrCopy.isColumnNamePattern = false
      list.append(attrCopy)
    }
    return true
  }

  
  // MARK: - SQLValue
  
  public func valueFor(SQLExpression context: SQLExpression) -> String {
    return context.sqlStringFor(schemaObjectName: columnName ?? name)
  }
  
  // MARK: - ExpressionEvaluation
  
  public func valueFor(object: Any?) -> Any? {
    return KeyValueCoding.value(forKeyPath: name, inObject: object)
  }
}


// MARK: - AttributeValue

import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.Decimal

// marker interface for types that can be used as columns
public protocol AttributeValue {
  
  static var  isOptional : Bool { get }
  
  static func shouldUseBindVariable(for attribute: Attribute) -> Bool
  
  static var optionalBaseType : AttributeValue.Type? { get }
}

public extension AttributeValue {
  static var isOptional : Bool { return false }
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return false
  }
  
  static var optionalBaseType : AttributeValue.Type? { return nil }
  
  // TBD: do we even need this?
  var optionalBaseType : Any.Type? { return type(of: self).optionalBaseType }
}

extension String : AttributeValue {
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
}
extension Data   : AttributeValue {
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
}
extension Int     : AttributeValue {}
extension Int16   : AttributeValue {}
extension Int32   : AttributeValue {}
extension Int64   : AttributeValue {}
extension Float   : AttributeValue {}
extension Double  : AttributeValue {}
extension Bool    : AttributeValue {}

extension Date    : AttributeValue {}
extension URL     : AttributeValue {}
extension Decimal : AttributeValue {}

extension Optional : AttributeValue {
  public static var isOptional : Bool { return true }

  public static var optionalBaseType : AttributeValue.Type? {
    return Wrapped.self as? AttributeValue.Type
  }
}


// MARK: - Query Builder

public extension Attribute {
  
  func eq(_ attr: Attribute) -> KeyComparisonQualifier {
    let key      = AttributeKey(self)
    let otherKey = AttributeKey(attr)
    return KeyComparisonQualifier(key, .EqualTo, otherKey)
  }
  
  func eq(_ value : Any?) -> KeyValueQualifier {
    let key = AttributeKey(self)
    return KeyValueQualifier(key, .EqualTo, value)
  }
}

public extension Attribute {
  
  func like(_ pattern : String) -> KeyValueQualifier {
    let key = AttributeKey(self)
    return KeyValueQualifier(key, .Like, pattern)
  }
  
}
