//
//  SchemaGeneration.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.06.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol SchemaGeneration: class {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }
  
  var createdTables   : Set<String>       { get set }
  var extraTableJoins : [ SQLExpression ] { get set }
  
  func reset()
  
  func appendExpression(_ expr: SQLExpression, toScript sb: inout String)
  
  func schemaCreationStatementsForEntities(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]

  func createTableStatementsForEntityGroup(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]

  func dropTableStatementsForEntityGroup(_ entities: [ Entity ])
       -> [ SQLExpression ]

  /**
   * Supports:
   *   ALTER TABLE table ADD CONSTRAINT table2target
   *         FOREIGN KEY ( target_id ) REFERENCES target( target_id );
   *   ALTER TABLE table DROP CONSTRAINT table2target;
   *     - Note: constraint name must be known!
   */
  var supportsDirectForeignKeyModification : Bool { get }
}

public class SchemaGenerationOptions {
  
  var dropTables              = true
  var createTables            = true
  var embedConstraintsInTable = true
  
}

public extension SchemaGeneration {
  
  func reset() {
    createdTables.removeAll()
    extraTableJoins.removeAll()
  }
  
  func appendExpression(_ expr: SQLExpression, toScript sb: inout String) {
    sb += expr.statement
  }
  
  func schemaCreationStatementsForEntities(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]
  {
    reset()
    
    var statements = [ SQLExpression ]()
    statements.reserveCapacity(entities.count * 2)
    
    var entityGroups = entities.extractEntityGroups()
    
    if options.dropTables {
      for group in entityGroups {
        statements.append(contentsOf: dropTableStatementsForEntityGroup(group))
      }
    }
    
    if options.createTables {
      if !supportsDirectForeignKeyModification ||
         options.embedConstraintsInTable // not strictly necessary but nicer
      {
        entityGroups.sort { lhs, rhs in // areInIncreasingOrder
          let lhsr = lhs.countReferencesToEntityGroup(rhs)
          let rhsr = rhs.countReferencesToEntityGroup(lhs)
          
          if lhsr < rhsr { return true  }
          if lhsr > rhsr { return false }
        
          // sort by name
          return lhs[0].name < rhs[0].name
        }
      }
      
      for group in entityGroups {
        let sa = createTableStatementsForEntityGroup(group, options: options)
        statements.append(contentsOf: sa)
      }
      
      statements.append(contentsOf: extraTableJoins)
    }
    
    return statements
  }
  
  func createTableStatementsForEntityGroup(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]
  {
    guard !entities.isEmpty else { return [] }
    
    // collect attributes, unique columns and relationships we want to create
    
    let attributes = entities.groupAttributes
    let relships   = entities.groupRelationships
    
    // build statement
    
    let rootEntity = entities[0] // we may or may not want to find the actual
    let table = rootEntity.externalName ?? rootEntity.name
    let expr  = adaptor.expressionFactory.createExpression(rootEntity)

    assert(!createdTables.contains(table))
    createdTables.insert(table)
    
    for attr in attributes {
      // TBD: is the pkey handling right for groups?
      expr.addCreateClauseForAttribute(attr, in: rootEntity)
    }
    
    var sql = "CREATE TABLE "
    sql += expr.sqlStringFor(schemaObjectName: table)
    sql += " ( "
    sql += expr.listString
    
    var constraintNames = Set<String>()
    for rs in relships {
      guard rs.isForeignKeyRelationship else { continue }
      
      let fkexpr = adaptor.expressionFactory.createExpression(rootEntity)
      guard let fkSQL  = fkexpr.sqlForForeignKeyConstraint(rs)
       else {
        log.warn("Could not create constraint statement for relationship:", rs)
        continue
       }
      
      var needsAlter = true
      
      if options.embedConstraintsInTable && rs.constraintName == nil {
        // if the constraint has an explicit name, keep it!
        
        if let dest = rs.destinationEntity?.externalName
                   ?? rs.destinationEntity?.name,
           createdTables.contains(dest)
        {
          sql += ",\n"
          sql += fkSQL
          needsAlter = false
        }
      }
      
      if needsAlter {
        var constraintName : String = rs.constraintName ?? rs.name
        if constraintNames.contains(constraintName) {
          constraintName = rs.name + String(describing: constraintNames.count)
          if constraintNames.contains(constraintName) {
            log.error("Failed to generate unique name for constraint:", rs)
            continue
          }
        }
        constraintNames.insert(constraintName)
        
        var sql = "ALTER TABLE "
        sql += expr.sqlStringFor(schemaObjectName: table)
        sql += " ADD CONSTRAINT "
        sql += expr.sqlStringFor(schemaObjectName: constraintName)
        sql += " "
        sql += fkSQL
        fkexpr.statement = sql
        extraTableJoins.append(fkexpr)
      }
    }
    
    sql += " )"
    expr.statement = sql
    
    return [ expr ]
  }
  
  func dropTableStatementsForEntityGroup(_ entities: [ Entity ])
       -> [ SQLExpression ]
  {
    // we just drop the single table shared by all, right?
    guard !entities.isEmpty else { return [] }
    
    let rootEntity = entities[0] // we may or may not want to find the actual
    let table      = rootEntity.externalName ?? rootEntity.name
    let expr       = adaptor.expressionFactory.createExpression(rootEntity)
    
    expr.statement = "DROP TABLE " + expr.sqlStringFor(schemaObjectName: table)
    return [ expr ]
  }
}

fileprivate extension Relationship {
  
  var constraintKey : String? {
    guard !joins.isEmpty else { return nil }
    
    func keyForJoin(_ join: Join) -> String {
      return (join.sourceName ?? "_") + "=>" + (join.destinationName ?? "_")
    }
    
    if joins.count == 1 { return keyForJoin(joins[0]) }
    
    let sortedJoins = joins.map(keyForJoin).sorted()
    return sortedJoins.joined(separator: ",")
  }
  
  var isForeignKeyRelationship : Bool {
    guard !isToMany      else { return false }
    guard !joins.isEmpty else { return false }
    return true
  }

  var ssfDestinationName : String? {
    return destinationEntity?.name
        ?? (self as? ModelRelationship)?.destinationEntityName
  }
}

extension Sequence where Iterator.Element == Entity { // a flat Entity array
  
  /**
   * Groups entities by external name.
   *
   * Usually there is just one entity per table, but there can be more with
   * entity-inheritance.
   *
   * Note: this is unrelated to PostgreSQL table inheritance.
   */
  func extractEntityGroups() -> [ [ Entity ] ] {
    var nameToIndex  = [ String : Int ]()
    var entityGroups = [ [ Entity ] ]()
    
    for entity in self {
      if let key = entity.externalName, !key.isEmpty {
        if let idx = nameToIndex[key] {
          entityGroups[idx].append(entity)
        }
        else {
          nameToIndex[key] = entityGroups.count
          entityGroups.append([ entity ])
        }
      }
      else {
        entityGroups.append([ entity ])
      }
    }
    
    return entityGroups
  }
}

extension Sequence where Iterator.Element == Entity { // a table group
  
  var groupExternalName : String {
    var iter = makeIterator()
    guard let first = iter.next() else {
      assert(false, "entity group contains no entities")
      return ""
    }
    return first.externalName ?? first.name
  }
  
  var groupAttributes : [ Attribute ] {
    func columnNameForAttribute(_ attr: Attribute) -> String {
      // could also do a translation when missing
      return attr.columnName ?? attr.name
    }
    
    var attributes        = [ Attribute    ]()
    var registeredColumns = Set<String>()
    
    for entity in self {
      for attr in entity.attributes {
        let columnName = columnNameForAttribute(attr)
        if registeredColumns.contains(columnName) {
          // TBD: We may want to 'merge' attributes as the entities may have
          //      different rules on them.
          continue
        }
        attributes.append(attr)
        registeredColumns.insert(columnName)
      }
    }
    
    return attributes
  }
  
  var groupRelationships : [ Relationship ] {
    var relships                = [ Relationship ]()
    var registeredRelationships = Set<String>()
    
    for entity in self {
      for rs in entity.relationships {
        guard let key = rs.constraintKey             else { continue }
        guard !registeredRelationships.contains(key) else { continue }
        relships.append(rs)
        registeredRelationships.insert(key)
      }
    }
    
    return relships
  }

  /**
   * Returns the names of the entities referenced by an entity group from
   * within to-one relationships (aka foreign keys).
   *
   * Excluded are self-references.
   *
   * Example:
   *   `addressEntityGroup.entityNamesReferencedBySchemaGroup()`
   * may return `[ Person ]` if an address entity has a toOne relationship
   * to the `Person` entity.
   */
  func entityNamesReferencedBySchemaGroup() -> Set<String> {
    let ownNames = Set<String>(self.map( { $0.name } ))
    var names    = Set<String>()
    
    for entity in self {
      for relship in entity.relationships {
        guard relship.isForeignKeyRelationship     else { continue }
        guard let name = relship.ssfDestinationName else { continue }
        
        guard !ownNames.contains(name) else { continue }
        names.insert(name)
      }
    }
    return names
  }
  
  /**
   * Counts how many toOne references the `self` entity group has to the
   * other entity group.
   */
  func countReferencesToEntityGroup<T: Sequence>(_ other: T) -> Int
         where T.Iterator.Element == Iterator.Element
  {
    let ownNames = Set<String>(self.map( { $0.name } ))
    var count = 0
    for entity in self {
      for relship in entity.relationships {
        guard relship.isForeignKeyRelationship      else { continue }
        guard let name = relship.ssfDestinationName else { continue }
        
        guard !ownNames.contains(name) else { continue }
        
        count += 1
      }
    }
    return count
  }
  
}
