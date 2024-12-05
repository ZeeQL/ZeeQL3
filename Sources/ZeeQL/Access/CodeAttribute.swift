//
//  CodeAttribute.swift
//  ZeeQL
//
//  Created by Helge Hess on 01/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * CodeAttribute objects are used to describe properties of Entity objects
 * (which then become columns in the database) from within Swift source code
 * (opposed to doing this in an XML file or fetching it from the database).
 *
 * Their primary feature over `ModelAttribute`s is that such are generic over
 * the value type.
 */
open class CodeAttribute<T: AttributeValue> : ModelAttribute {
  
  // Note: we remove the keyword
  @inlinable
  public init(_ name       : String? = nil,
              column       : String? = nil,
              externalType : String? = nil,
              width        : Int?    = nil,
              defaultValue : T?      = nil)
  {
    super.init(name: name ?? "",
               column: column, externalType: externalType,
               allowsNull: T.isOptional, width: width)
    
    self.valueType = T.isOptional ? T.optionalBaseType : T.self
    
    if let v = defaultValue {
      self.defaultValue = v
    }
  }
}


// MARK: - Typesafe Qualifier Building

public protocol SQLLikeType {}
extension String   : SQLLikeType {}
extension Optional : SQLLikeType where Wrapped: SQLLikeType {}

public extension CodeAttribute where T : SQLLikeType {
  
  @inlinable
  func like(_ pattern : String) -> KeyValueQualifier {
    let key = AttributeKey(self)
    return KeyValueQualifier(key, .Like, pattern)
  }  
}


enum CodeAttributeFactory {
  // Note: We could refer to the type, but there is little reason to invoke
  //       the functions all the time? Just store the values.
  
  /**
   * Attempt to create an `Attribute` object for the given value. The value can
   * be a 'real' value taken from an object, or a special thing, like an
   * `AnnotatedAttributeValue`.
   *
   * This checks:
   * - Is the value an `Attribute` already? If so, use it.
   * - Is the value an `AnnotatedAttributeValue`? Use the contained `Attribute`.
   * - String, Int, Bool, Float, Double - also use the value as the default!
   * - `AttributeValue`?
   */
  static func attributeFor(property: String, value: Any) -> Attribute? {
    if let attr = value as? Attribute { // an actual Attribute already
      if let mattr = attr as? ModelAttribute {
        // hack-in property name
        if mattr.name.isEmpty { mattr.name = property }
        return mattr
      }
      return attr
    }
    
    if let av = value as? AnnotatedAttributeValue {
      let attr = av.attribute
      if let mattr = attr as? ModelAttribute {
        // hack-in property name
        if mattr.name.isEmpty { mattr.name = property }
        return mattr
      }
      return attr
    }
    
    switch value {
      // TBD: is this superfluous wrt `AttributeValue` below?
      case let defaultValue as String:
        return CodeAttribute<String>(property, defaultValue: defaultValue)
      case let defaultValue as Int:
        return CodeAttribute<Int>(property, defaultValue: defaultValue)
      case let defaultValue as Bool:
        return CodeAttribute<Bool>(property, defaultValue: defaultValue)
      case let defaultValue as Float:
        return CodeAttribute<Float>(property, defaultValue: defaultValue)
      case let defaultValue as Double:
        return CodeAttribute<Double>(property, defaultValue: defaultValue)
      // TODO: add the rest

      case let defaultValue as AttributeValue:
        // We could just do AttributeInfo<AttributeValue>, but that is not really
        // what we want here. We want to have the specific type.
        // Well, actually that doesn't fly in Swift 3.
        
        // TODO: defaultValue
        
        if let baseType = defaultValue.optionalBaseType {
          
          switch baseType {
            case is String.Type: return CodeAttribute<String?>(property)
            case is Int.Type:    return CodeAttribute<Int?>   (property)
            case is Bool.Type:   return CodeAttribute<Bool?>  (property)
            case is Float.Type:  return CodeAttribute<Float?> (property)
            case is Double.Type: return CodeAttribute<Double?>(property)
            // TODO: add the rest
            default:
              fatalError("did not map optional AttributeValue? of " +
                         "property \(property): \(defaultValue) \(baseType)")
          }
        }
        else {
          fatalError("did not map AttributeValue? of property \(property): " +
                     "\(defaultValue)")
        }

      default:
        return nil
    }
  }
}

