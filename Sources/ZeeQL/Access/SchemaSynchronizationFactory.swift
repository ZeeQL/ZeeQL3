//
//  SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

open class SchemaSynchronizationFactory:
            SchemaGeneration, SchemaSynchronization
{
  public let log     : ZeeQLLogger
  public let adaptor : Adaptor
  
  public init(adaptor: Adaptor) {
    self.adaptor = adaptor
    self.log     = self.adaptor.log
  }
}

public extension Adaptor {
  
  var synchronizationFactory : SchemaSynchronizationFactory {
    return SchemaSynchronizationFactory(adaptor: self)
  }
  
}


// MARK: - Generation

public protocol SchemaGeneration {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }
  
  func appendExpression(_ expr: SQLExpression, toScript sb: inout String)
  
  func schemaCreationStatementsForEntities(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]

  func createTableStatementsForEntityGroup(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]

  func dropTableStatementsForEntityGroup(_ entities: [ Entity ])
       -> [ SQLExpression ]
}

public class SchemaGenerationOptions {
  
  var dropTables   = true
  var createTables = true
}

public extension SchemaGeneration {
  
  func appendExpression(_ expr: SQLExpression, toScript sb: inout String) {
    sb += expr.statement
  }
  
  func extractEntityGroups<T: Sequence>(_ entities: T) -> [ [ Entity ] ]
                           where T.Iterator.Element == Entity
  {
    var nameToIndex  = [ String : Int ]()
    var entityGroups = [ [ Entity ] ]()
    
    for entity in entities {
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
  
  func schemaCreationStatementsForEntities(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]
  {
    var statements = [ SQLExpression ]()
    statements.reserveCapacity(entities.count * 2)
    
    let entityGroups = extractEntityGroups(entities)
    
    if options.dropTables {
      for group in entityGroups {
        statements.append(contentsOf: dropTableStatementsForEntityGroup(group))
      }
    }
    
    if options.createTables {
      for group in entityGroups {
        let sa = createTableStatementsForEntityGroup(group, options: options)
        statements.append(contentsOf: sa)
      }
    }
    
    return statements
  }
  
  func columnNameForAttribute(_ attr: Attribute) -> String {
    // could also do a translation when missing
    return attr.columnName ?? attr.name
  }
  
  fileprivate func contraintKeyForRelationship(_ rs: Relationship) -> String? {
    guard !rs.joins.isEmpty else { return nil }

    func keyForJoin(_ join: Join) -> String {
      return (join.sourceName ?? "_") + "=>" + (join.destinationName ?? "_")
    }
    
    if rs.joins.count == 1 { return keyForJoin(rs.joins[0]) }
    
    let sortedJoins = rs.joins.map(keyForJoin).sorted()
    return sortedJoins.joined(separator: ",")
  }
  
  func createTableStatementsForEntityGroup(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]
  {
    guard !entities.isEmpty else { return [] }
    
    // collect attributes, unique columns and relationships we want to create
    
    var attributes = [ Attribute    ]() // rather to attributeGroups?
    var relships   = [ Relationship ]()
    
    var registeredColumns = Set<String>()
    var registeredJoins   = Set<String>()
    
    for entity in entities {
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
      
      for rs in entity.relationships {
        guard let key = contraintKeyForRelationship(rs) else { continue }
        guard !registeredJoins.contains(key)            else { continue }
        relships.append(rs)
        registeredJoins.insert(key)
      }
    }
    
    
    // build statement
    
    let rootEntity = entities[0] // we may or may not want to find the actual
    let table = rootEntity.externalName ?? rootEntity.name
    let expr  = adaptor.expressionFactory.createExpression(rootEntity)
    
    for attr in attributes {
      expr.addCreateClauseForAttribute(attr)
    }
    
    var sql = "CREATE TABLE "
    sql += expr.sqlStringFor(schemaObjectName: table)
    sql += " ( "
    sql += expr.listString
    
    // TODO: add constraints
    // FIXME: in SQLite this is the only place where we can add foreign key
    //        constraints! And we need proper ordering! (self-reference seems
    //        to be fine in both PG & SQLite)
    //        else: relation "contact" does not exist
    // e.g.:
    //   person_id INTEGER NOT NULL,
    //     FOREIGN KEY(person_id) REFERENCES person(person_id) DEFERRABLE
    
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


// MARK: - Synchronization

public protocol SchemaSynchronization {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }

  /// Supports: ALTER TABLE table ALTER COLUMN column TYPE newType;
  var supportsDirectColumnCoercion             : Bool { get }
  
  /// Supports: ALTER TABLE table DROP COLUMN column [CASCADE];
  var supportsDirectColumnDeletion             : Bool { get }
  /// Supports: ALTER TABLE table ADD COLUMN column TEXT;
  var supportsDirectColumnInsertion            : Bool { get }
  
  /**
   * Supports:
   *   ALTER TABLE table ADD CONSTRAINT table2target
   *         FOREIGN KEY ( target_id ) REFERENCES target( target_id );
   *   ALTER TABLE table DROP CONSTRAINT table2target;
   *     - Note: constraint name must be known!
   */
  var supportsDirectColumnForeignKeyModification : Bool { get }
  
  /// Supports: ALTER TABLE table ALTER COLUMN column SET  NOT NULL;
  ///           ALTER TABLE table ALTER COLUMN column DROP NOT NULL;
  var supportsDirectColumnNullRuleModification : Bool { get }
  
  /// Supports: ALTER TABLE table RENAME COLUMN column TO newName;
  var supportsDirectColumnRenaming             : Bool { get }
  
}

public extension SchemaSynchronization {
  
  var supportsDirectColumnCoercion               : Bool { return true }
  var supportsDirectColumnDeletion               : Bool { return true }
  var supportsDirectColumnInsertion              : Bool { return true }
  var supportsDirectColumnForeignKeyModification : Bool { return true }
  var supportsDirectColumnNullRuleModification   : Bool { return true }
  var supportsDirectColumnRenaming               : Bool { return true }
  var supportsSchemaSynchronization              : Bool { return true }
  
}
