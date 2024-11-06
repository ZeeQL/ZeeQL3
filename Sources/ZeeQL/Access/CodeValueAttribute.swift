//
//  CodeValueAttribute.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

#if canImport(Foundation)
import Foundation
#endif

/**
 * CodeValueAttribute objects are used to describe properties of Entity objects
 * (which then become columns in the database) from within Swift source code
 * (opposed to doing this in an XML file or fetching it from the database).
 *
 * CodeValueAttribute's box the storage of the model property. For example:
 *
 *     class Address : ActiveRecord, CodeObjectType {
 *       let street = Value.String()
 *     }
 *
 * Advantages:
 * - with the boxing we can make them `KeyValueCodingTargetValue`, that is:
 *   we get proper KVC for free!
 *
 * Disadvantages:
 * - we construct the model information from scratch for every single instance
 *   we allocate
 *
 * Summary: I think for simple stuff this may be good enough to have DRY, but
 *          a real setup should probably define the Entity using the regular
 *          `CodeEntity`.
 */
open class CodeValueAttribute<T: AttributeValue>
             : KeyValueCodingBox<T>, AnnotatedAttributeValue
{
  // TODO: We still copy the ModelAttribute for every single key!!!
  // Note: a class not a struct to support `KeyValueCodingTargetValue`
  
  public let attribute : Attribute
  
  // Note: we remove the keyword
  public init(_ name       : String? = nil,
              column       : String? = nil,
              externalType : String? = nil,
              width        : Int?    = nil,
              _ v          : T)
  {
    let ma = ModelAttribute(name: name ?? "",
                            column: column, externalType: externalType,
                            allowsNull: T.isOptional, width: width)
    ma.valueType    = T.isOptional ? T.optionalBaseType : T.self
    ma.defaultValue = v
    attribute = ma
    
    super.init(v)
  }
  public init(attribute: Attribute, value: T) {
    self.attribute = attribute
    super.init(value)
  }
  
  
}

// convenience accessors
public extension ActiveRecord {
  // It used to be this, but if we invoke a function we can do more neat
  // stuff, like assign default values, cache, and select proper types:
  //
  //     public typealias Int = CodeValueAttribute<Swift.Int>
  //
  
  enum Value {
    static func box<T>(name         : Swift.String? = nil,
                       column       : Swift.String? = nil,
                       externalType : Swift.String? = nil,
                       width        : Swift.Int?    = nil,
                       value        : T)
                -> CodeValueAttribute<T>
    {
      // In here we could cache, or build as-efficient-as-possible variants.
      // Note:
      // TODO: the name is hacked in later!
      let ma = ModelAttribute(name: name ?? "",
                              column: column, externalType: externalType,
                              allowsNull: T.isOptional, width: width)
      ma.valueType = T.isOptional ? T.optionalBaseType : T.self
      return CodeValueAttribute(attribute: ma, value: value)
    }
    
    public static func Int(name         : Swift.String? = nil,
                           column       : Swift.String? = nil,
                           externalType : Swift.String? = nil,
                           _ value      : Swift.Int     = -1)
                       -> CodeValueAttribute<Swift.Int>
    {
      return box(name: name, column: column, externalType: externalType,
                 value: value)
    }
    public static func OptInt(name         : Swift.String? = nil,
                              column       : Swift.String? = nil,
                              externalType : Swift.String? = nil,
                              _ value      : Swift.Int?    = nil)
                       -> CodeValueAttribute<Swift.Int?>
    {
      return box(name: name, column: column, externalType: externalType,
                 value: value)
    }

    public static func String(name         : Swift.String? = nil,
                              column       : Swift.String? = nil,
                              externalType : Swift.String? = nil,
                              width        : Swift.Int?    = nil,
                              _ value      : Swift.String  = "")
                       -> CodeValueAttribute<Swift.String>
    {
      return box(name: name, column: column,
                 externalType: externalType, width: width,
                 value: value)
    }
    
    public static func OptString(name         : Swift.String? = nil,
                                 column       : Swift.String? = nil,
                                 externalType : Swift.String? = nil,
                                 width        : Swift.Int?    = nil,
                                 _ value      : Swift.String? = nil)
                       -> CodeValueAttribute<Swift.String?>
    {
      return box(name: name, column: column,
                 externalType: externalType, width: width,
                 value: value)
    }

    #if canImport(Foundation)
    public static func Date(name         : Swift.String? = nil,
                            column       : Swift.String? = nil,
                            externalType : Swift.String? = nil,
                            _ value      : Foundation.Date = Foundation.Date())
                       -> CodeValueAttribute<Foundation.Date>
    {
      return box(name: name, column: column,
                 externalType: externalType,
                 value: value)
    }
    
    public static func OptDate(name         : Swift.String?    = nil,
                               column       : Swift.String?    = nil,
                               externalType : Swift.String?    = nil,
                               width        : Swift.Int?       = nil,
                               _ value      : Foundation.Date? = nil)
                       -> CodeValueAttribute<Foundation.Date?>
    {
      return box(name: name, column: column,
                 externalType: externalType, width: width,
                 value: value)
    }
    #endif // canImport(Foundation)
  }
}

public protocol AnnotatedAttributeValue {
  var attribute : Attribute { get }
}

public enum CodeValueAttributeError : Swift.Error { // cannot nest in generic
  case CannotSetValue(AttributeValue.Type, Attribute, Any?)
}
