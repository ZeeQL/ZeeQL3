//
//  Attribute.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import Foundation

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
 * ```xml
 * <attribute columnNameLike="name*" />
 * ```
 *
 * ## Write Formats
 *
 * 'Write formats' are very useful to lower- or uppercase a value which is
 * you want to search case-insensitive later on. for example:
 * ```xml
 * writeformat="LOWER(TRIM(%P))"
 * ```
 *
 * This should be done at write time because if you use `LOWER` in a `WHERE`
 * condition the database might not be able to use the index!
 * (well, at least in PostgreSQL you can put an index on the `LOWER`
 *  transformation, so it _can_ use an index)
 *
 * Implementors:
 * - ``ModelAttribute``
 * - ``CodeAttribute``
 * - ``CodeValueAttribute``
 */
public protocol Attribute : Property, SQLValue, ExpressionEvaluation,
                            SmartDescription
{
  // TBD: `ModelAttribute` and its subclasses are the sole implementers, right?
  //      This one is "readonly" though.
  
  var name            : String               { get }
  var columnName      : String?              { get }
  var externalType    : String?              { get }
  var allowsNull      : Bool?                { get }
  var isAutoIncrement : Bool?                { get }
  var width           : Int?                 { get }
  var precision       : Int?                 { get }

  var valueType       : AttributeValue.Type? { get }
  var defaultValue    : Any?                 { get }

  var patternType     : AttributePatternType { get }

  // MySQL (PG 8.2 has comments on column, but no column privileges?)
  var comment         : String?              { get }
  var collation       : String?              { get }
  var privileges      : [ String ]?          { get }
  
  // formatting (used by SQLExpression)
  var readFormat      : String?              { get }
  var writeFormat     : String?              { get }

  var isPattern       : Bool                 { get }

  var userData        : [ String : Any ]     { get }
  
  /// A persistent ID used to track renaming when doing model-to-model
  /// migrations. Used in Core Data.
  var elementID       : String?              { get }
  
  /// CoreData (e.g. for `Date` attributes)
  var usesScalarValueType  : Bool?           { get }
  /// CoreData: Minimum timestamp for Date, if set
  var minDateTimeInterval  : Date?           { get }
  /// CoreData: Maximum timestamp for Date, if set
  var maxDateTimeInterval  : Date?           { get }
  /// CoreData: If it is a derived attribute this contains the expression.
  var derivationExpression : String?         { get }
}

public extension Attribute { // default imp
  // Note: dupe those in classes to avoid surprises!
  
  var columnName           : String?              { return nil   }
  var externalType         : String?              { return nil   }
  var allowsNull           : Bool?                { return nil   }
  var isAutoIncrement      : Bool?                { return nil   }
  var width                : Int?                 { return nil   }
  var precision            : Int?                 { return nil   }
  
  var patternType          : AttributePatternType { return .none }
  
  var valueType            : AttributeValue.Type? { return nil   }
  var defaultValue         : Any?                 { return nil   }

  var comment              : String?              { return nil   }
  var collation            : String?              { return nil   }
  var privileges           : [ String ]?          { return nil   }
  
  var readFormat           : String?              { return nil   }
  var writeFormat          : String?              { return nil   }
  
  var isPattern            : Bool                 { return false }
  var usesScalarValueType  : Bool?                { return nil   }
  var minDateTimeInterval  : Date?                { return nil   }
  var maxDateTimeInterval  : Date?                { return nil   }
  var derivationExpression : String?              { return nil   }

  // MARK: - Property
  
  var relationshipPath : String? { // for flattened properties
    return nil
  }
  
  // MARK: - SQLValue
  
  @inlinable
  func valueFor(SQLExpression context: SQLExpression) -> String {
    return context.sqlStringFor(schemaObjectName: columnName ?? name)
  }
  
  // MARK: - ExpressionEvaluation
  
  @inlinable
  func valueFor(object: Any?) -> Any? {
    return KeyValueCoding.value(forKeyPath: name, inObject: object)
  }
  
  // MARK: - Description

  func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    if let cn = columnName { ms += "[\(cn)]" }

    // TODO: precision
    let ws : String
    if let w = width { ws = "(\(w))" }
    else             { ws = "" }
    
    if let vt = valueType, let et = externalType { ms += " \(vt)[\(et)\(ws)]" }
    else if let vt = valueType                   { ms += " \(vt)\(ws)"        }
    else if let et = externalType                { ms += " [\(et)\(ws)]"     }
    
    if let n = allowsNull,      n { ms += "?"        }
    if let n = isAutoIncrement, n { ms += " AUTOINC" }

    if let f = readFormat  { ms += " read='\(f)'"  }
    if let f = writeFormat { ms += " write='\(f)'" }
  }
}

public extension Attribute { // default imp
  
  @inlinable
  func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Attribute else { return false }
    return other.isEqual(to: self)
  }
  
  func isEqual(to other: Self) -> Bool {
    if other === self { return true  }
    guard name                == other.name                else { return false }
    guard columnName          == other.columnName          else { return false }
    guard externalType        == other.externalType        else { return false }
    guard allowsNull          == other.allowsNull          else { return false }
    guard isAutoIncrement     == other.isAutoIncrement     else { return false }
    guard width               == other.width               else { return false }
    guard precision           == other.precision           else { return false }
    guard valueType           == other.valueType           else { return false }
    guard readFormat          == other.readFormat          else { return false }
    guard writeFormat         == other.writeFormat         else { return false }
    guard isPattern           == other.isPattern           else { return false }
    guard patternType         == other.patternType         else { return false }

    guard elementID           == other.elementID           else { return false }
    guard usesScalarValueType == other.usesScalarValueType else { return false }
    guard minDateTimeInterval == other.minDateTimeInterval else { return false }
    guard maxDateTimeInterval == other.maxDateTimeInterval else { return false }
    guard derivationExpression == other.derivationExpression else {
      return false
    }
    
    guard ZeeQL.eq(defaultValue, other.defaultValue) else { return false }

    // TBD: userData
    return true
  }
  
  @inlinable
  static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}

/// Commonly used within the framework, but should not be public API
extension Attribute {
  var columnNameOrName : String { return columnName ?? name }
}

/// Pattern types.
public enum AttributePatternType: String, Sendable {
  case none       = ""
  /// The columnName is a pattern
  case columnName = "columnName"
  /// The attribute should be skipped in the entity.
  case skip       = "skip"
}


/**
 * An ``Attribute`` description which stores the info as regular variables.
 *
 * Suitable for use with models loaded from XML, or models fetched from a
 * database.
 */
open class ModelAttribute : Attribute, Equatable {
  // TBD: Would be good to make this a struct, but it is currently subclassed
  //      for the Code based models. Maybe they could just wrap it?

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
  
  public final var patternType     = AttributePatternType.none

  public final var userData        = [ String : Any ]()
  
  /// A persistent ID used to track renaming when doing model-to-model
  /// migrations. Used in Core Data.
  public final var elementID       : String?
  
  /// CoreData (e.g. for `Date` attributes)
  public final var usesScalarValueType     : Bool?
  /// CoreData: Minimum timestamp for Date, if set
  public final var minDateTimeInterval     : Date?
  /// CoreData: Maximum timestamp for Date, if set
  public final var maxDateTimeInterval     : Date?
  /// CoreData: If it is a derived attribute this contains the expression.
  public final var derivationExpression    : String?

  public init(name         : String,
              column       : String? = nil,
              externalType : String? = nil,
              allowsNull   : Bool?   = nil,
              width        : Int?    = nil,
              valueType    : AttributeValue.Type? = nil)
  {
    self.name         = name
    self.columnName   = column
    self.externalType = externalType
    self.allowsNull   = allowsNull
    self.width        = width
    self.valueType    = valueType
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
    
    self.defaultValue         = attr.defaultValue
    self.comment              = attr.comment
    self.collation            = attr.collation
    self.privileges           = attr.privileges
    self.patternType          = attr.patternType
    
    self.userData             = attr.userData
    self.elementID            = attr.elementID
    self.usesScalarValueType  = attr.usesScalarValueType
    self.minDateTimeInterval  = attr.minDateTimeInterval
    self.maxDateTimeInterval  = attr.maxDateTimeInterval
    self.derivationExpression = attr.derivationExpression
  }
  
  
  // MARK: - Property

  public var relationshipPath : String? { // for flattened properties
    return nil
  }
  
  
  // MARK: - Pattern Models
  
  public var isPattern : Bool {
    if patternType != .none { return true }
    if externalType == nil  { return true }
    if allowsNull   == nil  { return true }
    return false
  }
  
  public func doesColumnNameMatchPattern(_ columnName: String) -> Bool {
    if patternType != .columnName { return columnName == self.columnName }
    if self.columnName == "*" { return true } // match all
    
    // TODO: fix pattern handling, properly process '*' etc
    return self.columnName?.contains(columnName) ?? false
  }

  public func resolvePatternWith(attribute attr: ModelAttribute) -> Attribute {
    guard isPattern else { return self }
    
    /* derive info */
    
    let rAttr = ModelAttribute(attribute: self)
    // The pattern *overrides* the external spec! If you want the information
    // schema to win, leave out the value in the pattern.
    if rAttr.externalType    == nil, let v = attr.externalType    {
      rAttr.externalType    = v
    }
    if rAttr.isAutoIncrement == nil, let v = attr.isAutoIncrement {
      rAttr.isAutoIncrement = v
    }
    if rAttr.allowsNull      == nil, let v = attr.allowsNull      {
      rAttr.allowsNull      = v
    }
    if rAttr.width           == nil, let v = attr.width           {
      rAttr.width           = v
    }
    if rAttr.readFormat      == nil, let v = attr.readFormat      {
      rAttr.readFormat      = v
    }
    if rAttr.writeFormat     == nil, let v = attr.writeFormat     {
      rAttr.writeFormat     = v
    }
    if rAttr.defaultValue    == nil, let v = attr.defaultValue    {
      rAttr.defaultValue    = v
    }
    if rAttr.comment         == nil, let v = attr.comment         {
      rAttr.comment         = v
    }
    if rAttr.collation       == nil, let v = attr.collation       {
      rAttr.collation       = v
    }
    if rAttr.privileges      == nil, let v = attr.privileges      {
      rAttr.privileges      = v
    }
    
    /* construct */
    rAttr.patternType = .none // TBD: do we need to fix the colName?
    return rAttr
  }
  
  public func addAttributesMatchingAttributes(to list: inout [ Attribute ],
                                              attributes:    [ Attribute ],
                                              entity: Entity? = nil) -> Bool
  {
    if patternType == .skip { return false }
    if patternType != .columnName {
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
      attrCopy.name        = attr.name
      attrCopy.columnName  = attr.columnName
      attrCopy.patternType = .none
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
  
  
  // MARK: - Equatable
  
  public static func ==(lhs: ModelAttribute, rhs: ModelAttribute) -> Bool {
    return lhs.isEqual(to: rhs)
  }


  // MARK: - Own Description
  
  public func appendToDescription(_ ms: inout String) {
    ms += " \(name)"
    if let cn = columnName {
      ms += "["
      ms += cn
      if patternType == .columnName { ms += "*" }
      ms += "]"
    }
    
    if patternType == .skip { ms += " SKIP" }
    
    // TODO: precision
    let ws : String
    if let w = width { ws = "(\(w))" }
    else             { ws = ""       }
    
    if let vt = valueType, let et = externalType { ms += " \(vt)[\(et)\(ws)]" }
    else if let vt = valueType    { ms += " \(vt)\(ws)"  }
    else if let et = externalType { ms += " [\(et)\(ws)]" }
    
    if let n = allowsNull,      n { ms += "?"        }
    if let n = isAutoIncrement, n { ms += " AUTOINC" }
    
    if let f = readFormat   { ms += " read='\(f)'"  }
    if let f = writeFormat  { ms += " write='\(f)'" }

    if let v = defaultValue { ms += " default=\(v)" }
    if let v = comment      { ms += " comment='\(v)'" }
    if let v = collation    { ms += " collation='\(v)'" }
    if let v = privileges   { ms += " privileges='\(v)'" }

    if !userData.isEmpty {
      ms += " ud=["
      for ( key, value ) in userData {
        ms += " "
        ms += key
        ms += ": "
        ms += String(describing: value)
      }
      ms += "]"
    }
  }
}


// MARK: - Query Builder

public extension Attribute {
  
  @inlinable
  func eq(_ attr: Attribute) -> KeyComparisonQualifier {
    let key      = AttributeKey(self)
    let otherKey = AttributeKey(attr)
    return KeyComparisonQualifier(key, .EqualTo, otherKey)
  }
  
  @inlinable
  func eq(_ value : Any?) -> KeyValueQualifier {
    let key = AttributeKey(self)
    return KeyValueQualifier(key, .EqualTo, value)
  }
}

public extension Attribute {

  @inlinable
  func like(_ pattern : String) -> KeyValueQualifier {
    let key = AttributeKey(self)
    return KeyValueQualifier(key, .Like, pattern)
  }
  
}
