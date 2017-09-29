//
//  FancyModelMaker.swift
//  ZeeQL3
//
//  Created by Helge Hess on 19/05/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.URL

/**
 * `FancyModelMaker` is here to make plain models fancy.
 *
 * The core idea is that you keep your SQL schema SQL-ish but your Swift model
 * Swifty.
 *
 * Example SQL:
 *
 *     CREATE TABLE person (
 *       person_id       SERIAL PRIMARY KEY NOT NULL,
 *       firstname       VARCHAR NULL,
 *       lastname        VARCHAR NOT NULL
 *       office_location VARCHAR
 *     )
 *
 * Derived Entity:
 *
 *     class Entity : CodeEntity<Person> {
 *       let id             : Int     = 0
 *
 *       let firstname      : String? = nil
 *       let lastname       : String  = ""
 *
 *       let officeLocation : String? = nil
 *
 *       let addresses      = ToMany<Address>()
 *     }
 *
 * In addition the maker can:
 * - detect primary keys (if none are explicitly marked)
 *   - that is `id` and `table_id`
 * - detect relationships
 *   - e.g. the `address` entity has a `person_id` and there is a `person` table
 * - create reverse relationships
 *   - e.g. the `address` above would create a to-many in the `person` entity
 *
 * Extra Rules:
 * - by default only lowercase names are considered for camel-casing
 * - if the externalName/columnName is already different to the name,
 *   we don't touch it
 */
open class FancyModelMaker {
  
  public struct Options {
    var detectIdAsPrimaryKey       = true
    var detectTableIdAsPrimaryKey  = true
    
    var detectRelationships        = true
    var createInverseRelationships = true
    var fancyUpRelshipNames        = true
    
    var onlyLowerCase              = true
    var capCamelCaseEntityNames    = true // person_address => PersonAddress
    var camelCaseAttributeNames    = true // company_id => companyId
    var useIdForPrimaryKey         = true // person_id pkey => id
    
    var boolValueTypePrefixes      = [ "is_", "can_" ]
    var urlSuffix                  : String? = nil // "_url"
    var keyColumnSuffix            = "_id"
    
    public init() {}
  }
  
  public final let model   : Model
  public final let options : Options
  
  // processing state
  public final var newModel        : Model? = nil
  public final var renamedEntities = [ String : String ]()
  public final var renamedAttributesByNewEntityNames =
                                     [ String : [ String: String ]]()
  public final var modelRelationships = [ ModelRelationship ]()
  
  public init(model: Model, options: Options = Options()) {
    self.model   = model
    self.options = options
  }
  
  
  // MARK: - Fancyfy
  
  func clear() {
    renamedEntities.removeAll()
    renamedAttributesByNewEntityNames.removeAll()
    modelRelationships.removeAll()
    newModel = nil
  }
  
  open func fancyfyModel(reconnect: Bool = true) -> Model {
    clear()
    
    newModel = Model(entities: [], tag: model.tag)
    
    
    // Phase 1 conversion of entities
    
    for entity in model.entities {
      newModel!.entities.append(fancyfyEntity(entity))
    }
    
    
    // Patch references to renamed names :-)
    
    for mrs in modelRelationships {
      // TBD: what about `relationshipPath`? Stop if set?
      let renamedDestAttributes   : [ String : String ]?
      let renamedSourceAttributes =
            renamedAttributesByNewEntityNames[mrs.entity.name]
      
      if let dn = mrs.destinationEntityName {
        if let newDestName = renamedEntities[dn] {
          mrs.destinationEntityName = newDestName
          mrs.destinationEntity = nil // Hm
        }
        renamedDestAttributes =
          renamedAttributesByNewEntityNames[mrs.destinationEntityName!]
      }
      else {
        assert(mrs.destinationEntityName != nil, "relship w/o dest name?")
        renamedDestAttributes = nil
      }
      
      if renamedSourceAttributes != nil || renamedDestAttributes != nil {
        // value objects
        var newJoins = [ Join ]()
        newJoins.reserveCapacity(mrs.joins.count)
        for join in mrs.joins {
          guard let sn = join.sourceName, let dn = join.destinationName
           else {
            assert(false, "join misses source or destination name!")
            continue
           }
          
          newJoins.append(Join(source:      renamedSourceAttributes?[sn] ?? sn,
                               destination: renamedDestAttributes?  [dn] ?? dn))
        }
        mrs.joins = newJoins
      }
    }
    
    
    // improve names of relationships
    // - for schema fetches the names will contain the name of the constraint
    //   (or the key of the constraint in SQLite). That is usually ugly ;->
    
    if options.fancyUpRelshipNames {
      for entity in newModel!.entities {
        for relship in entity.relationships {
          // we only auto-create toOne relships from SQL databases or by the
          // auto-detection above.
          guard !relship.isToMany                       else { continue }
          guard let mrs = relship as? ModelRelationship else { continue }
          
          // this is our trigger
          guard relship.isNameConstraintName            else { continue }
          
          // the name of the relationship really depends on the name of
          // the foreign key (the source in here)
          // e.g.:
          // - owner_id  => owner   (connecting person.person_id)
          // - person_id => person  (connecting person.person_id)
          // or use 'toOwner' etc. Makes clashes less likely
          guard let fkeyAttrName = relship.foreignKey1 else { continue }
          
          guard let baseName = fkeyAttrName.withoutId  else { continue }
          // check whether a similar entity already exists ...
          guard let rsName = entity.availableName(baseName, baseName.toName)
           else { continue }
          
          // assign nicer name
          // TODO: use 'to' entity.name for exact attr matches, use
          // 'creator'Id for others
          // e.g. source: 'creatorId' => 'creator'
          mrs.name = rsName
        }
      }
    }
    
    
    if options.detectRelationships {
      // detect relationships
      // ... if the database schema has no proper constraints setup ..., like,
      // in the common OGo PostgreSQL schema ... ;->
      
      // collect available tables
      var tableToEntity               = [ String : Entity ]()
      var tableToPrimaryKeyColumNames = [ String : Set<String> ]()
      for entity in newModel!.entities {
        let tableName = entity.externalName ?? entity.name
        
        tableToEntity[tableName] = entity
        
        if let pkeys = entity.primaryKeyAttributeNames, !pkeys.isEmpty {
          var columns = Set<String>()
          for pkey in pkeys {
            guard let attr = entity[attribute: pkey] else { continue }
            columns.insert(attr.columnName ?? pkey)
          }
          tableToPrimaryKeyColumNames[tableName] = columns
        }
      }

      for entity in newModel!.entities {
        // skip entities which have constraints. If they have one, we assume
        // they do all ;->
        //
        // Note: this only works for simple cases, but better than nothing.
        //       e.g. an 'owner_id' pointing to a 'person' table doesn't work.
        //       TBD: maybe we could add additional conventions for such '_id'
        //            tables.
        guard entity.relationships.isEmpty           else { continue }
        guard let newEntity = entity as? ModelEntity else { continue }
        
        let pkeyColumns =
          tableToPrimaryKeyColumNames[newEntity.externalName ?? newEntity.name]
          ?? Set<String>()
        
        for attr in newEntity.attributes {
          let colname = attr.columnName ?? attr.name
          guard !pkeyColumns.contains(colname)             else { continue }
          guard colname.hasSuffix(options.keyColumnSuffix) else { continue }
          guard colname.characters.count > 3               else { continue }
          
          // OK, e.g. person_id. Now check whether there is a person table
          let endIdx = colname.index(colname.endIndex, offsetBy: -3)
          #if swift(>=4.0)
            let tableName = String(colname[colname.startIndex..<endIdx])
          #else
            let tableName = colname[colname.startIndex..<endIdx]
          #endif
          
          
          // This only works for target entities which have a single pkey
          // (currently, we could match multi-keys as well)
          guard let pkeyColumnNames = tableToPrimaryKeyColumNames[tableName],
                pkeyColumnNames.count == 1
           else {
            //print("skip key: \(colname) from \(newEntity) to \(tableName))")
            continue
           }
          
          // primary key columnName doesn't match this foreign key
          guard pkeyColumnNames.contains(colname) else { continue }
          
          
          // OK, seems to be a match!
          
          guard let destEntity = tableToEntity[tableName] else { continue }
          
          // TODO: this generates the 'toCompany'
          
          guard let sourceAttribute = newEntity [columnName: colname],
                let destAttribute   = destEntity[columnName: colname]
           else { continue }

          guard let baseName = sourceAttribute.name.withoutId  else { continue }
          // check whether a similar entity already exists ...
          guard let rsName = entity.availableName(baseName, baseName.toName)
           else { continue }
          
          let relship = ModelRelationship(name: rsName, isToMany: false,
                                          source:      newEntity,
                                          destination: destEntity)
          let join = Join(source:      sourceAttribute,
                          destination: destAttribute)
          relship.joins.append(join)
          
          newEntity.relationships.append(relship)
        }
      }
    }
    
    
    if options.createInverseRelationships {
      
      /* what to do:
         - scan for toOne relationships
         - look whether the target has a reverse relationship already
         - create one otherwise
       */
      
      for entity in newModel!.entities {
        for relship in entity.relationships {
          // we only auto-create toOne relships from SQL databases or by the
          // auto-detection above.
          guard !relship.isToMany                       else { continue }
          guard let mrs = relship as? ModelRelationship else { continue }
          
          guard let destEntityName = mrs.destinationEntityName else { continue }
          guard let destEntity =
                      newModel![entity: destEntityName] as? ModelEntity
           else { continue }
          
          // - so we have our relationship
          // - we need to check whether the target already has an inverse
          
          var hasInverse = false;
          for destRelship in destEntity.relationships {
            // this could be either toMany or toOne.
            
            guard relship.isReciprocalTo(relationship: destRelship)
             else { continue }
            
            hasInverse = true
          }
          
          if hasInverse { continue }
          
          
          // create inverse relationship
          
          // name is 'creator' or 'owner' or 'company'
          // we want the reverse, like 'creatorOfAddress' - plural, really
          // also: 'to' fallback

          
          // TODO: if we refer to the primary key, we want just the plurals,
          // e.g. instead of 'companyOfAddress'(es), use just 'addresses'
          
          
          let baseName = relship.name + "Of" + entity.name
          
          // TODO: use 'to' entity.name for exact attr matches, use
          // 'creator'Id for others
          // e.g. source: 'creatorId' => 'person.companyId'
          //              -> creatorOf? or creatorOfAppointments?
          //              or base this off the other relship-name?
          // check whether a similar entity already exists ...
          guard let rsName =
                      entity.availableName(entity.name.decapitalized.pluralized,
                                           baseName,
                                           baseName.toName)
           else { continue }
          
          let newRelship = ModelRelationship(name: rsName, isToMany: true,
                                             source:      destEntity,
                                             destination: entity)
          newRelship.joinSemantic = .leftOuterJoin // TBD
          for join in relship.joins {
            // TODO: fix `!`
            let inverseJoin = Join(source:      join.destinationName!,
                                   destination: join.sourceName!)
            newRelship.joins.append(inverseJoin)
          }
          destEntity.relationships.append(newRelship)
        }
      }
    }
    
    
    // TODO: fixup relationship names
    
    
    // reconnect model
    
    if reconnect {
      newModel!.connectRelationships()
    }
    
    let result = newModel!
    clear()
    return result
  }
  
  open func fancyfyEntity(_ entity: Entity) -> Entity {
    let newEntity = ModelEntity(entity: entity, deep: true)
    
    // map entity name
    
    if options.capCamelCaseEntityNames,
       !newEntity.hasExplicitExternalName,
       !options.onlyLowerCase || newEntity.name.isLowerCase
    {
      let oldName = entity.name
      if newEntity.externalName == nil {
        newEntity.externalName = oldName
      }
      newEntity.name = newEntity.name.capCamelCase
      renamedEntities[oldName] = newEntity.name
    }
    
    
    // map attribute names
    
    // TBD: classPropertyNames. Hm. for now assume they are calculated.
    //      to implement this, we need to compare the sets
    
    var oldSinglePrimaryKeyName : String?
    if let pkeys = newEntity.primaryKeyAttributeNames, pkeys.count == 1,
       options.useIdForPrimaryKey
    {
      oldSinglePrimaryKeyName = pkeys[0]
    }
    else {
      oldSinglePrimaryKeyName = nil
    }
    
    var renamedAttributes = [ String : String ]()
    if options.camelCaseAttributeNames {
      for attr in newEntity.attributes {
        guard let ma = attr as? ModelAttribute else {
          assert(attr is ModelAttribute) // we copied deep, should be all model
          continue
        }
        
        guard !attr.hasExplicitExternalName                   else { continue }
        guard !options.onlyLowerCase || attr.name.isLowerCase else { continue }
        
        if options.camelCaseAttributeNames || oldSinglePrimaryKeyName != nil {
          let oldName = attr.name
          if attr.columnName == nil {
            ma.columnName = oldName
          }
          
          // TODO: special case: 'id' for single primary key
          if let pk = oldSinglePrimaryKeyName, oldName == pk {
            ma.name = "id"
          }
          else {
            ma.name = oldName.camelCase
          }
          renamedAttributes[oldName] = ma.name
        }
      }
    }

    if !renamedAttributes.isEmpty {
      renamedAttributesByNewEntityNames[newEntity.name] = renamedAttributes
    }
    
    // map primary key names
    
    if let oldPKeys = newEntity.primaryKeyAttributeNames, !oldPKeys.isEmpty {
      newEntity.primaryKeyAttributeNames = oldPKeys.map {
        renamedAttributes[$0] ?? $0
      }
    }
    
    assignPrimaryKeyIfMissing(newEntity)
    patchValueTypesOfAttributes(newEntity)
    recordRelationshipsOfNewEntity(newEntity)
    
    return newEntity
  }
  
  func assignPrimaryKeyIfMissing(_ newEntity: ModelEntity) {
    guard newEntity.primaryKeyAttributeNames?.count ?? 0 == 0 else { return }
    
    if options.detectIdAsPrimaryKey && newEntity[attribute: "id"] != nil {
      newEntity.primaryKeyAttributeNames = [ "id" ]
    }
    else if options.detectTableIdAsPrimaryKey {
      let keyname = (newEntity.externalName ?? newEntity.name)
                  + options.keyColumnSuffix
      if let attr = newEntity[columnName: keyname] {
        newEntity.primaryKeyAttributeNames = [ attr.name ]
      }
    }
  }
  
  func patchValueTypesOfAttributes(_ newEntity: Entity) {
    // TBD: maybe value-type assignment shaould be always done in here?
    // convert Value type to bool type, e.g. of the column name starts with an
    // 'is_'
    
    guard !options.boolValueTypePrefixes.isEmpty else { return }
      
    for attr in newEntity.attributes {
      let cn = attr.columnName ?? attr.name
      guard !options.onlyLowerCase || cn.isLowerCase else { continue }
      
      guard let ma = attr as? ModelAttribute else {
        assert(attr is ModelAttribute) // we copied deep, should be all model
        continue
      }
      
      if let urlSuffix = options.urlSuffix, cn.hasSuffix(urlSuffix) {
        if let oldVT = ma.valueType {
          if oldVT.isOptional {
            if oldVT.optionalBaseType == String.self {
              ma.valueType = Optional<URL>.self
            }
          }
          else {
            if oldVT == String.self {
              ma.valueType = URL.self
            }
          }
        }
        else {
          ma.valueType = (ma.allowsNull ?? true) ? Optional<URL>.self : URL.self
        }
        continue
      }
      
      for prefix in options.boolValueTypePrefixes {
        if cn.hasPrefix(prefix) {
          // Note: this includes NULL columns in a special way!
          // TBD: only certain types of valueTypes?
          ma.valueType = Bool.self
        }
      }
    }
  }
  
  /// process relationships, record for later patching
  func recordRelationshipsOfNewEntity(_ newEntity: Entity) {
    for rs in newEntity.relationships {
      guard let mrs = rs as? ModelRelationship else {
        assert(rs is ModelRelationship) // we copied deep, should be all model
        continue
      }
      
      modelRelationships.append(mrs)
    }
  }
}


// MARK: - String Helpers

#if os(Linux)
  import func Glibc.isupper
#else
  import func Darwin.isupper
#endif

import struct Foundation.CharacterSet

fileprivate extension Entity {
  
  var hasExplicitExternalName : Bool {
    guard let en = externalName else { return false }
    return en != name
  }

  func availableName(_ names: String...) -> String? {
    for name in names {
      if self[relationship: name] == nil &&
         self[attribute:    name] == nil
      {
        return name
      }
    }
    return nil
  }
}

fileprivate extension Attribute {
  
  var hasExplicitExternalName : Bool {
    guard let en = columnName else { return false }
    return en != name
  }
  
}

fileprivate extension Relationship {
  
  var foreignKey1 : String? {
    guard joins.count == 1 else { return nil }
    let join = joins[0]
    return join.sourceName ?? join.source?.name
  }
  
  var isNameConstraintName : Bool {
    guard let en = constraintName else { return false }
    return en == name
  }
  
  func isReciprocalTo(relationship: Relationship) -> Bool {
    if let dmrs = relationship as? ModelRelationship,
       let destDestEntityName = dmrs.destinationEntityName
    {
      guard destDestEntityName == entity.name else { return false }
    }
    else if let destEntity = relationship.destinationEntity {
      // TBD: compare just names? Hm.
      if entity !== destEntity { return false }
    }
    else { // no target entity?
      return false
    }
    
    return areJoinsReciprocalTo(relationship: relationship)
  }
  
  func areJoinsReciprocalTo(relationship: Relationship) -> Bool {
    guard joins.count == relationship.joins.count else { return false }
    
    // FIXME: ordering doesn't have to be the same?!
    for i in 0..<joins.count {
      let baseJoin = joins[i]
      let destJoin = relationship.joins[i]
      
      guard baseJoin.isReciprocalTo(join: destJoin) else { return false }
    }
    return true
  }
  
}

extension String {
  
  var toName : String {
    return "to" + capitalized
  }
  var withoutId : String? {
    guard hasSuffix("Id")      else { return nil }
    guard characters.count > 2 else { return nil }
    let endIdx   = self.index(endIndex, offsetBy: -2)
    return String(self[startIndex..<endIdx])
  }
  
  var decapitalized : String {
    guard !isEmpty else { return "" }
    
    let idx = self.index(after: self.startIndex)
    let c0 = self.substring(to: idx).lowercased()
    return c0 + self.substring(from: idx)
  }

  func makeCamelCase(upperFirst: Bool) -> String {
    guard !self.isEmpty else { return "" }
    var newChars = [ Character ]()
    
    var upperNext = upperFirst
    for c in characters {
      switch c {
        case " ", "_": // skip and upper next
          // FIXME: wrong behaviour for columns starting with _
          upperNext = true
          continue
        case "a"..."z":
          if upperNext {
            let s = String(c).uppercased()
            newChars.append(s[s.startIndex])
            upperNext = false
          }
          else {
            newChars.append(c)
          }
        default:
          upperNext = false
          newChars.append(c)
      }
    }
    
    guard !newChars.isEmpty else { return self }
    return String(newChars)
  }
  var capCamelCase : String { return makeCamelCase(upperFirst: true) }
  var camelCase    : String { return makeCamelCase(upperFirst: false) }
  
  var isLowerCase : Bool {
    guard !isEmpty else { return false }
    let upper = CharacterSet.uppercaseLetters
    for c in self.unicodeScalars {
      if upper.contains(c) { return false }
    }
    return true
  }
  
  var isMixedCase : Bool {
    guard !isEmpty else { return false }
    let upper = CharacterSet.uppercaseLetters
    let lower = CharacterSet.lowercaseLetters
    
    var hadUpper = false
    var hadLower = false
    for c in self.unicodeScalars {
      if upper.contains(c) {
        if hadLower { return true }
        hadUpper = true
      }
      else if lower.contains(c) {
        if hadUpper { return true }
        hadLower = true
      }
    }
    return false
  }
    
}
