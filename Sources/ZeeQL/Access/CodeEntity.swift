//
//  CodeAttribute.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

#if canImport(Foundation)
import Foundation
#endif

open class CodeEntityBase : Entity {
  // Those are available in subclasses, which makes it convenient
  // (can't do this in Generic classes, hence this intermediate)
  public enum Attribute {
    public typealias Int            = CodeAttribute<Swift.Int>
    public typealias OptInt         = CodeAttribute<Swift.Int?>
    public typealias String         = CodeAttribute<Swift.String>
    public typealias NullableString = CodeAttribute<Swift.String?>
    public typealias OptString      = CodeAttribute<Swift.String?>
    #if canImport(Foundation)
    public typealias Date           = CodeAttribute<Foundation.Date>
    public typealias OptDate        = CodeAttribute<Foundation.Date?>
    #endif
  }
  public typealias Info = Attribute
  
  public typealias ToOne<T: DatabaseObject>  = ToOneRelationship<T>
  public typealias ToMany<T: DatabaseObject> = ToManyRelationship<T>
  
  public final var name                     : String = ""
  public final var externalName             : String?
  public final var className                : String? // TBD: Hm.
  public final var restrictingQualifier     : Qualifier?
  public final var fetchSpecifications      = [ String : FetchSpecification ]()

  public final var attributes               = Array<ZeeQL.Attribute>()
  public final var relationships            = [ Relationship  ]()
  public final var primaryKeyAttributeNames : [ String    ]? = nil

  public var objectType : DatabaseObject.Type? { return nil   }
  public var isPattern  : Bool                 { return false }
}

/**
 * CodeEntity objects are used to describe Entity objects (ORM table
 * mapping) from within Swift source code (opposed to doing this in an XML
 * file or fetching it from the database).
 *
 * Example usage:
 *
 *     class Person : ActiveRecord, EntityType {
 *       class Entity : CodeEntity<Person> {
 *         let table      = "person"
 *         let id         = Info.Int(column: "company_id")
 *         let isPerson   = Info.Int(column: "is_person")
 *
 *         let login      = Info.OptString(width: 50)
 *         let isLocked   = Info.Int(column: "is_locked")
 *         let number     = Info.String(width: 100)
 *
 *         let lastname   = Info.OptString(column: "name")
 *         let firstname  : String? = nil
 *         let middlename : String? = nil
 *
 *         let addresses  = ToMany<Address>() // auto: foreign-key
 *       }
 *       static let entity : ZeeQL.Entity = Entity()
 *     }
 *
 * One can use different styles to declare attributes:
 * - Arbitrary `Attribute` objects (`let id : ModelAttribute(...)`)
 * - CodeAttribute objects. `Attribute.Int` etc. are just aliases for this.
 * - Plain Swift types, like `let lastname : String`. If they are optional, that
 *   maps to 'nullable' on the SQL side.
 *   Note: Swift 3.0 requires instantiation of the object to do reflection,
 *         which implies that you have to initialize the property
 *         (hence `let id = 42` or `let middlename : String? = nil`)
 *
 * To define relationships:
 * - Use actual `Relationship` objects, like `ModelRelationship`
 * - Use `CodeRelationship` objects, like `ToMany<T>`
 *
 * Related: CodeObjectEntity<T>
 */
open class CodeEntity<T: DatabaseObject> : CodeEntityBase {

  override public var objectType : DatabaseObject.Type? { return T.self }
  
  // MARK: - Setup
  
  override public init() {
    // Note: Swift cannot reflect on a Type, the instance is required
    super.init()
    
    name       = "\(T.self)"
    className  = "\(T.self)"
    
    for m in Mirror(reflecting: self).mirrorHierarchy(stopAt: "CodeEntity") {
      processMirror(m)
    }
    
    primaryKeyAttributeNames = lookupPrimaryKeyAttributeNames()
  }
}


// MARK: - Directly work on class

public protocol CodeObjectType :
                  /* DatabaseObject, EntityType, implied by: */
                  TypedEntityObject
{
  init() // this is required for reflection
}

/**
 * CodeObjectEntity objects are used to describe Entity objects (ORM table
 * mapping) from within Swift source code (opposed to doing this in an XML
 * file or fetching it from the database).
 *
 * Example usage:
 *
 *     class Person : ActiveRecord, CodeObjectType {
 *       let id         = Value(column: "company_id")
 *       let isPerson   = Value.Int(column: "is_person")
 *
 *       let login      = Value.OptString(width: 50, nil)
 *       let isLocked   = Value.Int(column: "is_locked")
 *       let number     = Value.String(width: 100)
 *
 *       let lastname   = Value.OptString(column: "name")
 *
 *       // We can do this, but we don't get automagic KVC then:
 *       let firstname  : String? = nil
 *       let middlename : String? = nil
 *
 *       let addresses  = ToMany<Address>() // auto: foreign-key
 *     }
 *     static let entity : ZeeQL.Entity
 *                       = CodeObjectEntity<Person>(table: "person")
 *   }
 *
 * Note: Swift 3/4 requires instantiation of the object to do reflection,
 *       which implies that you have to initialize the properties!
 *       (hence `let id = 42` or `let middlename : String? = nil`)
 *
 * To define relationships:
 * - Use actual `Relationship` objects, like `ModelRelationship`
 * - Use `CodeRelationship` objects, like `ToMany<T>`
 *
 * Related: CodeEntity<T>
 */
open class CodeObjectEntity<T: CodeObjectType> : CodeEntityBase {
  
  override public var objectType : DatabaseObject.Type? { return T.self }
  
  // MARK: - Setup
  
  public init(table: String? = nil) {
    // Note: Swift cannot reflect on a Type, the instance is required
    super.init()
    
    name         = "\(T.self)"
    className    = "\(T.self)"
    externalName = table
    
    let prototype = T() // Swift needs to instantiate to do this
    
    for m in Mirror(reflecting: prototype)
               .mirrorHierarchy(stopAt: ActiveRecord.self)
    {
      processMirror(m)
    }
    
    primaryKeyAttributeNames = lookupPrimaryKeyAttributeNames()
    
    /// Resolve fetch specification entities.
    if !fetchSpecifications.isEmpty {
      for ( fsName, fs ) in fetchSpecifications where fs.entity == nil {
        assert(fs.entityName == self.name)
        if var fs = fs as? ModelFetchSpecification {
          fs.entity = self
          fetchSpecifications[fsName] = fs
        }
      }
    }
  }
}


// MARK: - Reflection

fileprivate let specialTableKey                = "table" // TBD
fileprivate let specialRestrictingQualifierKey = "_restrictingQualifier"
fileprivate let specialFetchSpecificationsKey  = "_fetchSpecifications"

fileprivate extension CodeEntityBase {

  private func processFetchSpecificationMirror(_ mirror: Mirror) {
    for ( propName, propValue ) in mirror.children {
      assert(propName != nil)
      assert(propValue is ModelFetchSpecification)
      guard let fs = propValue as? FetchSpecification, let name = propName else {
        continue
      }
      
      assert(fetchSpecifications[name] == nil, "Duplicate fetchspec: \(fs)")
      fetchSpecifications[name] = fs
    }
  }

  /**
   * Walk a Swift Mirror object and try to create `Attribute` and
   * `Relationship` objects for the properties found.
   *
   * Note: This inspects the actual values of an object! (i.e. Swift cannot
   *       reflect on a Type, just on an instance).
   *
   * Sideeffect: Results are pushed into the `attributes` and `relationships`
   *             properties of the `CodeEntityBase`.
   */
  func processMirror(_ mirror: Mirror) {
    // TODO: preserve them across processMirror invocations
    var nameToIdx    = [ String : Int ]()
    var relNameToIdx = [ String : Int ]()
    for i in 0..<attributes   .count { nameToIdx   [attributes   [i].name] = i }
    for i in 0..<relationships.count { relNameToIdx[relationships[i].name] = i }
    
    for ( propName, propValue ) in mirror.children {
      guard let propName = propName else { continue }
      
      if propName == specialTableKey, // || propname == "externalType",
         let v = propValue as? String
      {
        externalName = v
        continue
      }
      if propName == specialRestrictingQualifierKey {
        assert(propValue is Qualifier)
        if let v = propValue as? Qualifier {
          restrictingQualifier = v
          continue
        }
      }
      if propName == specialFetchSpecificationsKey {
        processFetchSpecificationMirror(Mirror(reflecting: propValue))
        continue
      }

      if let attribute = CodeAttributeFactory.attributeFor(property: propName,
                                                           value: propValue)
      {
        if let idx = nameToIdx[propName] {
          attributes[idx] = attribute // override
        }
        else {
          // Dupe cannot happen. I think :-) TODO: betta check
          attributes.append(attribute)
        }
      }
      else if let relship = propValue as? Relationship {
        if let mrelship = relship as? ModelRelationship {
          if mrelship.name.isEmpty {
            // hack in name
            mrelship.name = propName
          }
        }
        
        if let crelship = relship as? CodeRelationshipType {
          crelship.codeEntity = self
        }
        
        if let idx = relNameToIdx[propName] {
          relationships[idx] = relship // override
        }
        else {
          // Dupe cannot happen. I think :-) TODO: betta check
          relationships.append(relship)
        }
      }
      
      // TODO: fetch specifications, restrictingQualifier
    }
  }
}
