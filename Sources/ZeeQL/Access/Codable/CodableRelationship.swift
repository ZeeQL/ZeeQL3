//
//  CodableRelationship.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  
  // FIXME: I think those should be protocols, as the faults depend on the
  //        storage (may be even async?)
  //        But, no, we need to be able to specify the target type in the
  //        source, like: `var addresses : ToMany<Address>`
  
  /**
   * A container to maintain a ToOne relationship to a different object.
   *
   * This is usually used with the `ToOne` typealias, for example like this:
   *
   *     var owner : ToOne<Person>
   *
   * NOTE: This is *NOT* a `Relationship` object. It is more like a `Fault`
   *       and necessary because `Codable` doesn't deal with recursive
   *       relationships.
   */
  public struct ToOneRelationshipHolder<TargetType: CodableObjectType>
                  : Codable
  {
    // TODO: complete me
    // TBD: should this have a reference to the `Relationship` itself?
    
    public init(from decoder: Decoder) throws {
      if decoder is ReflectingDecoderType {
        // init is separate from reflection, we just need an empty object here
      }
      else {
        // TODO: later we need the actual decoder here (probably taking the EC)
        fatalError("unexpected decoder: \(decoder)")
      }
    }
  }
  
  /**
   * A container to maintain a ToMany relationship to a set of different
   * objects.
   *
   * This is usually used with the `ToMany` typealias, for example like this:
   *
   *     var addresses : ToMany<Address>
   *
   * NOTE: This is *NOT* a `Relationship` object. It is more like a `Fault`
   *       and necessary because `Codable` doesn't deal well with recursive
   *       relationships.
   */
  public struct ToManyRelationshipHolder<TargetType: CodableObjectType>
                  : Codable
  {
    // TODO: like a toMany fault?
    // TBD: should this have a reference to the `Relationship` itself?

    public init(from decoder: Decoder) throws {
      if decoder is ReflectingDecoderType {
        // init is separate from reflection, we just need an empty object here
      }
      else {
        // TODO: later we need the actual decoder here (probably taking the EC)
        fatalError("unexpected decoder")
      }
    }
  }
  
  /**
   * For more info on relationships, check the `ModelRelationship` superclass.
   *
   * The specific `DecodableRelationship` is used for implicit inline
   * relationships, like those:
   *
   *     class Property : Codable {
   *       var owner : Person // <= becomes a DecodableRelationship
   *     }
   */
  open class DecodableRelationship<TargetType : Decodable> : ModelRelationship {
    
    private var _isMandatory : Bool
    override open var isMandatory : Bool { return _isMandatory }

    init(name   : String, isToMany : Bool, isMandatory : Bool,
         source : CodableEntityType, destination : Entity?)
    {
      self._isMandatory = isMandatory
      super.init(name: name, isToMany: isToMany,
                 source: source, destination: destination)
    }
  }
  
  /**
   * For more info on relationships, check the `ModelRelationship` superclass.
   *
   * The specific `CodableObjectRelationship` is used when the
   * `CodableModelPostProcessor` has to create an inverse to-One relationship
   * for an implicit to-many relationship.
   *
   * For example:
   *
   *     class Person    : CodableObjectType {
   *       var addresses : [ Address ]
   *     }
   *     class Address   : CodableObjectType {
   *       var name1     : String?
   *
   *       // we create an implicit 'personId' attribute (the required foreign
   *       // key!) and a `person` relationship of type
   *       // `CodableObjectRelationship<Person>`.
   *     }
   *
   */
  open class CodableObjectRelationship<TargetType : CodableObjectType>
               : DecodableRelationship<TargetType>
  {
  }
  
  /**
   * For more info on relationships, check the `ModelRelationship` superclass.
   *
   * The specific `CodableObjectRelationshipS` is used when we decode explicit
   * relationships, like so:
   *
   *     class Property : Codable {
   *       var owner : ToOne<Person>
               // ^ becomes a CodableObjectRelationshipS<Property, Person>
   *     }
   *
   * When we decode those, we know both, the static source type and the static
   * target type.
   */
  open class CodableObjectRelationshipS<SourceType : Decodable,
                                        TargetType : CodableObjectType>
               : CodableObjectRelationship<TargetType>
  {
  }
  
  
  // MARK: - Internal Stuff
  
  extension ToOneRelationshipHolder : RelationshipHolderType {
    
    static func reflectTargetType(on state: CodableModelDecoder) throws
                  -> CodableEntityType
    {
      // This can also get the source type from the
      // EntityPropertyReflectionContainer.
      if !state.hasEntityForType(TargetType.self) {
        _ = try state.decode(TargetType.self) // reflect on target entity
      }
      
      let entity = state.lookupOrCreateTypedEntity(TargetType.self)
      return entity
    }
    
    static func makeRelationship<SourceType: Decodable>(
                                 name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 sourceType  : SourceType.Type,
                                 destination : CodableEntityType)
                  -> Relationship
    {
      // Create a typed relationship, this works because the
      // `ToOneRelationshipHolder` has the static type of the target as the
      // generic argument.
      let rs = CodableObjectRelationshipS<SourceType, TargetType>(
                 name: name, isToMany: false, isMandatory: !isOptional,
                 source: source, destination: destination)
      return rs
    }
  }
  
  extension ToManyRelationshipHolder : RelationshipHolderType {
    
    static func reflectTargetType(on state: CodableModelDecoder) throws
                  -> CodableEntityType
    {
      // This can also get the source type from the
      // EntityPropertyReflectionContainer.
      if !state.hasEntityForType(TargetType.self) {
        _ = try state.decode(TargetType.self) // reflect on target entity
      }
      
      let entity = state.lookupOrCreateTypedEntity(TargetType.self)
      return entity
    }
    
    static func makeRelationship<SourceType: Decodable>(
                                 name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 sourceType  : SourceType.Type,
                                 destination : CodableEntityType)
                  -> Relationship
    {
      // TBD: isOptional doesn't really matter here, right?
      let rs = CodableObjectRelationshipS<SourceType, TargetType>(
                 name: name, isToMany: true, isMandatory: !isOptional, // TBD
                 source: source, destination: destination)
      return rs
    }
  }
  
  internal protocol RelationshipHolderType {
    static func reflectTargetType(on decoder: CodableModelDecoder) throws
                  -> CodableEntityType
    static func makeRelationship<SourceType: Decodable>
                                (name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 sourceType  : SourceType.Type,
                                 destination : CodableEntityType)
                  -> Relationship
  }
#endif // swift(>=4.0)
