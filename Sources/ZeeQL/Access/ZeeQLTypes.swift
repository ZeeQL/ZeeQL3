//
//  ZeeQLTypes.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.Date
import struct Foundation.Data
import struct Foundation.Decimal
import struct Foundation.UUID

public enum ZeeQLTypes {
  // All this really belongs into the adaptors, but the basic stuff is all the
  // same for SQL.
  // Update: Yes, but even the adaptors share using this thing. It is also
  //         used in SQLExpression
  
  /**
   * Returns a SQL type for the given Swift type (_name_). 
   *
   * E.g. "INT" for an "Int". Or "VARCHAR" for "String".
   *
   * Do not overuse this, bad stylez :-)
   */
  public static func externalTypeFor(swiftType: String) -> String? {
    switch swiftType {
      case "Int"     : return "INT"
      case "String"  : return "VARCHAR"
      case "Float"   : return "FLOAT"
      case "Double"  : return "DOUBLE"
      case "Bool"    : return "BOOLEAN"
      case "Data"    : return "BLOB"
      case "Date"    : return "TIMESTAMP"
      case "Decimal" : return "NUMERIC"
      case "UUID"    : return "UUID"
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
  public static func externalTypeFor(swiftType: Any.Type,
                                     includeConstraint: Bool = false)
                     -> String?
  {
    // Also used by ActiveRecord.reflectedEntity
    if includeConstraint {
      if swiftType == Int    .self { return "INT NOT NULL"       }
      if swiftType == String .self { return "VARCHAR NOT NULL"   }
      if swiftType == Float  .self { return "FLOAT NOT NULL"     }
      if swiftType == Double .self { return "DOUBLE NOT NULL"    }
      if swiftType == Data   .self { return "BLOB NOT NULL"      }
      if swiftType == Date   .self { return "TIMESTAMP NOT NULL" }
      if swiftType == Int    .self { return "INT NOT NULL"       }
      if swiftType == Bool   .self { return "BOOLEAN NOT NULL"   }
      if swiftType == Decimal.self { return "NUMERIC NOT NULL"   }
      if swiftType == UUID   .self { return "UUID NOT NULL"      }

      if swiftType == Optional<Int>    .self { return "INT NULL"       }
      if swiftType == Optional<String> .self { return "VARCHAR NULL"   }
      if swiftType == Optional<Float>  .self { return "FLOAT NULL"     }
      if swiftType == Optional<Double> .self { return "DOUBLE NULL"    }
      if swiftType == Optional<Data>   .self { return "BLOB NULL"      }
      if swiftType == Optional<Date>   .self { return "TIMESTAMP NULL" }
      if swiftType == Optional<Int>    .self { return "INT NULL"       }
      if swiftType == Optional<Bool>   .self { return "BOOLEAN NULL"   }
      if swiftType == Optional<Decimal>.self { return "NUMERIC NULL"   }
      if swiftType == Optional<UUID>   .self { return "UUID NULL"      }
    }
    else {
      if swiftType == Int    .self { return "INT"       }
      if swiftType == String .self { return "VARCHAR"   }
      if swiftType == Float  .self { return "FLOAT"     }
      if swiftType == Double .self { return "DOUBLE"    }
      if swiftType == Data   .self { return "BLOB"      }
      if swiftType == Date   .self { return "TIMESTAMP" }
      if swiftType == Int    .self { return "INT"       }
      if swiftType == Bool   .self { return "BOOLEAN"   }
      if swiftType == Decimal.self { return "NUMERIC"   }
      if swiftType == UUID   .self { return "UUID"      }

      if swiftType == Optional<Int>    .self { return "INT"       }
      if swiftType == Optional<String> .self { return "VARCHAR"   }
      if swiftType == Optional<Float>  .self { return "FLOAT"     }
      if swiftType == Optional<Double> .self { return "DOUBLE"    }
      if swiftType == Optional<Data>   .self { return "BLOB"      }
      if swiftType == Optional<Date>   .self { return "TIMESTAMP" }
      if swiftType == Optional<Int>    .self { return "INT"       }
      if swiftType == Optional<Bool>   .self { return "BOOLEAN"   }
      if swiftType == Optional<Decimal>.self { return "NUMERIC"   }
      if swiftType == Optional<UUID>   .self { return "UUID"      }
    }
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
      if uType.hasPrefix("VARCHAR")   { return Optional<String> .self }
      if uType.hasPrefix("INT")       { return Optional<Int>    .self }
      if uType.hasPrefix("DOUBLE")    { return Optional<Double> .self }
      if uType.hasPrefix("FLOAT")     { return Optional<Float>  .self }
      if uType.hasPrefix("TEXT")      { return Optional<String> .self }
      if uType.hasPrefix("TIMESTAMP") { return Optional<Date>   .self }
      if uType.hasPrefix("BLOB")      { return Optional<Data>   .self }
      if uType.hasPrefix("CLOB")      { return Optional<String> .self }
      if uType.hasPrefix("BOOL")      { return Optional<Bool>   .self }
      if uType.hasPrefix("BYTEA")     { return Optional<Data>   .self }
      if uType.hasPrefix("NUMERIC")   { return Optional<Decimal>.self }
      if uType.hasPrefix("BPCHAR")    { return Optional<String> .self }
      if uType.hasPrefix("UUID")      { return Optional<UUID>   .self }
    }
    else {
      if uType.hasPrefix("VARCHAR")   { return String .self }
      if uType.hasPrefix("INT")       { return Int    .self }
      if uType.hasPrefix("DOUBLE")    { return Double .self }
      if uType.hasPrefix("FLOAT")     { return Float  .self }
      if uType.hasPrefix("TEXT")      { return String .self }
      if uType.hasPrefix("TIMESTAMP") { return Date   .self }
      if uType.hasPrefix("BLOB")      { return Data   .self }
      if uType.hasPrefix("CLOB")      { return String .self }
      if uType.hasPrefix("BOOL")      { return Bool   .self }
      if uType.hasPrefix("BYTEA")     { return Data   .self }
      if uType.hasPrefix("NUMERIC")   { return Decimal.self }
      if uType.hasPrefix("BPCHAR")    { return String .self }
      if uType.hasPrefix("UUID")      { return UUID   .self }
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
