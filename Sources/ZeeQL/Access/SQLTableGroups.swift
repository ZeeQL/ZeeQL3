//
//  SQLTableGroups.swift
//  ZeeQL3
//
//  Created by Helge Hess on 10/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

typealias SQLTableGroup = [ Entity ]

/// Table Groups are an internal feature and should not be exposed.
///
/// A table group is a set of entities that have the same 'externalName'. I.e.
/// are defined on the same table in the store.

extension Sequence where Iterator.Element == Entity { // a flat Entity array
  
  /**
   * Groups entities by external name.
   *
   * Usually there is just one entity per table, but there can be more with
   * entity-inheritance.
   *
   * Note: this is unrelated to PostgreSQL table inheritance.
   */
  func extractEntityGroups() -> [ SQLTableGroup ] {
    var nameToIndex  = [ String : Int ]()
    var entityGroups = [ SQLTableGroup ]()
    
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
    return first.externalNameOrName
  }
  
  var groupAttributes : [ Attribute ] {
    func columnNameForAttribute(_ attr: Attribute) -> String {
      // could also do a translation when missing
      return attr.columnNameOrName
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

extension Sequence where Iterator.Element == Entity { // an egroup
  
  var groupForeignKeys : Set<SQLForeignKey> {
    var foreignKeys = Set<SQLForeignKey>()
    for entity in self {
      foreignKeys.formUnion(entity.relationships.flatMap { $0.foreignKey })
    }
    return foreignKeys
  }

}


// MARK: - Helpers

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
  
  var ssfDestinationName : String? {
    return destinationEntity?.name
        ?? (self as? ModelRelationship)?.destinationEntityName
  }
}
