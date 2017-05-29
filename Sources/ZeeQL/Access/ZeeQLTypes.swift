//
//  ZeeQLTypes.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.Date
import struct Foundation.Data

public enum ZeeQLTypes {
  // All this really belongs into the adaptors, but the basic stuff is all the
  // same for SQL.
  
  /**
   * Returns a SQL type for the given Swift type (_name_). 
   *
   * E.g. "INT" for an "Int". Or "VARCHAR" for "String".
   *
   * Do not overuse this, bad stylez :-)
   */
  public static func externalTypeFor(swiftType: String) -> String? {
    // TODO: this really belongs into the Adaptor?
    switch swiftType {
      case "Int":    return "INT"
      case "String": return "VARCHAR"
      case "Float":  return "FLOAT"
      case "Double": return "DOUBLE"
      case "Bool":   return "BOOLEAN"
      default:       return nil
    }
  }

  /**
   * Returns a SQL type for the given Swift type (type object).
   *
   * E.g. "INT" for an `Int.self`. Or "VARCHAR" for `String.self`.
   *
   * Do not overuse this, bad stylez :-)
   */
  public static func externalTypeFor(swiftType: Any.Type) -> String? {
    if swiftType == Int.self     { return "INT"     }
    if swiftType == String.self  { return "VARCHAR" }
    if swiftType == Float.self   { return "FLOAT"   }
    if swiftType == Double.self  { return "DOUBLE"  }
    if swiftType == [UInt8].self { return "BLOB"    }
    if swiftType == Int.self     { return "INT"     }
    if swiftType == Bool.self    { return "BOOLEAN" }
    return nil
  }
  
  /**
   * Returns a reasonable Swift type for the given SQL type.
   *
   * E.g. a `String.self` for a "VARCHAR".
   *
   * Do not overuse this, bad stylez :-)
   */
  public static func valueTypeForExternalType(_ uType: String, allowsNull: Bool)
                     -> AttributeValue.Type?
  {
    // TODO: consider scale and such
    if allowsNull {
      if uType.hasPrefix("VARCHAR")        { return Optional<String>.self }
      if uType.hasPrefix("INT")            { return Optional<Int>.self    }
      if uType.hasPrefix("DOUBLE")         { return Optional<Double>.self }
      if uType.hasPrefix("FLOAT")          { return Optional<Float>.self  }
      if uType.hasPrefix("TEXT")           { return Optional<String>.self }
      if uType.hasPrefix("TIMESTAMP")      { return Optional<Date>.self   }
      if uType.hasPrefix("BLOB")           { return Optional<Data>.self   }
      if uType.hasPrefix("CLOB")           { return Optional<String>.self }
      if uType.hasPrefix("BOOL")           { return Optional<Bool>.self   }
    }
    else {
      if uType.hasPrefix("VARCHAR")        { return String.self }
      if uType.hasPrefix("INT")            { return Int.self    }
      if uType.hasPrefix("DOUBLE")         { return Double.self }
      if uType.hasPrefix("FLOAT")          { return Float.self  }
      if uType.hasPrefix("TEXT")           { return String.self }
      if uType.hasPrefix("TIMESTAMP")      { return Date.self   }
      if uType.hasPrefix("BLOB")           { return Data.self   }
      if uType.hasPrefix("CLOB")           { return String.self }
      if uType.hasPrefix("BOOL")           { return Bool.self   }
    }
    /* TBD: is there a calendar date? :-)
    if uType.hasPrefix("TIMESTAMP WITH") { return CalendarDate.self }
    if uType.hasPrefix("DATETIME")       { return CalendarDate.self }
    if uType.hasPrefix("TIME")           { return TODO  }
    if uType.hasPrefix("DATE")           { return TODO }
    */
    return nil
  }
}
