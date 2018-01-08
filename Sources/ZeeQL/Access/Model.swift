//
//  Model.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * A ZeeQL.Model represents the mapping between the database schema and the
 * object model in the application. For example it can be used to map
 * rows of a "person" database table to a "Person" Swift class.
 *
 * Models can be loaded from XML files, they can be created out of the database
 * schema, or they can be represented in code (with the help of `CodeEntity` etc
 * model objects).
 *
 * Note: Many hipster frameworks use the term `Model` to represent a single
 *       entity, for example `Person`. ZeeQL uses the naming of the so-called
 *       [Entity–relationship
 *          model](https://en.wikipedia.org/wiki/Entity–relationship_model).
 *
 *
 * TODO: explain more
 *
 *
 * ## Access Model Information
 *
 * In the current version a model is just a set of entities. You can access
 * them using a subscript, e.g.:
 *
 *     let entityNames = model.entityNames
 *     for entityName in entityNames {
 *       guard let entity = model[entity: entityName] else { continue }
 *       ...
 *     }
 *
 *
 * ## Model tags
 *
 * Especially during development, you may want to detect whether a model
 * changed. This is supported by the adaptors using a `model tag`.
 * That tag will change, when the database model was modified.
 * The actual implementation of the tag is opaque and differs between the
 * databases (e.g. on PG it is a hash over the information schema, while
 * SQLite has a schema modification sequence).
 *
 * TODO: explain more
 *
 *
 * ## Pattern Models
 *
 * Models can be 'pattern models'. Pattern models retrieve database tables and
 * table columns from the database' information schema. This way you only need
 * to map things which actually require a mapping.
 *
 * When the model is then used with an adaptor, the adaptor will fetch the
 * information schema of the database, build a derived model, and then merge
 * that with the pattern model.
 *
 * TODO: explain more
 *
 *
 * ## XML file format:
 *
 * ZeeQL comes w/ an own XML format for storing models. There is no requirement
 * to use this.
 *
 *   <model version="1.0">
 *     <entity tableNameLike="subscriber*"> <!-- dynamically load tables -->
 *       <attribute name="subscriber" />
 *     </entity>
 *
 *     <entity tableName="account">
 *       <!-- dynamically load all attributes -->
 *       <attribute columnNameLike="*" />
 *     </entity>
 *   </model>
 *
 * Do we actually have this in ZeeQL? I think this is GETobjects only :->
 *
 *
 * ## CoreData Model Loader
 *
 * TODO: explain `CoreDataModelLoader`
 *
 */
open class Model : SmartDescription {
  // TODO: actually implement pattern models
  // TODO: add loading

  open var log      : ZeeQLLogger = globalZeeQLLogger
  open var tag      : ModelTag?
  open var entities : [ Entity ]
  
  public init(entities: [ Entity ], tag: ModelTag? = nil) {
    self.entities = entities
    self.tag      = tag
  }
  
  public init(model: Model, deep: Bool = true) {
    // TBD: keep tag?
    if deep {
      self.entities = [ Entity ]()
      for entity in model.entities {
        entities.append(ModelEntity(entity: entity, deep: true))
      }
      connectRelationships()
    }
    else {
      entities = model.entities
    }
  }

  open var entityNames : [ String ] {
    return entities.map({$0.name})
  }
  
  open var isPattern : Bool {
    if self.entities.isEmpty { return true }
    for entity in self.entities {
      if entity.isPattern { return true }
    }
    return false
  }
  
  
  /**
   * Return the first entity which has a matching name.
   */
  open subscript(entity n: String) -> Entity? {
    // TODO: use a map if this turns out to be a common thing
    for entity in entities {
      if n == entity.name { return entity }
    }
    return nil
  }
  
  /**
   * Return the entities which represent the given external name (table name).
   */
  open subscript(entityGroup externalName: String) -> [ Entity ] {
    // TODO: use a map if this turns out to be a common thing
    var group = [ Entity ]()
    for entity in entities {
      if let n = entity.externalName {
        if n == externalName {
          group.append(entity)
        }
      }
    }
    if group.isEmpty { // next try regular names
      for entity in entities {
        if entity.externalName == nil && entity.name == externalName {
          group.append(entity)
        }
      }
    }
    return group
  }
  
  /**
   * Return the first entity which has a matching externalName.
   *
   * This first scans entities which do have an externalName,
   * and then scans all entities which do not (comparing against the plain 
   * name).
   */
  open func firstEntityWith(externalName n: String) -> Entity? {
    // TODO: use a map if this turns out to be a common thing
    for entity in entities {
      guard let en = entity.externalName else { continue }
      if n == en { return entity }
    }
    for entity in entities {
      guard entity.externalName == nil else { continue }
      if n == entity.name { return entity }
    }
    return nil
  }
  
  open func entityForObject(_ object: Any?) -> Entity? {
    guard let object = object else { return nil }
    
    // scan by type (TBD: is this actually sound?)
    let objectType = type(of: object)
    for entity in entities {
      guard let type = entity.objectType else { continue }
      if type == objectType { return entity }
    }
    
    // scan be name
    let typeName = String(describing: objectType)
    for entity in entities {
      guard let name = entity.className else { continue }
      if name == typeName { return entity }
    }
    
    log.warn("Did not find entity for object: \(object) " +
             "type: \(objectType)/\(typeName)")
    return nil
  }
  
  open func connectRelationships() {
    for entity in entities {
      entity.connectRelationships(in: self)
    }
  }
  open func disconnectRelationships() { // free cycles
    for entity in entities {
      entity.disconnectRelationships()
    }
  }
  
  /**
   * Returns true if the model contains an entity which has a pattern in its
   * external name.
   */
  var hasEntitiesWithExternalNamePattern : Bool {
    if entities.isEmpty { return true } // yes, fetch all
    for entity in entities {
      if let modelEntity = entity as? ModelEntity {
        if modelEntity.isExternalNamePattern { return true }
      }
    }
    return false
  }
  
  // TODO: prototypes
  
  
  // MARK: - Merging
  
  open func merge(_ model: Model) {
    if tag != nil {
      log.trace("dropping model tag during merge ...", tag)
    }
    tag = nil

    for entity in model.entities {
      entities.append(entity)
    }
  }
  
  
  // MARK: - Description
  
  open func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    if entities.isEmpty {
      ms += " no-entities"
    }
    else {
      ms += " entities: {\n"
      var isFirst = true
      for entity in entities {
        entity.appendToDescription(&ms)
        ms += isFirst ? "\n" : ",\n"
        isFirst = false
      }
      ms += "}"
    }
  }
}

/**
 * Adaptor specific cache marker. The tag changes when anything the database
 * schema changed.
 */
public protocol ModelTag : EquatableType {
  // Note: cannot be `Equatable`, unfortunately
}
