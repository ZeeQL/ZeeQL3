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
open class SchemaSynchronizationFactory: SchemaGeneration, SchemaSynchronization
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
  
  open func synchronizeModels(old: Model, new: Model) {
    // Note: run SQLizer and/or FancyModelMaker before merging! (TBD)
    
    // WORK IN PROGRESS, TODO
    
    log.log("from:", old)
    log.log("to:  ", new)
    log.log("-----------------------------------------")
    
    let changes = new.entities.calculateTableChanges(since: old.entities)
    log.log("  changes:", changes)
    
    log.log("dropped: ", changes.dropped)
    log.log("created: ", changes.created)
    log.log("same:    ", changes.same)
    
    for ( old, new ) in changes.same {
      let changes = new.calculateAttributeChanges(since: old)
      log.log("\nTable:", new.groupExternalName)
      log.log("  dropped: ", changes.dropped)
      log.log("  created: ", changes.created)
      log.log("  same:    ", changes.same)
    }
    
    log.log("-----------------------------------------")
  }
}

extension Sequence where Iterator.Element == Entity { // an array of entities

  /// This takes two sequences of entities, NOT groups. It does *return*
  /// groups though.
  func calculateTableChanges<T: Sequence>(since oldSeq: T)
       -> SchemaSyncChangeSet<[Entity]>
         where T.Iterator.Element == Iterator.Element
  {
    // TODO: optimize ;->
    let oldGroups = oldSeq.extractEntityGroups()
    let newGroups = self.extractEntityGroups()
    let oldTables = Set<String>(oldGroups.map { $0.groupExternalName })
    let newTables = Set<String>(newGroups.map { $0.groupExternalName })
    
    var createdGroups = [ [ Entity ] ]()
    var droppedGroups = [ [ Entity ] ]()
    var oldSame    = [ String : [ Entity ] ]()
    var sameGroups    = [ ( [ Entity ], [ Entity ] ) ]()
    
    for oldGroup in oldGroups {
      let tableName = oldGroup.groupExternalName
      if !newTables.contains(tableName) {
        droppedGroups.append(oldGroup)
      }
      oldSame[tableName] = oldGroup
    }
    
    for group in newGroups {
      guard !group.isEmpty else { continue }
      
      let tableName = group.groupExternalName
      
      if !oldTables.contains(tableName) { // group is new
        createdGroups.append(group)
        continue
      }

      guard let oldGroup = oldSame[tableName]
       else {
        assert(false, "internal inconsistency on table \(tableName)")
        continue
       }
      
      sameGroups.append( ( oldGroup, group ) )
    }
    
    return SchemaSyncChangeSet(created : createdGroups,
                               dropped : droppedGroups,
                               same    : sameGroups)
  }
}

extension Sequence where Iterator.Element == Entity { // an entity group
  
  func calculateAttributeChanges<T: Sequence>(since oldEntity: T)
       -> SchemaSyncChangeSet<Attribute>
         where T.Iterator.Element == Iterator.Element
  {
    let oldAttrs   = oldEntity.groupAttributes
    let newAttrs   = self.groupAttributes
    let oldColumns = Set<String>(oldAttrs.map { $0.columnName ?? $0.name })
    let newColumns = Set<String>(newAttrs.map { $0.columnName ?? $0.name })
    
    var oldSame = [ String : Attribute ]()
    var created = [ Attribute ]()
    var dropped = [ Attribute ]()
    var same    = [ ( Attribute, Attribute ) ]()
    
    for attr in oldAttrs {
      let column = attr.columnName ?? attr.name
      if !newColumns.contains(column) { dropped.append(attr)   }
      else                            { oldSame[column] = attr }
    }
    
    for attr in newAttrs {
      let column = attr.columnName ?? attr.name
      if !oldColumns.contains(column)       { created.append(attr)             }
      else if let oldAttr = oldSame[column] { same.append( ( oldAttr, attr ) ) }
      else { assert(false, "internal inconsistency: \(attr)") }
    }
    
    return SchemaSyncChangeSet(created: created, dropped: dropped, same: same)
  }
}

final class SchemaSyncChangeSet<T> {
  let created : [ T ]
  let dropped : [ T ]
  let same    : [ ( T, T ) ]
  
  init(created: [ T ] = [], dropped: [ T ] = [], same: [ ( T, T ) ] = []) {
    self.created = created
    self.dropped = dropped
    self.same    = same
  }
}
