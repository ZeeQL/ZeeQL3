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
   * NOTE: This is *NOT* a `Relationship` object. It is more like a `Fault`
   *       and necessary because `Codable` doesn't deal with recursive
   *       relationships.
   */
  public struct ToOneRelationshipHolder<T: CodableObjectType> : Codable {
    // TODO: complete me
    // TBD: should this have a reference to the `Relationship` itself?
    
    public init(from decoder: Decoder) throws {
      if decoder is CodableModelDecoder {
        // init is separate from reflection, we just need an empty object here
      }
      else {
        // TODO: later we need the actual decoder here (probably taking the EC)
        fatalError("unexpected decoder")
      }
    }
  }
  
  /**
   * A container to maintain a ToMany relationship to a set of different
   * objects.
   *
   * NOTE: This is *NOT* a `Relationship` object. It is more like a `Fault`
   *       and necessary because `Codable` doesn't deal with recursive
   *       relationships.
   */
  public struct ToManyRelationshipHolder<T: CodableObjectType> : Codable {
    // TODO: like a toMany fault?
    // TBD: should this have a reference to the `Relationship` itself?

    public init(from decoder: Decoder) throws {
      if decoder is CodableModelDecoder {
        // init is separate from reflection, we just need an empty object here
      }
      else {
        // TODO: later we need the actual decoder here (probably taking the EC)
        fatalError("unexpected decoder")
      }
    }
  }
  
  open class CodableRelationship<Target: CodableObjectType>
               : ModelRelationship
  {
    private var _isMandatory : Bool
    override open var isMandatory : Bool { return _isMandatory }

    init(name   : String, isToMany : Bool, isMandatory : Bool,
         source : CodableEntityType, destination : Entity)
    {
      self._isMandatory = isMandatory
      super.init(name: name, isToMany: isToMany,
                 source: source, destination: destination)
    }
  }
  
  open class DecodableRelationship<Target: Decodable> : ModelRelationship {
    // We have this just for the mandatory overload. It is used for inline
    // relationships.
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
  
  
  // MARK: - Internal Stuff
  
  extension ToOneRelationshipHolder : RelationshipHolderType {
    
    static func reflectTargetType(on decoder: CodableModelDecoder) throws
                  -> CodableEntityType
    {
      if !decoder.hasEntityForType(T.self) {
        _ = try decoder.decode(T.self) // reflect on target entity
      }
      
      guard let _ = decoder.currentEntity else {
        throw CodableModelDecoder.Error.missingEntity
      }
      
      let entity = decoder.lookupOrCreateTypedEntity(T.self)
      return entity
    }
    
    static func makeRelationship(name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 destination : CodableEntityType)
                  -> Relationship
    {
      // Create a typed relationship, this works because the
      // `ToOneRelationshipHolder` has the static type of the target as the
      // generic argument.
      let rs = CodableRelationship<T>(name: name, isToMany: false,
                                      isMandatory: !isOptional,
                                      source: source, destination: destination)
      return rs
    }
  }
  
  extension ToManyRelationshipHolder : RelationshipHolderType {
    
    static func reflectTargetType(on decoder: CodableModelDecoder) throws
                  -> CodableEntityType
    {
      if !decoder.hasEntityForType(T.self) {
        _ = try decoder.decode(T.self) // reflect on target entity
      }
      
      guard let _ = decoder.currentEntity else {
        fatalError("no entity?")
      }
      
      let entity = decoder.lookupOrCreateTypedEntity(T.self)
      return entity
    }
    
    static func makeRelationship(name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 destination : CodableEntityType)
                  -> Relationship
    {
      // TBD: isOptional doesn't really matter here, right?
      let rs = CodableRelationship<T>(name: name, isToMany: true,
                                      isMandatory: !isOptional, // TBD
                                      source: source, destination: destination)
      return rs
    }
  }
  
  internal protocol RelationshipHolderType {
    static func reflectTargetType(on decoder: CodableModelDecoder) throws
                  -> CodableEntityType
    static func makeRelationship(name        : String,
                                 isOptional  : Bool,
                                 source      : CodableEntityType,
                                 destination : CodableEntityType)
                  -> Relationship
  }
#endif // swift(>=4.0)
