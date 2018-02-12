//
//  CodableEntity.swift
//  ZeeQL
//
//  Created by Helge Hess on 11.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  /**
   * `Entity` objects usually represent a database table or view. Entity objects
   * are contained in Model objects and are usually looked up by name.
   *
   * The `CodableEntityBase` implementation derives its data from a Swift type
   * supporting the `Codable` protocol.
   */
  open class CodableEntityBase : Entity {
    public final var name                     : String = ""
    public final var externalName             : String? = nil
    public final var className                : String? = nil // TBD: Hm.
    
    public final var attributes               = Array<ZeeQL.Attribute>()
    public final var relationships            = [ Relationship  ]()
    public final var primaryKeyAttributeNames : [ String    ]? = nil

    public final var classPropertyNames : [ String ]? = [ String ]()

    public       var isPattern                : Bool { return false }
    
    open         var objectType : DatabaseObject.Type? { return nil }
      // TBD: we may need to adjust the type of this in Entity
    
    public init() {
    }
    
    
    // MARK: - Type Safe Factory (overridden by typed class)
    
    internal func makeToOneRelationship(name: String,
                                        from sourceEntity: CodableEntityType,
                                        sourceAttribute sa: Attribute,
                                        destinationAttribute da: Attribute)
                  -> ModelRelationship
    {
      // NOTE: This has to be in here to make polymorphism work!
      let rs = ModelRelationship(name: name, isToMany: false,
                                 source: sourceEntity, destination: self)
      rs.joins = [ Join(source: sa, destination: da) ]
      return rs
    }
  }
  
  internal protocol CodableEntityType : Entity {
    // This is what we patch as part of the decoding reflection.
    // And that also works with non-static ModelEntities
    var primaryKeyAttributeNames : [ String       ]? { set get }
    var attributes               : [ Attribute    ]  { set get }
    var relationships            : [ Relationship ]  { set get }
    var classPropertyNames       : [ String       ]? { set get }
    func makeToOneRelationship(name: String,
                               from sourceEntity: CodableEntityType,
                               sourceAttribute sa: Attribute,
                               destinationAttribute da: Attribute)
           -> ModelRelationship
  }
  extension CodableEntityBase : CodableEntityType {}
  extension ModelEntity       : CodableEntityType {} // not necessary
  extension CodableEntityType {
    internal func makeToOneRelationship(name: String,
                                        from sourceEntity: CodableEntityType,
                                        sourceAttribute sa: Attribute,
                                        destinationAttribute da: Attribute)
                  -> ModelRelationship
    {
      let rs = ModelRelationship(name: name, isToMany: false,
                                 source: sourceEntity, destination: self)
      rs.joins = [ Join(source: sa, destination: da) ]
      return rs
    }
    
    internal func replaceTemporaryEntity(_    oldEntity : CodableEntityType,
                                         with newEntity : CodableEntityType)
    {
      let log = globalZeeQLLogger
      guard oldEntity !== newEntity else { return } // same
      for rs in relationships {
        if rs.entity === oldEntity {
          if let mrs = rs as? ModelRelationship {
            mrs.entity = newEntity
          }
          else {
            log.warn("could not replace temporary entity in relationship:", rs)
          }
        }
        if rs.destinationEntity === oldEntity {
          if let mrs = rs as? ModelRelationship {
            mrs.destinationEntity = newEntity
          }
          else {
            log.warn("could not replace temporary entity in relationship:", rs)
          }
        }
      }
    }
  }

  open class CodableObjectEntity<T: CodableObjectType> : CodableEntityBase {
    
    override open var objectType : DatabaseObject.Type? { return T.self }
    
    // MARK: - Setup
    
    public init(name: String? = nil, className: String? = nil) {
      super.init()
      self.name       = name      ?? "\(T.self)"
      self.className  = className ?? "\(T.self)"
    }

    
    // MARK: - Type Safe Factory
    
    override internal
    func makeToOneRelationship(name                    : String,
                               from sourceEntity       : CodableEntityType,
                               sourceAttribute      sa : Attribute,
                               destinationAttribute da : Attribute)
           -> ModelRelationship
    {
      let isOptional = sa.allowsNull ?? true // TBD
      let rs = CodableRelationship<T>(name: name, isToMany: false,
                                      isMandatory: !isOptional,
                                      source: sourceEntity,
                                      destination: self)
      rs.joins = [ Join(source: sa, destination: da) ]
      return rs
    }
  }
#endif // swift(>=4.0)
