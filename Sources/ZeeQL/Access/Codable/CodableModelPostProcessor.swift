//
//  CodableModelPostProcessor.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)

  /**
   * Takes the entities derived by decoding the types, and fills up the missing
   * links.
   * That is, missing primary and foreign keys, missing reverse relationships,
   * and so on.
   */
  internal class CodableModelPostProcessor {
    
    enum Error : Swift.Error {
      case notImplemented
      case missingDestinationEntity(relationship: Relationship)
      case reverseRelationshipMissesJoins(relationship: Relationship)
      case missingPrimaryKey(entity: Entity)
      case couldNotFindOrCreateReverseRelationship
      case reverseRelationshipHasNoJoins(relationship: Relationship)
    }
    
    struct Options {
      let makeForeignKeyOptional    = true
      
      // this kinda depends on the backend, e.g. CKRecordID for CloudKit?
      // TBD: or should we always use `GlobalID` here?
      let defaultOptionalKeyType    = Optional<Int>.self
      let defaultNonOptionalKeyType = Int.self
      let defaultPrimaryKeyName     = "id"
    }
    let options = Options()

    var log : ZeeQLLogger { return globalZeeQLLogger }
    
    let entities : [ CodableEntityType ]

    init(entities: [ CodableEntityType ]) {
      self.entities = entities
    }
    
    
    /**
     * The main entry point. Construct the model from from the entities which
     * got passed into the constructor.
     */
    internal func buildModel() -> Model {
      entities.forEach(self.assignPrimaryKeyIfMissing)
      
      // TODO: This process should be in a separate object.
      processToOneRelationships()
      processToManyRelationships()
      
      let model = Model(entities: entities)
      #if false // we need to do this
        model.connectRelationships()
      #endif
      return model
    }
    
    
    /**
     * If the entity doesn't have a primary key, assign one.
     *
     * This first checks `lookupPrimaryKeyAttributeNames` of the entity,
     * and if this fails, we create an `id` primary key, as configured in the
     * `Options` object.
     */
    private func assignPrimaryKeyIfMissing(_ entity: CodableEntityType) {
      // FancyModelMaker also has a `assignPrimaryKeyIfMissing`
      entity.primaryKeyAttributeNames =
        entity.lookupPrimaryKeyAttributeNames()
      
      if entity.primaryKeyAttributeNames?.count ?? 0 == 0 {
        // found no pkey, create one
        let name = options.defaultPrimaryKeyName
        let pkey = ModelAttribute(name: name, column: nil,
                                  externalType: nil, allowsNull: false,
                                  width: nil,
                                  valueType: options.defaultNonOptionalKeyType)
        entity.attributes.insert(pkey, at: 0) // put to front
        entity.primaryKeyAttributeNames = [ pkey.name ]
      }
    }

    /**
     * Ensure that we have an attribute matching the target key, and setup a
     * proper join.
     */
    func processToOneRelationships() {
      for entity in entities {
        for rs in entity.relationships {
          guard !rs.isToMany                       else { continue }
          guard let mrs = rs as? ModelRelationship else { continue }

          do {
            try processToOne(source: entity, relationship: mrs)
          }
          catch {
            // TODO: collect errors and pass rethrow a single Error
            log.error("could not process toMany relationship:", mrs, error)
          }
        }
      }
    }
    
    func processToManyRelationships() {
      for entity in entities {
        for rs in entity.relationships {
          guard rs.isToMany                        else { continue }
          guard let mrs = rs as? ModelRelationship else { continue }

          do {
            try processToMany(source: entity, relationship: mrs)
          }
          catch {
            // TODO: collect errors and pass rethrow a single Error
            log.error("could not process toMany relationship:", mrs, error)
          }
        }
      }
    }
    
    /**
     * Hook up and create joins for the ToOne relationship.
     *
     * A ToOne has an attribute - the foreign key - in the source. The target
     * of that key is the primary key in the destination (for Codable, custom
     * entities can do fancier stuff).
     *
     * We do not auto-create toMany relationships on the other side. TBD.
     *
     * So for to-one, there is not a lot to do? We need to check whether we
     * have a foreign-key matching our relationship.
     * And if not, create one.
     * Then setup the joins.
     */
    fileprivate func processToOne(source srcEntity: CodableEntityType,
                                  relationship rs: ModelRelationship) throws
    {
      log.trace("\(#function) from:", srcEntity)
      guard let anyDestEntity = rs.destinationEntity else {
        log.error("relationship has no destinationEntity?:", rs, srcEntity)
        throw Error.missingDestinationEntity(relationship: rs)
      }
      guard let destEntity = anyDestEntity as? CodableEntityType else {
        log.error("relationship destinationEntity has different type?:",
                  rs, anyDestEntity)
        throw Error.missingDestinationEntity(relationship: rs)
      }
      
      // lookup primary key in destination
      
      guard let pkeyName = destEntity.primaryKeyAttributeNames?.first else {
        log.trace("  no or many primary keys:", destEntity)
        throw Error.missingPrimaryKey(entity: destEntity)
      }
      guard let pkey = destEntity[attribute: pkeyName] else {
        log.trace("  did not find pkey:", pkeyName, destEntity)
        throw Error.missingPrimaryKey(entity: destEntity)
      }

      // Do we have a foreign key matching the relship (ownerId, ownerID)
      
      // TODO: `toOwner` => `owner`
      let baseName = rs.name
      if let fkey = srcEntity[attribute: baseName + "Id"]
                 ?? srcEntity[attribute: baseName + "ID"]
      {
        log.trace("  found foreign key:", fkey)
        rs.joins = [ Join(source: fkey, destination: pkey) ]
        
        // TODO: make sure optionality matches!
      }
      else {
        log.trace("  missing foreign key:", baseName + "Id",
                  "for:", rs.name, "mandatory:", rs.isMandatory ? "y" : "n")
        // TODO:
        // - how to we keep the static type, can we? We could ask the pkey
        //   to replicate itself? But is it worth it?
        // - use a closure to select name?
        
        let valueType  : AttributeValue.Type
        
        // TODO:
        // optionality depends on whether the target type of the ToOne is
        // optional: i.e. `ToOne<Person>` vs `ToOne<Person?>`.
        // but we may not be able to express this?
        // We technically *do* support `ToOne<Person>?`.
        
        // TBD: isMandatory - what if it is a plain ModelRelship w/o joins
        
        if let pkeyType = pkey.valueType {
          if !rs.isMandatory, let ot = pkeyType.optionalType {
            valueType = ot
          }
          else if rs.isMandatory, let ot = pkeyType.optionalBaseType {
            valueType = ot
          }
          else {
            // TBD: warn?
            valueType = pkeyType
          }
        }
        else {
          valueType = !rs.isMandatory
                        ? options.defaultOptionalKeyType
                        : options.defaultNonOptionalKeyType
        }
        
        let fkey = ModelAttribute(name: baseName + "Id", column: nil,
                                  externalType: nil,
                                  allowsNull: !rs.isMandatory,
                                  width: nil, valueType: valueType)
        srcEntity.attributes.append(fkey)
        
        log.trace("  created foreign-key:",     fkey)
        
        // DONE!
        //try applyJoinFromReverseRelationship(rev)
        rs.joins = [ Join(source: fkey, destination: pkey) ]
      }
    }

    /**
     * Hook up and create joins for the ToMany relationship.
     *
     * A ToMany has no attribute in the source, but the foreign key in and
     * potentially a reverse relationship in the target.
     *
     * The sequence:
     *
     * - check whether the target has a ToOne which matches the the source
     *   in lowercase (e.g. the Address entity has a `var person:ToOne<Person>`.
     * - check whether the target has an attribute named like `$source$Id`,
     *   (e.g. the Address entity has a `var personId : Int`)
     *   - if yes, also look for the reverse ToOne relationship w/ that as the
     *     target attribute
     *     - if missing, create one!
     * - check whether the target has any *unused* ToOne relationship that
     *   targets our entity (e.g. the Address entity has a
     *   `var owner: ToOne<Person>`)
     * - if all that fails, create a new reverse relationship in target,
     *   the foreign key will be $source$Id (which can't exist as per the upper)
     */
    fileprivate func processToMany(source srcEntity: CodableEntityType,
                                   relationship rs: ModelRelationship) throws
    {
      log.trace("\(#function) from:", srcEntity)
      guard let anyDestEntity = rs.destinationEntity else {
        log.error("relationship has no destinationEntity?:", rs, srcEntity)
        throw Error.missingDestinationEntity(relationship: rs)
      }
      guard let destEntity = anyDestEntity as? CodableEntityBase else {
        log.error("relationship destinationEntity has different type?:",
                  rs, anyDestEntity)
        throw Error.missingDestinationEntity(relationship: rs)
      }
      
      // FIXME: check whether the RS is already setup (has joins etc)
      
      // first check whether the target has a ToOne which matches the the source
      // in lowercase (e.g. the Address entity has a `var person:ToOne<Person>`.

      let reverseName = srcEntity.name.decapitalized // e.g. 'person'
      if let rev = destEntity[relationship: reverseName], // we have that RS
         !rev.isToMany,                                   // it is a toOne
         rev.destinationEntity === srcEntity              // entity matches
      {
        log.trace("  found reverse:", rev)
        // NOTE: this should have keys setup due to the toOne being processed
        //       first!
        guard !rev.joins.isEmpty else {
          throw Error.reverseRelationshipMissesJoins(relationship: rev)
        }
        
        return // Nothing to do, right?!
      }
      else {
        log.trace("  no reverse named:", reverseName)
      }
      
      
      // we need to have a primaryKey from here on, right?
      
      guard let pkeyName = srcEntity.primaryKeyAttributeNames?.first else {
        log.trace("  no or many primary keys:", srcEntity)
        throw Error.missingPrimaryKey(entity: srcEntity)
      }
      guard let pkey = srcEntity[attribute: pkeyName] else {
        log.trace("  did not find pkey:", pkeyName, srcEntity)
        throw Error.missingPrimaryKey(entity: srcEntity)
      }
      
      
      func applyJoinFromReverseRelationship(_ revRelship: Relationship) throws {
        assert(revRelship.joins.count == 1, "unexpected number of joins")
        
        // FIXME: this is just to please CodeRelationship, which we may not
        //        want to use.
        rs.joins = revRelship.joins.map { $0.inverse }
      }
      
      // next: whether we got a foreign key (personId, personID)
      
      if let fkey = destEntity[attribute: reverseName + "Id"]
                 ?? destEntity[attribute: reverseName + "ID"]
      {
        log.trace("  found foreign key:", fkey)
        
        /* - if yes, also look for the reverse ToOne relationship w/ that as the
         *   target attribute
         *   - if missing, create one!
         */
        
        // next: scan for relationship with fkey as the source attribute
        var rev : Relationship? = nil
        for rs in destEntity.relationships {
          guard !rs.isToMany        else { continue }
          guard rs.joins.count == 1 else { continue }
          
          guard let sn = rs.joins[0].sourceName ?? rs.joins[0].source?.name
           else { continue }
          
          if sn == fkey.name {
            rev = rs
            break
          }
        }
        
        if rev == nil { // foreign key, but no reverse relship, create it!
          log.trace("  no toOne reverse for fkey:", fkey)
          
          // preserve type if possible
          rev = srcEntity.makeToOneRelationship(
                  name: reverseName, from: destEntity,
                  sourceAttribute: fkey, destinationAttribute: pkey)
          destEntity.relationships.append(rev!)
        }
        
        // OK, now we got a reverse relationship
        guard let revRelship = rev else { // unexpected
          assert(rev != nil, "neither got nor created reverse relship?!")
          throw Error.couldNotFindOrCreateReverseRelationship
        }
        
        // DONE!
        try applyJoinFromReverseRelationship(revRelship)
        return
      }
      else {
        log.trace("  no reverse foreign key:", reverseName + "Id")
      }

      
      /* - check whether the target has any *unused* ToOne relationship that
       *   targets our entity (e.g. the Address entity has a
       *   `var owner: ToOne<Person>`)
       */
      do {
        // FIXME: IMPORTANT: we don't do the 'unused' part. We really should.
        
        for rs in destEntity.relationships {
          guard !rs.isToMany        else { continue }
          guard rs.joins.count == 1 else { continue }
          
          guard rs.destinationEntity === srcEntity else { continue }
          
          // DONE!
          try applyJoinFromReverseRelationship(rs)
          return
        }
        
        log.trace("  no toOne relationship pointing back to entity")
      }

      /*
       * - if all that fails, create a new reverse relationship in target,
       *   the foreign key will be $source$Id (which can't exist as per the
       *   upper)
       */
      // TBD: will it be Optional or not? Hm. Optional I guess.
      do {
        // TODO:
        // - how to we keep the static type, can we? We could ask the pkey
        //   to replicate itself? But is it worth it?
        // - use a closure to select name?
        
        let valueType : AttributeValue.Type
        if let pkeyType = pkey.valueType {
          if options.makeForeignKeyOptional, let ot = pkeyType.optionalType {
            valueType = ot
          }
          else if !options.makeForeignKeyOptional, let ot = pkeyType.optionalBaseType {
            valueType = ot
          }
          else {
            // TBD: warn?
            valueType = pkeyType
          }
        }
        else {
          valueType = options.makeForeignKeyOptional
                        ? options.defaultOptionalKeyType
                        : options.defaultNonOptionalKeyType
        }
        
        let fkey = ModelAttribute(name: reverseName + "Id", column: nil,
                                  externalType: nil, allowsNull: true,
                                  width: nil, valueType: valueType)
        destEntity.attributes.append(fkey)

        // preserve type if possible
        let rev = srcEntity.makeToOneRelationship(
                      name: reverseName, from: destEntity,
                      sourceAttribute: fkey, destinationAttribute: pkey)
        destEntity.relationships.append(rev)
        
        log.trace("  created foreign-key:",     fkey)
        log.trace("  created reverse-relship:", rev)
        
        // DONE!
        try applyJoinFromReverseRelationship(rev)
        return
      }
    }
  }
#endif
