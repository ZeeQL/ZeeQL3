//
//  ModelPattern.swift
//  ZeeQL3
//
//  Created by Helge Heß on 31.10.24.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

fileprivate extension ModelAttribute {
  
  /**
   * - Parameters:
   *   - inAttrs: The attributes that got fetched from the database
   *   - entity:  The template entity.
   *   - attrs:   The list to be filled.
   */
  func addAttributesMatchingAttributes(_ inAttrs: [ Attribute ],
                                       entity: Entity,
                                       to attrs: inout [ Attribute ])
  {
    if patternType == .skip { return } // do not add
    if patternType != .columnName {
      /* check whether we are contained */
      // TODO: is this correct, could be more than 1 attribute with the same
      //       column?
      /* check whether we are contained */
      if let columnName = columnName { // this CAN be nil!
        if inAttrs.contains(where: { $0.columnName == columnName }) {
          attrs.append(self)
        }
        else {
          globalZeeQLLogger.warn("Did not find column", columnName,
                                 "in template", entity.name,
                                 "in database:", inAttrs)
          
        }
      }
      else {
        // If we do NOT have a column name, this means that columnName is the
        // SAME like the attributeName, e.g. `zip` in `address`.
        if inAttrs.contains(where: { $0.columnName == name }) {
          let attr = ModelAttribute(attribute: self)
          attr.columnName = name
          attrs.append(attr)
        }
        else {
          globalZeeQLLogger.warn("Did not find column w/ name", columnName,
                                 "\n  in template", entity.name,
                                 "\n  in database:", inAttrs)
          
        }
      }
      
      // We have NO column name!
      return
    }
    
    /* OK, now we need to evaluate the pattern and clone ourselves */
    
    for inAttr in inAttrs {
      guard let colname = inAttr.columnName else {
        assert(inAttr.columnName != nil, "Attribute has no column name?")
        continue
      }
      guard doesColumnNameMatchPattern(colname) else {
        print("MISMATCH:", colname, "ME:", self.columnName ?? "-", self.name, self)
        continue
      }
      
      /* check whether we already have an attribute for that column */
      
      do {
        if entity.attributes.contains(where: { $0.columnName == colname }) {
          #if false // this is OK
          print("template:", entity.name, "already contains column", colname)
          #endif
          continue
        }
        
        /* eg: 'name'='description' in the model (Company) vs column='name'
         *     in the schema */
        if entity[attribute: colname] != nil { // TBD
          // TBD: better keep the other attr and rename it
          #if false // this also happens
          print("template:", entity.name, "already contains attr:", colname)
          #endif
          continue
        }
      }
      
      /* clone and add */
      
      let attr = ModelAttribute(attribute: inAttr)
      assert(inAttr.columnName != nil)
      attr.name       = inAttr.columnNameOrName // should always be colname
      attr.columnName = inAttr.columnName
      attrs.append(attr)
    }
  }

}

fileprivate extension ModelEntity {
  
  @discardableResult
  func addEntitiesMatchingTableNames(_ tableNames: [ String ],
                                     to entities: inout [ Entity ]) -> Bool
  {
    guard !tableNames.isEmpty else { return false }

    if !isExternalNamePattern {
      /* check whether we are contained */
      guard let externalName = externalName else { return false }
      let containsUs = tableNames.contains(externalName)
      if containsUs { entities.append(self) }
      return containsUs
    }

    /* OK, now we need to evaluate the pattern and clone ourselves */
    
    for tableName in tableNames where doesExternalNameMatchPattern(tableName) {
      let entity = ModelEntity(entity: self, deep: true) // TBD
      entity.isExternalNamePattern = false
      entity.name         = tableName // TBD
      entity.externalName = tableName
      entities.append(entity)
    }
    return true
  }
  
  func doesExternalNameMatchPattern(_ tableName: String) -> Bool {
    if !isExternalNamePattern { return tableName == externalName }

    // TODO: fix pattern handling, properly process '*' etc
    return (externalName ?? "").contains(tableName)
  }
  
  func resolveEntityPatternWithModel(_ storedModel: Model) -> Entity? {
    let log = globalZeeQLLogger
    assert(externalName != nil, "No external name in entity? \(self)")
    guard isPattern, let externalName = externalName else { return self }

    /* lookup peer entity in database model */

    guard let storedEntity =
            storedModel.firstEntityWith(externalName: externalName) else
    {
      log.error("database model contains no peer for pattern entity:", self)
      return nil
    }

    /* first evaluate column patterns */

    var resolvedList = [ Attribute ]()
    resolvedList.reserveCapacity(attributes.count)

    /* now lets each entity produce a clone for the given table */
    for attr in attributes {
      guard let modelAttr = attr as? ModelAttribute else {
        log.warn("Pattern model contained non-ModelAttribute?", attr)
        continue
      }
      modelAttr.addAttributesMatchingAttributes(storedEntity.attributes,
                                                entity: self, to: &resolvedList)
    }

    /* fill column attributes */

    for ( idx, attribute ) in zip(resolvedList.indices, resolvedList) {
      guard attribute.isPattern else { continue }
      guard let attribute = attribute as? ModelAttribute else {
        log.warn("Pattern model resolved non-ModelAttribute?", attribute)
        continue
      }

      let storedAttrMaybe : ModelAttribute? = {
        if let colName = attribute.columnName {
          if let attr = storedEntity.attributes
            .first(where: { $0.columnName == colName })
          {
            if let model = attr as? ModelAttribute {
              return model
            }
            else {
              log.warn("Attr matched columnName but isn't non-ModelAttribute?",
                       attr)
            }
          }
        }
        /* try to lookup using name */
        if let attr = storedEntity[attribute: attribute.name] {
          if let model = attr as? ModelAttribute {
            return model
          }
          else {
            log.warn("Attr matched name but isn't non-ModelAttribute?", attr)
          }
        }
        return nil
      }()
      guard let storedAttr = storedAttrMaybe else {
        log.error("database model contains no peer for attribute:" , attribute)
        return nil
      }
      
      let newAttribute = attribute.resolvePatternWith(attribute: storedAttr)

      if newAttribute.isPattern {
        log.warn("attribute is still a pattern after resolve:\n  a:",
                 attribute, "\n  s:", storedAttr);
        assertionFailure("Pattern resolution failed?")
      }
      resolvedList[idx] = newAttribute
    }

    let lAttrs = resolvedList

    /* derive information from the peer */

    let lName    = self.name // TBD: column vs storedEntity name?
    let lTable   = self.externalName ?? storedEntity.externalName

    // recalculate those, later we might want to join them when available
    let props : [ String ]? = nil

    // TODO: this would probably need some more work
    #if false
    let rels = storedEntity.relationships
    #else
    let rels : [ Relationship ]
    if relationships.isEmpty {
      rels = storedEntity.relationships
    }
    else if storedEntity.relationships.isEmpty {
      rels = relationships
    }
    else {
      assertionFailure("Cannot (properly) merge relationships just yet.")
      rels = storedEntity.relationships + relationships
    }
    // They are still connected to the original model, reset this.
    rels.compactMap { $0 as? ModelRelationship }.forEach {
      $0.destinationEntity = nil
    }
    #endif

    // not derived:
    //   restrictingQualifier
    //   fetchSpecifications

    /* construct */

    let newEntity = ModelEntity(name: lName, table: lTable, isPattern: false)
    newEntity.schemaName = schemaName ?? storedEntity.schemaName
    newEntity.className  = className  ?? storedEntity.className
    newEntity.dataSourceClassName = dataSourceClassName
                        ?? (storedEntity as? ModelEntity)?.dataSourceClassName
    
    newEntity.attributes               = lAttrs
    newEntity.relationships            = rels
    newEntity.classPropertyNames       = props
    newEntity.primaryKeyAttributeNames = primaryKeyAttributeNames
                                      ?? storedEntity.primaryKeyAttributeNames
    newEntity.fetchSpecifications      = fetchSpecifications
    newEntity.adaptorOperations        = adaptorOperations

    newEntity.attributesUsedForLocking = attributesUsedForLocking
                    ?? storedEntity.attributesUsedForLocking
    newEntity.restrictingQualifier     = restrictingQualifier
    newEntity.isReadOnly               = isReadOnly

    if newEntity.isPattern {
      log.warn("entity is still a pattern after resolve:", newEntity,
               ", stored:", storedEntity)
    }

    return newEntity
  }
}


public extension Adaptor {
  
  /**
   * Resolves a pattern model against data fetched from the information schema.
   *
   * This does not touch the `model` property of the adaptor. It opens a channel
   * to the database, fetches the information schema and then resolves the
   * pattern against that.
   *
   * - Parameters:
   *   - pattern: A pattern Model, if the model is not a pattern, it is
   *              returned as is.
   * - Returns:   The resolved pattern model.
   */
  func resolveModelPattern(_ pattern: Model) throws -> Model? {
    guard pattern.isPattern else { return pattern }

    var entities = pattern.entities
    if entities.isEmpty { /* not sure whether this is a good idea */
      return try fetchModel()
    }

    log.info("starting to resolve pattern model ...");

    /* start fetches */

    let channel = try openChannelFromPool()
    defer { releaseChannel(channel) }

    /* determine set of entities to work upon (tableNameLike) */

    if pattern.hasEntitiesWithExternalNamePattern {
      // TODO: maybe we should improve this for database which have a
      //       large number of dynamic tables (some kind of on-demand
      //       loading?)
      //       We could also declare an entity as having a "static"
      //       structure?
      log.info("  resolving dynamic table names ...");

      let tableNames = try channel.describeTableNames()
      log.info("  fetched table names:", tableNames.joined(separator: ", "))

      var resolvedList = [ Entity ]()
      resolvedList.reserveCapacity(tableNames.count)

      /* now lets each entity produce a clone for the given table */
      for entity in entities {
        guard let modelEntity = entity as? ModelEntity else {
          log.warn("Pattern model contained non-ModelEntity?", entity)
          continue
        }
        modelEntity
          .addEntitiesMatchingTableNames(tableNames, to: &resolvedList)
      }

      entities = resolvedList
    }

    if !entities.isEmpty {
      /* now collect all table names */

      let tableNames = entities.compactMap { $0.externalName }

      /* fetch model for the tables we operate on */

      guard let storedModel =
              try channel.describeModelWithTableNames(tableNames) else
      {
        log.error("The database doesn't provide information for all tables,",
                  "cannot resolve model:", tableNames.joined(separator: ", "))
        return nil
      }

      /* now give all entities a chance to update their information */

      for ( idx, entity ) in zip(entities.indices, entities) {
        log.info("    resolving entity:", entity.name);
        guard let modelEntity = entity as? ModelEntity else {
          log.warn("Pattern model resolved non-ModelEntity?", entity)
          continue
        }
        guard let resolved =
                modelEntity.resolveEntityPatternWithModel(storedModel) else
        {
          log.warn("Could not resolve entity?", modelEntity)
          continue
        }
        entities[idx] = resolved
      }
    }

    /* create model object */

    let newModel = Model(entities: entities)
    log.info("finished resolving pattern model:", newModel)

    newModel.connectRelationships()

    #if DEBUG
    for entity in entities {
      for relship in entity.relationships {
        assert(relship.isConnected)
        assert(relship.destinationEntity != nil)
      }
    }
    #endif
    
    return newModel
  }
}
