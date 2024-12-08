//
//  CodeRelationship.swift
//  ZeeQL
//
//  Created by Helge Hess on 01/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol CodeRelationshipType : Relationship {
  // internal patch-helper since we can't refer to generic classes
  var sourceAttributeName : String? { get set }
  var targetAttributeName : String? { get set }
  var codeEntity : Entity? { get set }
}

open class CodeRelationshipBase<Target: SwiftObject>
             : ModelRelationship
{
  open var sourceAttributeName : String?
  open var targetAttributeName : String?
    // FIXME: rename
  
  override open var destinationEntity : Entity? {
    set {
      assert(newValue === destinationEntity,
             "cannot change destinationEntity of code relship: \(self)")
    }
    get {
      if let e = super.destinationEntity           { return e          }
      if let tot = Target.self as? EntityType.Type { return tot.entity }
      return nil // TBD: warn?
    }
  }
  
  override open var joins : [ Join ] { // Note: do not cache due to threading
    set { assert(false, "cannot set joins of code-attribute") }
    get {
      do {
        let join = try calculateJoin()
        return [ join ]
      }
      catch {
        // Note: to not log self, recursion!
        log.error("could not calculate join", error)
        #if DEBUG
          fatalError("could not calculate join: \(self) \(error)")
        #else
          return []
        #endif
      }
    }
  }
  
  enum JoinCalculationError : Swift.Error {
    case toManyHasNoSourceAttribute
    case toManyCouldNotDeriveTargetAttribute(entityName: String,
                                             column: String,
                                             sourceAttribute: Attribute,
                                             destinationEntity: Entity?)
    case toManyDidNotFindSourceAttribute(sourceAttributeName: String)
    
    case toOneHasNoTargetAttribute
    case toOneCouldNotDeriveForeignKey(entityName: String)
  }
  
  func calculateJoin() throws -> Join {
    // Code entities support a single join only
    let targetAttributeName : String
    let sourceAttributeName : String
    
    if isToMany {
      if let n = self.sourceAttributeName     { sourceAttributeName = n    }
      else if let pkey = sourcePrimaryKeyName { sourceAttributeName = pkey }
      else { throw JoinCalculationError.toManyHasNoSourceAttribute }
      
      if let n = self.targetAttributeName     { targetAttributeName = n    }
      else {
        // TODO: encapsulate this as 'lookupForeignKey'-something
        // TODO: support 'id' based naming schemes (where the pkey is id,
        //       combine to table_id for foreign-key
        
        // This is the foreign key in our tables. Now this gets funny, because
        // we usually want to match up *column* names, not attribute names.
        // Though it really depends whether you use the `table_id` naming
        // schema or just 'id'.
        
        if let sourceA = entity[attribute: sourceAttributeName] {
          // The primary key _column_ of the target, e.g. `company_id`
          // Do we have this as the column? (aka foreign key)?
          // But what if we name the columns 'id' in the database too. Say
          // Person.id and Address.id. We wouldn't want to match those?!
          
          let colname = sourceA.columnName ?? sourceA.name
          if let targetA = destinationEntity?[columnName: colname] {
            targetAttributeName = targetA.name
          }
          else {
            // OK, we hit this if both pkeys are named 'id'
            
            print("source attr is:", sourceA)
            throw JoinCalculationError.toManyCouldNotDeriveTargetAttribute(
              entityName: self.name, column: colname, sourceAttribute: sourceA,
              destinationEntity: destinationEntity
            )
          }
        }
        else {
          throw JoinCalculationError.toManyDidNotFindSourceAttribute(
                                       sourceAttributeName: sourceAttributeName)
        }
      }
    }
    else {
      // The automatics assume an 'owned' relationship, which is not necessarily
      // true. It could also be just a regular 1:1, but the user can always
      // specify the attributes manually.
      if let n = self.targetAttributeName     { targetAttributeName = n    }
      else if let pkey = targetPrimaryKeyName { targetAttributeName = pkey }
      else { throw JoinCalculationError.toOneHasNoTargetAttribute }
      
      if let n = self.sourceAttributeName     { sourceAttributeName = n    }
      else {
        // TODO: encapsulate this as 'lookupForeignKey'-something
        // TODO: support 'id' based naming schemes (where the pkey is id,
        //       combine to table_id for foreign-key
        
        // This is the foreign key in our tables. Now this gets funny, because
        // we usually want to match up *column* names, not attribute names.
        // Though it really depends whether you use the `table_id` naming
        // schema or just 'id'.
        
        if let targetA = destinationEntity?[attribute: targetAttributeName] {
          // The primary key _column_ of the target, e.g. `company_id`
          // Do we have this as the column? (aka foreign key)?
          
          if let srcA = entity[columnName: targetA.columnName ?? targetA.name] {
            sourceAttributeName = srcA.name
          }
          else {
            throw JoinCalculationError
                    .toOneCouldNotDeriveForeignKey(entityName: self.name)
          }
        }
        else {
          throw JoinCalculationError
                  .toOneCouldNotDeriveForeignKey(entityName: self.name)
        }
      }
    }
    
    if let sourceAttr = entity[attribute: sourceAttributeName],
       let targetAttr = destinationEntity?[attribute: targetAttributeName]
    {
      return Join(source: sourceAttr, destination: targetAttr)
    }
    else {
      return Join(source      : sourceAttributeName,
                  destination : targetAttributeName)
    }
  }

  
  // MARK: - helpers
  
  var sourcePrimaryKeyName : String? {
    guard let pkeys = entity.primaryKeyAttributeNames else { return nil }
    guard pkeys.count == 1 else { return nil }
    return pkeys[0]
  }
  var targetPrimaryKeyName : String? {
    guard let pkeys = destinationEntity?.primaryKeyAttributeNames
     else { return nil }
    
    guard pkeys.count == 1 else { return nil }
    return pkeys[0]
  }
  
  
  // MARK: - Description

  override open func appendJoinsToDescripton(_ ms: inout String) {
    do {
      let join = try calculateJoin()
      if joinSemantic != .innerJoin { ms += " \(joinSemantic)" }
      ms += " "
      ms += join.shortDescription
    }
    catch {
      ms += " JOIN-ERROR<\(error)>"
    }
  }
}

open class CodeRelationship<Target: DatabaseObject>
             : CodeRelationshipBase<Target>, CodeRelationshipType,
               TypedProperty
{
  public typealias T = Target
  
  public var codeEntity : Entity? = nil
  override open var entity : Entity {
    set {
      codeEntity = newValue
    }
    get {
      if let entity = codeEntity { return entity }
      fatalError("code entity has not been resolved!")
    }
  }

}


fileprivate let fakeEntity = ModelEntity(name: "FAKE")
  
/**
 * Defines a 1:1 relationship.
 *
 * Sample:
 *
 *     class Address : ActiveRecord, EntityType {
 *       class Entity : CodeEntityInfo {
 *         let id     = 1337
 *         let person = ToOne<Person>()
 *       }
 *       static let entity : ZeeQL.Entity = CodeEntity<Address>(Entity())
 *     }
 *
 */
open class ToOneRelationship<Target: DatabaseObject>: CodeRelationship<Target> {
  override open var isToMany : Bool {
    set { assert(!newValue,
                 "attempt to change to-many type of code relship \(self)") }
    get { return false }
  }
  
  public init(from sourceAttributeName : String? = nil,
              on   targetAttributeName : String? = nil)
  {
    super.init(name: "", isToMany: false, source: fakeEntity,
               destination: nil) // this MUST be dynamic to avoid recursion
    
    self.sourceAttributeName = sourceAttributeName
    self.targetAttributeName = targetAttributeName
  }
}
/**
 * Defines a 1:n relationship.
 *
 * Sample:
 *
 *     class Person : ActiveRecord, EntityType {
 *       class Entity : OGoCodeEntity {
 *         let table         = "person"
 *         let id            = Info.Int(column: "company_id")
 *
 *         let addresses     = ToMany<Address>()
 *       }
 *       static let entity : ZeeQL.Entity = CodeEntity<Person>(Entity())
 *     }
 */
open class ToManyRelationship<Target: DatabaseObject>: CodeRelationship<Target>{
  override open var isToMany : Bool {
    set { assert(newValue,
                 "attempt to change to-many type of code relship \(self)") }
    get { return true }
  }
  
  public init(from sourceAttributeName : String? = nil,
              on   targetAttributeName : String? = nil)
  {
    super.init(name: "", isToMany: true, source: fakeEntity,
               destination: nil) // this MUST be dynamic to avoid recursion
    
    self.sourceAttributeName = sourceAttributeName
    self.targetAttributeName = targetAttributeName
  }
}
