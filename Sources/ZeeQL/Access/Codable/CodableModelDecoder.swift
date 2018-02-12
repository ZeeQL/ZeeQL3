//
//  CodableModelDecoder.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  
  public extension CodableObjectType { // MutableKeyValueCodingType
    // TODO: This is only here to please `DatabaseObject`
    func takeValue(_ value : Any?, forKey k: String) throws {
      // TBD
      throw KeyValueCoding.Error.CannotTakeValueForKey(k)
    }
  }
  
  open class CodableModelDecoder {
    // TODO: Rename this class to avoid confusion (it is not a Codable
    //       decoder)
    //       Maybe make this a private CodableReflectionState, and add another
    //       public API to actually build the model.
    
    var log : ZeeQLLogger { return globalZeeQLLogger }
    
    public struct Options {
      /**
       * Using Codable you can create infinitely recursive models. This is the
       * depth until we give up trying to decode.
       */
      var maxDepth = 10 // TODO: improve cycle detection
      
      /**
       * Arbitrary `Codable` types can be decoded. But sometimes, you want to
       * limit the type to be a `CodableObjectType`
       */
      var enforceCodableObjectType = false
      
      /**
       * If non-nil, we will SQLize the external names of the model using the
       * `ModelSQLizer`.
       *
       * What it does:
       * - it lowercases entity names, a `Person` entity becomes the `person`
       *   table
       * - it expands primary keys, a `Person.id` becomes `person.person_id`
       * - it de-camel-cases attribute names: `bankAddress` becomes
       *   `bank_address`
       * and more ;-)
       */
      var sqlize : ModelSQLizer.Options?
      
      public init(sqlize: Bool = false) {
        self.sqlize = sqlize ? ModelSQLizer.Options() : nil
      }
    }
    let options :  Options
    
    init(options: Options = Options()) {
      self.options = options
    }


    // MARK: - API
    
    public func add<T: CodableObjectType>(_ type: T.Type) throws {
      codingPath.removeAll()
      _ = try decode(type)
    }
    public func add<T: Decodable>(_ type: T.Type) throws {
      codingPath.removeAll()
      _ = try decode(type)
    }

    public func buildModel() -> Model {
      log.trace("build model ...")
      migrateTypedEntities()
      processPendingEntities()
      
      log.trace("post process entities and create model ...")
      var model = CodableModelPostProcessor(entities: Array(entities.values))
                    .buildModel()
      
      if let sqlize = options.sqlize {
        // FIXME: this needs to SQLize in-place!
        log.trace("SQLize model ...", sqlize)
        model = ModelSQLizer().sqlizeModel(model, options: sqlize)
      }
      log.trace("created model:", model)
      return model
    }
    
    enum Error : Swift.Error {
      case notImplemented
      case unsupportedSingleValue
      case missingEntity
      case missingKey
      case unsupportedValueType(Any.Type)
      case unsupportedNesting // we currently do not allow this, reconsider
      
      /// Should never happen, internal error
      case unexpectedRelationshipType(Relationship)
      
      /// This can happen for very complex models, or in cases where the types
      /// have a strong recursion.
      case reflectionDepthExceeded
      
      /// Should never happen, internal error
      case unexpectedRelationshipHolderType
    }
    
    /// helper, remove this
    var codingPathKK : String {
      return codingPath.map { $0.stringValue }.joined(separator: ".")
    }
    
    
    // MARK: - Processing State
    
    var codingPath = [ CodingKey ]()
    var userInfo   = [ CodingUserInfoKey : Any]()
    
    /// Entities we decoded for which we have a full
    /// `CodableObjectEntity` (vs just a `DecodableEntity`).
    var entities   = [ String : CodableEntityType ]()
    
    /// Entities we decoded for which we do not have a full
    /// `CodableObjectEntity`, but just a `DecodableEntity`.
    var temporaryEntities = [ String : CodableEntityType ]()
    
    /// This is used when we first implicitly decoded an entity, but later
    /// get a full `CodableObjectEntity`.
    var entitiesToMigrate = Set<String>()
    

    
    // MARK: - Decoder
    
    private var decodeTypeStack = [ Decodable.Type ]()
    
    /**
     * A map from the type name (FIXME) to an instance. This way we can avoid
     * unnecessary recursion.
     * E.g. if the a `Person` is being decoded, but a `Person` was decoded
     * before, we just use the old object.
     */
    var decodeObjectMap = [ String : CodableObjectType ]()
    
    private func entityNameFromType(_ type: Any.Type) -> String {
      var s = "\(type)" // FIXME: "Address #1" - cut off
      if let r = s.range(of: " #") {
        s = String(s[s.startIndex..<r.lowerBound])
      }
      return s
    }
    
    func hasEntityForType<T: CodableObjectType>(_ type: T.Type) -> Bool {
      let name = entityNameFromType(type)
      return (entities[name] as? CodableObjectEntity<T>) != nil
    }
    func hasEntityForType<T: Decodable>(_ type: T.Type) -> Bool {
      // weaker variant
      let name = entityNameFromType(type)
      return entities[name] != nil
    }
    
    /**
     * If the decoder doesn't have a static type for a given entity, it has
     * to create an untyped `ModelEntity` object. If it then later *does*
     * get a typed entity, all references to the `ModelEntity` are replaced w/
     * the typed `CodableEntity<T>`.
     * This is what this function does as a post-processing step.
     */
    private func migrateTypedEntities() {
      let names = Array(entitiesToMigrate)
      log.trace("migrate temporary entities:", names.joined(separator: ","))
      for entityName in names {
        guard let old = temporaryEntities[entityName],
              let new = entities         [entityName] else { continue }
        
        log.trace("  migrate temporary entity:",
                  "\n  old:", old,
                  "\n  new:", new)
        // TODO: replace old w/ new in relationships
        // TBD: do we need to walk both sets? I think so, yes
        for ( _, entity ) in entities {
          entity.replaceTemporaryEntity(old, with: new)
        }
        for ( _, entity ) in temporaryEntities {
          entity.replaceTemporaryEntity(old, with: new)
        }

        entitiesToMigrate.remove(entityName)
        temporaryEntities.removeValue(forKey: entityName)
      }
      assert(entitiesToMigrate.isEmpty)
      
      if !temporaryEntities.isEmpty {
        log.log("left w/ temporary model entities:", temporaryEntities)
        
        for (name, entity) in temporaryEntities {
          guard entities[name] == nil else { continue }
          entities[name] = entity
        }
      }
      temporaryEntities.removeAll()
    }
    
    func lookupOrCreateTypedEntity<T>(_ type: T.Type) -> CodableObjectEntity<T>
           where T: CodableObjectType
    {
      let name = entityNameFromType(type)
      if let entity = entities[name] as? CodableObjectEntity<T> {
        return entity
      }
      
      let newEntity = CodableObjectEntity<T>(name: name, className: name)
      entities[name] = newEntity
      
      if let tempEntity = temporaryEntities[name] {
        // we need to patch references later
        entitiesToMigrate.insert(name)
        
        // copy over information that we already decoded
        newEntity.attributes               = tempEntity.attributes
        newEntity.relationships            = tempEntity.relationships
        newEntity.primaryKeyAttributeNames = tempEntity.primaryKeyAttributeNames
        newEntity.classPropertyNames       = tempEntity.classPropertyNames
      }
      
      return newEntity
    }
    
    /**
     * Ensure we have an entity, triggered by an untyped one. Ideally we want
     * to replace them later w/ typed ones, but if we don't get a static type,
     * we can also just use those.
     */
    func lookupOrCreateLowTypedEntity<T>(_ type: T.Type) -> CodableEntityType
           where T: Decodable
    {
      let name = entityNameFromType(type)
      if let entity = entities         [name] { return entity }
      if let entity = temporaryEntities[name] { return entity }
      
      // NOTE: THIS IS *NOT* actually untyped! T still has the full type
      //       information!
      // I think the only issue here is, that we cannot get from
      // `T: Decodable` to `T: CodableObjectType` even though
      // we do *know* that:
      //   `if case is CodableObjectType.Type = type` is true
      // but we need it for this:
      //    CodableEntity<T: CodableObjectType>
      
      let newEntity = DecodableEntity<T>(name: name, className: name)
      temporaryEntities[name] = newEntity
      log.trace("registering temporary entity:", newEntity)
      return newEntity
    }
    
    func existingEntityForType<T: Decodable>(_ type: T.Type)
           -> CodableEntityType?
    {
      let name = entityNameFromType(type)
      return entities[name] ?? temporaryEntities[name]
    }
    
    class RelationshipPatchEntryBase {
      func patchUsingDecoder(_ decoder: CodableModelDecoder) {}
    }
    class RelationshipPatchEntry<T: Decodable> : RelationshipPatchEntryBase {
      let type         : T.Type
      let relationship : ModelRelationship
      
      init(type: T.Type, relationship: ModelRelationship) {
        self.type         = type
        self.relationship = relationship
      }
      override func patchUsingDecoder(_ decoder: CodableModelDecoder) {
        guard relationship.destinationEntity == nil else { return }
        if let entity = decoder.existingEntityForType(type) {
          relationship.destinationEntity = entity
        }
        else {
          let log = decoder.log
          log.warn("entity is not registered explicitly!", self)
        }
      }
    }
    
    private var relationshipPatchEntries = [ RelationshipPatchEntryBase ]()
    
    private func processPendingEntities() {
      for patch in relationshipPatchEntries {
        patch.patchUsingDecoder(self)
      }
    }
    internal func registerForPendingEntity<T: Decodable>
                    (_ type: T.Type, relationship: ModelRelationship)
    {
      relationshipPatchEntries.append(
        RelationshipPatchEntry(type: type, relationship: relationship))
    }
    
    
    /**
     * Decode a `CodableObjectType`. This is like the main entry point to
     * reflect on a CodableObjectType object and the method you need to use
     * to get a statically typed entity object.
     *
     * NOTE: This only works for statically typed objects! (i.e. only those
     *       which are explicitly passed into the coder from the client).
     *       There is a type-erased variant below.
     */
    internal func decode<T: CodableObjectType>(_ type: T.Type) throws -> T {
      // This is still required for the type-erased containers. This is not
      // sufficient: decode<T: CodableObjectType>
      
      if let fakeObject = decodeObjectMap["\(type)"] as? T {
        log.log("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                "REUSE entity-object: \(type)")
        return fakeObject // already processed this
      }
      
      guard decodeTypeStack.count <= options.maxDepth else {
        // Protect against cycles. But can't we do this in a more clever way?
        // TBD: e.g. just by looking whether the type is already decoded in the
        //      stack?
        throw Error.reflectionDepthExceeded
      }

      log.trace("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                "DECODE entity-object: \(type)")
      decodeTypeStack.append(type)
      let entity = lookupOrCreateTypedEntity(type) // register
      // Note: we may have processed that already!
      // TBD:  I think this is the place where we need to resolve the
      //       recursion
      
      // create our nested decoder
      let decoder = CodableModelEntityDecoder<T>(state: self, entity: entity)
      
      // call into `Decodable.init(from:)`
      let fakeObject = try type.init(from: decoder)
      decodeTypeStack.removeLast()
      return fakeObject
    }
    
    /**
     * Decode a `CodableObjectType`. No other values are supported here at the
     * top level!
     * In here we create a model entity (unless an entity is available already).
     *
     * This is a *type erased* decode function which is invoked when an object
     * is decoded as a dependency. The full static type is not available
     * anymore!
     */
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
      // This is still required for the type-erased containers. This is not
      // sufficient: decode<T: CodableObjectType>
      
      if options.enforceCodableObjectType {
        guard case is CodableObjectType.Type = type else {
          throw Error.unsupportedValueType(type)
        }
      }
      
      guard decodeTypeStack.count <= options.maxDepth else {
        // Protect against cycles. But can't we do this in a more clever way?
        throw Error.reflectionDepthExceeded
      }

      if let fakeObject = decodeObjectMap["\(type)"] as? T {
        log.log("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                "REUSE entity-object: \(type)")
        return fakeObject // already processed this
      }
      
      log.trace("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                "DECODE entity-object: \(type)")
      decodeTypeStack.append(type)
      
      // Note: This is NOT actually untyped, see the function for details.
      let entity = lookupOrCreateLowTypedEntity(type) // register
      
      // create our nested decoder
      let decoder = CodableModelEntityDecoder<T>(state: self, entity: entity)

      
      // call into `Decodable.init(from:)`
      let fakeObject = try type.init(from: decoder)
      decodeTypeStack.removeLast()
      return fakeObject
    }

  }
  
  
  internal func * (lhs: String, rhs: Int) -> String {
    var s = ""
    for _ in 0..<rhs { s += lhs }
    return s
  }

#endif // swift(>=4.0)
