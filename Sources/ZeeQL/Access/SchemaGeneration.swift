//
//  SchemaGeneration.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.06.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

public protocol SchemaGeneration: AnyObject {
  
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
   *
   * SQLite doesn't support this (2023-09-06).
   */
  var supportsDirectForeignKeyModification : Bool { get }
}

public class SchemaGenerationOptions { // TBD: Make that an optionset?
  
  var dropTables              = true
  var createTables            = true
  var embedConstraintsInTable = true
}

private func orderEntityGroupsForCreation(_ groups: [ SQLTableGroup ])
             -> [ SQLTableGroup ]
{
  guard groups.count > 1 else { return groups }

  var dependencies = Array(repeating: Set<Int>(), count: groups.count)
  for source in groups.indices {
    for destination in groups.indices where source != destination {
      if groups[source].countReferencesToEntityGroup(groups[destination]) > 0 {
        dependencies[source].insert(destination)
      }
    }
  }

  func isPreferred(_ candidate: Int, over current: Int?) -> Bool {
    guard let current else { return true }
    let candidateName = groups[candidate].groupExternalName
    let currentName   = groups[current].groupExternalName
    if candidateName != currentName { return candidateName < currentName }
    return candidate < current
  }

  var remaining = Set(groups.indices)
  var ordered   = [ SQLTableGroup ]()
  ordered.reserveCapacity(groups.count)
  while !remaining.isEmpty {
    var next: Int?
    for candidate in remaining
      where dependencies[candidate].isDisjoint(with: remaining)
    {
      if isPreferred(candidate, over: next) { next = candidate }
    }
    if next == nil {
      for candidate in remaining {
        if isPreferred(candidate, over: next) { next = candidate }
      }
    }
    guard let next else { break }
    ordered.append(groups[next])
    remaining.remove(next)
  }
  return ordered
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
        entityGroups = orderEntityGroupsForCreation(entityGroups)
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
    
    let primaryKeyNames = rootEntity.primaryKeyAttributeNames ?? []
    let hasCompositePrimaryKey = primaryKeyNames.count > 1
    for attr in attributes {
      // A composite key must be emitted as one table-level constraint.
      expr.addCreateClauseForAttribute(
        attr, in: hasCompositePrimaryKey ? nil : rootEntity)
    }
    if hasCompositePrimaryKey {
      let columns = primaryKeyNames.compactMap {
        rootEntity[attribute: $0]?.columnNameOrName
      }
      if columns.count == primaryKeyNames.count {
        if !expr.listString.isEmpty { expr.listString += ",\n" }
        expr.listString += "PRIMARY KEY ( "
        expr.listString += columns.map {
          expr.sqlStringFor(schemaObjectName: $0)
        }.joined(separator: ", ")
        expr.listString += " )"
      }
      else {
        log.error("Could not resolve composite primary key:", rootEntity)
      }
    }
    
    var sql = "CREATE TABLE "
    sql += expr.sqlStringFor(schemaObjectName: table)
    sql += " ( "
    sql += expr.listString
    
    var constraintNames = Set<String>()
    for rs in relships {
      guard rs.isForeignKeyRelationship else { continue }
      
      let fkexpr = adaptor.expressionFactory.createExpression(rootEntity)
      guard let fkSQL  = fkexpr.sqlForForeignKeyConstraint(rs) else {
        log.warn("Could not create constraint statement for relationship:", rs)
        continue
       }
      
      var needsAlter = true
      
      if options.embedConstraintsInTable ||
         !supportsDirectForeignKeyModification
      {
        let destination = rs.destinationEntity?.externalName
                       ?? rs.destinationEntity?.name
        if !supportsDirectForeignKeyModification
           || destination.map(createdTables.contains) == true
        {
          sql += ",\n"
          if let name = rs.constraintName, !name.isEmpty {
            sql += "CONSTRAINT "
            sql += expr.sqlStringFor(schemaObjectName: name)
            sql += " "
          }
          sql += fkSQL
          needsAlter = false
        }
      }
      
      if needsAlter {
        var constraintName: String
        if let name = rs.constraintName, !name.isEmpty {
          constraintName = name
        }
        else {
          constraintName = rs.name
        }
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
