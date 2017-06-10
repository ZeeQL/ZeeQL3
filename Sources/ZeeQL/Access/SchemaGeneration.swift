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
