//
//  EntityPropertyReflectionContainer.swift
//  ZeeQL3
//
//  Created by Helge Hess on 27.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  public protocol CodableObjectType : Codable, DatabaseObject {
    // TODO: This only conforms to (full) `DatabaseObject` for Entity.objectType
    //       - we may want to change this.
    // Notes:
    // - this needs a custom `changesFromSnapshot(_:)`
    //   - as used when creating an adaptor operation in DatabaseChannel
    // - this cannot support `updateFromSnapshot(_:)` via Codable, Codable has
    //   no operations for that. But apparently we don't currently use this
    
    /* Weird Swift 4 build issue: When I move this into CodeableEntity.swift,
     * or CodableObjectType.swift,
     * Swift insists that I qualify the generic class (i.e. ToOneRelH<T>):
     * CodableEntity.swift:11:24: error: reference to generic type
     *                    'ToOneRelationshipHolder' requires arguments in <...>
     *   typealias ToOne  = ToOneRelationshipHolder
     *   ^
     *      <<T: CodableObjectType>>
     * CodableRelationship.swift:10:17: note: generic type
     *    'ToOneRelationshipHolder' declared here
     *   public struct ToOneRelationshipHolder<T: CodableObjectType> : Codable {
     */
    
    typealias ToOne  = ToOneRelationshipHolder
    typealias ToMany = ToManyRelationshipHolder
  }
  
  internal extension CodableModelDecoder {
  
    /**
     * This container is used when reflecting on the properties of a Entity
     * backed type (e.g. `Person`).
     * That is, the container which is used by the synthesized Codable.
     *
     * This container can contain:
     * - plain properties, like `let name : String`
     * - optional properties, like `let age : Int?`
     * - implicit relationships, like `let owner : Person?`
     * - explicit relationships, like `let owner : ToOne<Person>`
     */
    final class EntityPropertyReflectionContainer<EntityType : Decodable,
                                                  Key        : CodingKey>
                  : KeyedDecodingContainerProtocol
    {
      var codingPathKK : String {
        return codingPath.map { $0.stringValue }.joined(separator: ".")
      }
      
      let log        : ZeeQLLogger
      let decoder    : CodableModelEntityDecoder<EntityType>
      let codingPath : [ CodingKey ]
      
      let entity     : CodableEntityType
        // yes, when creating the container, we do not actually know the type
        // which is being decoded!
      
      let allKeys    : [ Key ] = []
        // can be queried by the type, we cannot answer that, we depend on the
        // type asking us for keys :-)
      
      private class NilKeySet { // you wonder why, right? go figure! ;-)
        var set = Set<String>()
        
        func insert  (_ key: Key) { set.insert(key.stringValue) }
        func contains(_ key: Key) -> Bool {
          return set.contains(key.stringValue)
        }
      }
      private let nilKeys = NilKeySet()
      
      init(decoder    : CodableModelEntityDecoder<EntityType>,
           entity     : CodableEntityType,
           codingPath : [ CodingKey ] = [])
      {
        self.decoder    = decoder
        self.codingPath = codingPath
        self.log        = decoder.log
        self.entity     = entity
      }
      
      func contains(_ key: Key) -> Bool {
        // called by decodeIfPresent() - which is used for stuff like `age:Int?`
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                  "\(codingPathKK)]:contains:",
                  key.stringValue)
        return true
      }
      
      
      // MARK: - Non-Basetype Objects
      
      /**
       * The main *type erased!* decoding functions for types which are not base
       * types.
       *
       * Remember that Swift won't dispatch dynamically on `T`. Hence the manual
       * checks inline.
       *
       * Arrays: There are two kinds of arrays we want to support:
       *         - base types column arrays, like `[Int]`,
       *         - arrays of CodableObjectType`s aka relationships
       */
      func decode<T>(_ type: T.Type, forKey key: Key) throws -> T
             where T : Decodable
      {
        switch type {
          case is RelationshipHolderType.Type:
            return try decodeRelationshipHolder(erasedHolderType: type,
                                                forKey: key)
          
          case is CodableObjectType.Type:
            return try decodeCodableObject(type, forKey: key)
          
          // TODO: support all combinations :-)
          // TBD: Can we do Array<AttributeValue>?
          //      Maybe via conditional conformance in 4.1?
          case is Array<Int>.Type:
            return try decodeBaseTypeArray(type, Int.self, forKey: key)
          
          default:
            // Note: This does not fly!:
            //         case let atype as Array<CodableObjectType>.Type
            //       the type is something concrete, like Array<Person>
            
            // OK: Deal with arrays and other objects we don't directly
            //     control.
            return try decodeOtherType(type, forKey: key)
        }
      }
      
      func decodeOtherType<T>(_ type: T.Type, forKey key: Key) throws -> T
             where T : Decodable
      {
        // effectively this is: `decodeCodableObjectArray<T>`
        log.trace("out of band type:", type, "for key:", key)
        
        /*
         This is tricky. We need to communicate to the decoder, that we are
         decoding a property.
         What do we want? We want to collect relationship types. I.e. this:
           var addresses : [ Address ]
         we want to add to the `entity` of this containers entity, the
         class property `addresses` as a ToMany<Address>.
         So how do we do this?
         We somehow need to track, that we decoded an [ CodingType ]?
         */
        
        decoder.codingPath.append(key) // this is the key we are going to use
        //let v = try decoder.decode(type)
        let v = try type.init(from: decoder) // init the ('array' expected)
        decoder.codingPath.removeLast()
        
        #if false
          if let cota = v as? Array<CodableObjectType> {
            // ^^ we can't dispatch on the static type. But we *can* dispatch on
            //    the dynamic type :-)
            // Maybe we can handle this earlier, but at least in here, we know
            // the proper type.
            // => We should probably handle it earlier.
            print("TODO: it is an array of CodableObjectType!")
          }
        #endif
        
        return v
      }

      /**
       * Decode base type column arrays, like `[Int]`
       */
      func decodeBaseTypeArray<T, E>(_ type: T.Type,
                                     _ elementType: E.Type,
                                     forKey key: Key) throws -> T
             where T : Decodable
      {
        log.error("TODO: Array<Int>")
        throw Error.unsupportedValueType(type)
      }

      /**
       * This decodes a `ToMany` or `ToOne` wrapper object.
       *
       * `erasedHolderType` and `reflectedHolderType` refer to the same
       * `ToOne` or `ToMany` type.
       * The first is just the typed erased version (generic `Decodable`),
       * while the other was reflected on.
       */
      private
      func decodeRelationshipHolder<T>(erasedHolderType : T.Type,
                                       forKey key       : Key) throws -> T
             where T : Decodable
      {
        guard let reflectedHolderType =
                    erasedHolderType as? RelationshipHolderType.Type
        else {
          throw Error.unexpectedRelationshipHolderType
        }
        
        // e.g. ToManyRelationshipHolder<T>
        log.trace("\("  " * codingPath.count)",
                  "KC[\(entity.name):\(codingPathKK)]:",
                  "decode `RelationshipHolderType`:",
                  key.stringValue, erasedHolderType)
        
        // In here because we need the key for the relship name
        let targetEntity =
              try reflectedHolderType.reflectTargetType(on: decoder.state)
          // make sure the target is there (no recursion because we unique,
          // but this may be different if we do free-form)
        
        let name = nameForKey(key)
        //let extName = key.stringValue == name ? nil : key.stringValue
        
        if entity[relationship: name] == nil {
          let rs : Relationship =
            reflectedHolderType.makeRelationship(name: name,
                                   isOptional: nilKeys.contains(key),
                                   source: entity, destination: targetEntity)
            // TODO: push extName for constraint?
          
          entity.relationships.append(rs)
          // entity.attributes.append(makeAttribute(type, forKey: key))
          entity.addClassPropertyName(nameForKey(key))
        }
        else {
          log.error("already registered relationship:", name, "in", entity)
        }
        
        // The `To-x-RelationshipHolder` objects have special support for our
        // coder, so this is a little easier.
        return try erasedHolderType.init(from: decoder) // we need some init
      }
      
      /**
       * This decodes a `CodableObjectType` when it is used inline (aka is type
       * erased).
       * For example:
       *
       *     class House { var owner : Person }
       *
       * It calls into `decoder.decode()` to do its job.
       */
      private func decodeCodableObject<T>(_ type: T.Type,
                                          forKey key: Key) throws -> T
             where T : Decodable
      {
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                  "\(codingPathKK)]:decode:", key.stringValue, type)
      
        let name = nameForKey(key)
        if entity[relationship: name] == nil {
          // TBD: The container is type erased wrt CodableObjectType. Can we
          //      still somehow ask the Type to make the relationship, like
          //      above?
          let destEntity = decoder.state.existingEntityForType(type)
          let rs = DecodableRelationship<T>(name: name, isToMany: false,
                                            isMandatory : !nilKeys.contains(key),
                                            source      : entity,
                                            destination : destEntity)
            // TODO: push extName for constraint?
          log.trace("\("  " * codingPath.count)KC[\(entity.name): created:", rs)
          
          entity.relationships.append(rs)
          // entity.attributes.append(makeAttribute(type, forKey: key))
          entity.addClassPropertyName(name)
        }
        else {
          log.log("already registered relationship:", name, "in", entity)
        }

        
        // let the main decoder handle this
        decoder.codingPath.append(key)
        let v = try decoder.state.decode(type) // TODO: replace?
        decoder.codingPath.removeLast()
        
        
        // post process relationship
      
        if let rs = entity[relationship: name],
           let mrs = rs as? ModelRelationship,
           mrs.destinationEntity == nil
        {
          // we didn't have the entity yet
          if let targetEntity = decoder.state.existingEntityForType(type) {
            mrs.destinationEntity = targetEntity
          }
          else {
            // register the relship for patching
            log.trace("did not decode target relationship, register:",
                      name, "in", entity)
            decoder.state.registerForPendingEntity(type, relationship: mrs)
          }
        }
      
        return v
      }
      
      /**
       * Extract the property (attribute or relationship) name of the key.
       * Ideally this would be the Swift property name, but it looks we can't
       * grab that anymore in 4.1 :-<
       */
      func nameForKey(_ key: Key) -> String {
        #if swift(>=4.1)
          // Description gives:
          //
          //   CodingKeys(stringValue: "id", intValue: nil)
          //
          // This is not really what we want, we want to reflect the original
          // key.
          // But maybe this has to do for now (and we should do it on 4.0 too.
          #if true // we want this as the external name
            return key.stringValue
          #else
            return "\(key)" // was stretched and fails on 4.1.snapshot
          #endif
        #else
          return "\(key)" // well, this is a little stretched
        #endif
      }

      /// Create a typed attribute for the given key.
      func makeAttribute<T>(_ t: T.Type, forKey key: Key) -> Attribute
             where T: AttributeValue
      {
        // FIXME: This doesn't take Optional into account
        let name    = nameForKey(key)
        let extName = key.stringValue == name ? nil : key.stringValue
        
        let attr : Attribute
        if nilKeys.contains(key) {
          attr = CodeAttribute<Optional<T>>(name, column: extName)
        }
        else {
          attr = CodeAttribute<T>(name, column: extName)
        }
        log.trace("makeAttribute:", t,
                  "name:", name, "ext:", extName, "key:", key,
                  "\n  attr:", attr)
        return attr
      }
      
      func addAttribute<T>(_ type: T.Type, forKey key: Key) -> Bool
             where T: AttributeValue
      {
        guard entity[attribute: nameForKey(key)] == nil else {
          log.trace("already registered attribute:", key, "in", entity)
          return false
        }
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                  "\(codingPathKK)]:decode:", key.stringValue, key, type)
        entity.attributes.append(makeAttribute(type, forKey: key))
        entity.addClassPropertyName(nameForKey(key))
        return true
      }

      // Note: I think we need to implement each, because we need to return the
      //       value (otherwise we would need to add a protocol w/ a default
      //       ctor)
      
      func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? -1337 : -1338
      }
      func decode(_ type: Int8.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? -13 : -14
      }
      func decode(_ type: Int16.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? -1337 : -1338
      }
      func decode(_ type: Int32.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? -11337 : -11338
      }
      func decode(_ type: Int64.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? -111337 : -111338
      }
      
      func decode(_ type: UInt.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? 1337 : 1338
      }
      func decode(_ type: UInt8.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? 13 : 14
      }
      func decode(_ type: UInt16.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? 1337 : 1338
      }
      func decode(_ type: UInt32.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? 11337 : 11338
      }
      func decode(_ type: UInt64.Type, forKey key: Key) throws -> Int {
        return addAttribute(type, forKey: key) ? 111337 : 111338
      }
      
      func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return addAttribute(type, forKey: key) ? "kasse7" : "kasse8"
      }
      func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        return addAttribute(type, forKey: key)
      }
      
      func decodeNil(forKey key: Key) throws -> Bool {
        if nilKeys.contains(key) {
          // return nil if we already know this key!
          // This allows cycles on optional items!
          log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                    "\(codingPathKK)]:decodeNil:", key.stringValue,
                    "AS-NIL-was-nil")
          return true
        }
        
        // We should check whether the entity already has that class
        // property already. If so, there is no need to decode any
        // further.
        if let cp = entity.classPropertyNames, cp.contains(nameForKey(key)) {
          // return nil if we already know this key!
          // This allows cycles on optional items!
          log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                    "\(codingPathKK)]:decodeNil:", key.stringValue,
                    "AS-NIL-prop-exists")
          return true
        }
        
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
                  "\(codingPathKK)]:decodeNil:", key.stringValue, "NOT-NIL")
        // Note: so it first calls `contains(:)`, if that returns true,
        //       an Optional still calls decodeNil.
        //       And this returns true for nil values, or false otherwise
        nilKeys.insert(key)
        // we do NOT want nil, we want to fake existence
        return false
      }
      
      func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type,
                                      forKey key: Key) throws
           -> KeyedDecodingContainer<NestedKey>
           where NestedKey : CodingKey
      {
        //return try decoder.container(keyedBy: type)
        throw Error.unsupportedNesting
      }
      
      func nestedUnkeyedContainer(forKey key: Key) throws
        -> UnkeyedDecodingContainer
      {
        //return try decoder.unkeyedContainer()
        throw Error.unsupportedNesting
      }
      
      func superDecoder() throws -> Decoder {
        return decoder
      }
      func superDecoder(forKey key: Key) throws -> Decoder {
        return decoder
      }
    }
  
    
    /**
     * Right now the sole purpose of this is to decode an array of
     * `CodableObjectType` aka an implicit toMany relationship:
     *
     *     var addresses : [ Address ]
     *
     */
    internal struct EntityCollectionPropertyReflectionContainer<EntityType: Decodable>
                      : UnkeyedDecodingContainer
    {
      // This has to live in a different file due to the Xcode 9 compile error
      let log          : ZeeQLLogger
      let decoder      : CodableModelEntityDecoder<EntityType>

      let sourceEntity : CodableEntityType
      let sourceKey    : CodingKey
      
      let codingPath   : [ CodingKey ]
      var currentIndex : Int = 0
      var isAtEnd      : Bool {
        return (count ?? 0) <= currentIndex
      }
      
      var count : Int? {
        // If we already know the relationship, we don't need to decode it!
        let name = nameForKey(sourceKey)
        if let rs = sourceEntity[relationship: name] {
          log.trace("count 0:", currentIndex, name, rs)
          // we know it already, return 0
          return 0
        }
        else {
          log.trace("count 1:", currentIndex, name)
          // we do not have it yet, decode it
          return 1
        }
      }

      init(decoder    : CodableModelEntityDecoder<EntityType>,
           entity     : CodableEntityType,
           key        : CodingKey,
           codingPath : [ CodingKey ] = [])
      {
        self.decoder      = decoder
        self.codingPath   = codingPath
        self.log          = decoder.log
        self.sourceEntity = entity
        self.sourceKey    = key
        
        log.trace("entity-col-prop-reflection-decoder:",
                  "\n  codingPath:  ", codingPath,
                  "\n  sourceEntity:", entity.name,
                  "\n  sourceKey:   ", key)
      }
      
      
      // MARK: - Main decoding function
      
      mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        currentIndex += 1
        log.trace("decode index:", currentIndex, type,
                  "\n  source:    ", sourceEntity,
                  "\n  source-key:", sourceKey)
        
        // we only expect other objects in here
        // Xcode issue: Because of this line, the class cannot live in its own
        //              file.
        guard case is CodableObjectType.Type = type else {
          throw Error.unsupportedValueType(type)
        }
        
        
        // OK: we already need to register the relationship here, to avoid
        //     recursion!
        let name = nameForKey(sourceKey)
        var didWorkOut = false
        let rsToRemove : ModelRelationship?
        
        if sourceEntity[relationship: name] == nil {
          // TBD: The container is type erased wrt CodableObjectType. Can we
          //      still somehow ask the Type to make the relationship, like
          //      above?
          let destEntity = decoder.state.existingEntityForType(type)
          let rs = ModelRelationship(name        : name, isToMany: true,
                                     source      : sourceEntity,
                                     destination : destEntity)
            // TODO: push extName for constraint?
          
          rsToRemove = rs
          sourceEntity.relationships.append(rs)
          sourceEntity.addClassPropertyName(name)
        }
        else {
          log.log("already registered relationship:", name, "in", sourceEntity)
          didWorkOut = true
          rsToRemove = nil
        }
        
        defer {
          // unregister if something failed
          if !didWorkOut, let rs = rsToRemove {
            if let idx = sourceEntity.relationships.index(where: { $0 === rs } )
            {
              sourceEntity.relationships.remove(at: idx)
              if let cpn = sourceEntity.classPropertyNames,
                 let idx = cpn.index(where: { $0 == name } )
              {
                sourceEntity.classPropertyNames?.remove(at: idx)
              }
            }
          }
        }

        
        // let the main decoder decode the type
        let v = try decoder.state.decode(type)
        
        guard v is CodableObjectType else { // superfluous, but be explicit
          throw Error.unsupportedValueType(type)
        }
        
        
        // OK, we got a CodableObjectType - lets setup the relationship
        
        if let rs = sourceEntity[relationship: name] {
          if rs.destinationEntity != nil {
            didWorkOut = true
          }
          else {
            guard let destEntity = decoder.state.existingEntityForType(type) else {
              // In this case there has to be an entity, right?
              throw Error.missingEntity
            }
            
            guard let mrs = rs as? ModelRelationship else {
              throw Error.unexpectedRelationshipType(rs)
            }
            
            mrs.destinationEntity = destEntity
            didWorkOut = true
          }
        }

        // return value
        return v
      }
      
      func nameForKey(_ key: CodingKey) -> String {
        return "\(key)" // well, this is a little stretched
      }

      
      // MARK: - Base Decoders, not supported in this specific container
      
      func decodeNil() -> Bool {
        return false
      }
      public mutating func decode(_ type: Bool.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: String.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: Int.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: Int8.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: Int16.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: Int32.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: Int64.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: UInt.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: UInt8.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: UInt16.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: UInt32.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }
      public mutating func decode(_ type: UInt64.Type) throws -> Bool {
        throw Error.unsupportedValueType(type)
      }

      func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
             -> KeyedDecodingContainer<NestedKey>
             where NestedKey : CodingKey
      {
        throw Error.unsupportedNesting
      }
      func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw Error.unsupportedNesting
      }
      
      func superDecoder() throws -> Decoder {
        return decoder
      }
    }
  } // CodableModelDecoder

  fileprivate extension CodableEntityType {
    func addClassPropertyName(_ s: String) {
      // This is not as obvious as it looks, because `ModelEntity`, which is
      // also a `CodableEntityType`, automagically derives the properties when
      // they have been missing!
      // That case is taken care of when constructing the temporary entity.
      if classPropertyNames == nil { classPropertyNames = [ s ]}
      else {
        if classPropertyNames?.contains(s) ?? false {
          return // Note: should never happen!
        }
        classPropertyNames?.append(s)
      }
    }
  }
#endif // swift(>=4.0)
