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
    var oldToGroup    = [ String : [ Entity ] ]()
    var sameGroups    = [ ( [ Entity ], [ Entity ] ) ]()
    
    for oldGroup in oldGroups {
      let tableName = oldGroup.groupExternalName
      if !newTables.contains(tableName) {
        droppedGroups.append(oldGroup)
      }
      oldToGroup[tableName] = oldGroup
    }
    
    for group in newGroups {
      guard !group.isEmpty else { continue }
      
      let tableName = group.groupExternalName
      
      if !oldTables.contains(tableName) { // group is new
        createdGroups.append(group)
        continue
      }

      guard let oldGroup = oldToGroup[tableName]
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
