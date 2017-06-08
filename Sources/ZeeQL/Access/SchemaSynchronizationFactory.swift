//
//  SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Object used to generate database DDL expressions (i.e. CREATE TABLE and 
 * such). Similar to `SQLExpression`.
 *
 * To acquire a `SchemaSynchronizationFactory` use the
 * `Adaptor.synchronizationFactory` property as the adaptor may provide a
 * subclass w/ customized generation.
 *
 * Note: This is a stateful object.
 */
open class SchemaSynchronizationFactory:
            SchemaGeneration, SchemaSynchronization
{
  public let log     : ZeeQLLogger
  public let adaptor : Adaptor

  public var createdTables   = Set<String>()
  public var extraTableJoins = [ SQLExpression ]()
  
  public init(adaptor: Adaptor) {
    self.adaptor = adaptor
    self.log     = self.adaptor.log
  }

  open var supportsDirectForeignKeyModification     : Bool { return true }
  open var supportsDirectColumnCoercion             : Bool { return true }
  open var supportsDirectColumnDeletion             : Bool { return true }
  open var supportsDirectColumnInsertion            : Bool { return true }
  open var supportsDirectColumnNullRuleModification : Bool { return true }
  open var supportsDirectColumnRenaming             : Bool { return true }
  open var supportsSchemaSynchronization            : Bool { return true }
  
}

public extension Adaptor {
  
  /// Note: Returns a stateful object (a new one every time it is accessed).
  var synchronizationFactory : SchemaSynchronizationFactory {
    return SchemaSynchronizationFactory(adaptor: self)
  }
  
}


// MARK: - Generation

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
  
  func columnNameForAttribute(_ attr: Attribute) -> String {
    // could also do a translation when missing
    return attr.columnName ?? attr.name
  }
  
  func createTableStatementsForEntityGroup(_ entities: [ Entity ],
                                           options: SchemaGenerationOptions)
       -> [ SQLExpression ]
  {
    guard !entities.isEmpty else { return [] }
    
    // collect attributes, unique columns and relationships we want to create
    
    var attributes = [ Attribute    ]() // rather to attributeGroups?
    var relships   = [ Relationship ]()
    
    var registeredColumns       = Set<String>()
    var registeredRelationships = Set<String>()
    
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
        guard let key = rs.constraintKey             else { continue }
        guard !registeredRelationships.contains(key) else { continue }
        relships.append(rs)
        registeredRelationships.insert(key)
      }
    }
    
    
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

fileprivate extension Sequence where Iterator.Element == Entity {
  
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

  /**
   * Returns the names of the entities referenced by an entity group from
   * within to-one relationships (aka foreign keys).
   *
   * Excluded are self-references.
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


// MARK: - Synchronization

public protocol SchemaSynchronization : SchemaGeneration {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }

  /// Supports: ALTER TABLE table ALTER COLUMN column TYPE newType;
  var supportsDirectColumnCoercion             : Bool { get }
  
  /// Supports: ALTER TABLE table DROP COLUMN column [CASCADE];
  var supportsDirectColumnDeletion             : Bool { get }
  /// Supports: ALTER TABLE table ADD COLUMN column TEXT;
  var supportsDirectColumnInsertion            : Bool { get }
  
  /// Supports: ALTER TABLE table ALTER COLUMN column SET  NOT NULL;
  ///           ALTER TABLE table ALTER COLUMN column DROP NOT NULL;
  var supportsDirectColumnNullRuleModification : Bool { get }
  
  /// Supports: ALTER TABLE table RENAME COLUMN column TO newName;
  var supportsDirectColumnRenaming             : Bool { get }
  
}

public extension SchemaSynchronization {
}
