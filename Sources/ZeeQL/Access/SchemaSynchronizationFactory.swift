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
    
    for ( old, new ) in changes.same {
      log.log("\nTable:", new.groupExternalName)
      do {
        let changes = new.calculateAttributeChanges(since: old)
        log.log("  dropped: ", changes.dropped)
        log.log("  created: ", changes.created)
        log.log("  same:    ", changes.same)
        
        for ( old, new ) in changes.same {
          // TODO: compare attributes
          guard let changes = new.changes(since: old) else { continue }
          log.log("    attr changes:", new.name, changes)
        }
      }
      do {
        let changes = new.calculateForeignKeyConstraintChanges(since: old)
        log.log("  dropped: ", changes.dropped)
        log.log("  created: ", changes.created)
      }
    }
    
    log.log("-----------------------------------------")
  }
}

fileprivate var log : ZeeQLLogger { return globalZeeQLLogger }

fileprivate extension Attribute {
  
  func isSameExternalTypeName(_ lhs: String, _ rhs: String) -> Bool {
    // FIXME: not really, they could be synonyms
    // TODO: this needs to live in the adaptor
    return lhs.uppercased() == rhs.uppercased()
  }
  func externalTypeForValueType(_ vt: AttributeValue.Type) -> String? {
    // FIXME: do this in the adaptor (/SQLExpression of the adaptor)
    return ZeeQLTypes.externalTypeFor(swiftType: vt, includeConstraint: false)
  }
  
  func changes(since old: Attribute) -> SQLAttributeChange? {
    var change = SQLAttributeChange()
    
    let oldName = old.columnName  ?? old.name
    let newName = self.columnName ?? self.name
    if oldName != newName { change.name = ( oldName, newName ) }
    
    if (old.allowsNull ?? true) != (self.allowsNull ?? true) {
      change.nullability = self.allowsNull ?? true
    }
    
    // Type changes are a little difficult as we need to consider both,
    // valueType and externalType.
    
    if let oldExt = old.externalType, let newExt = self.externalType {
      // if both have an external type assigned, this is authoritive
      if !isSameExternalTypeName(oldExt, newExt) {
        change.externalType = newExt
      }
      // else: considered the same
    }
    else if let oldVT = old.valueType?.optionalBaseType  ?? old.valueType,
            let newVT = self.valueType?.optionalBaseType ?? self.valueType
    {
      // FIXME: This needs to be more clever. Sometimes the external type
      //        doesn't really change.
      // - one of them could still have *one* external type
      if oldVT != newVT {
        // FIXME: can return nil, what then?
        change.externalType = externalType ?? externalTypeForValueType(newVT)
      }
      // else: considered the same
    }
    else {
      // either neither, or only one has an external type.
      
      // usually the old has an external type (fetched schema from DB). Well,
      // but usually it also has assigned a value type.
      
      print("TODO: complex type compare: \(old) \(self)")
    }
    
    return change.hasChanges ? change : nil
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

fileprivate extension Sequence where Iterator.Element == Entity { // an egroup
  
  func calculateForeignKeyConstraintChanges<T: Sequence>(since oldEntity: T)
       -> SchemaSyncChangeSet<SQLForeignKey>
         where T.Iterator.Element == Iterator.Element
  {
    let oldFKeys = oldEntity.groupForeignKeys
    let newFKeys = self.groupForeignKeys
    
    // Note: We don't track 'same' here, the ForeignKey value is a natural
    //       value. (and for schema sync we are not really interested in the
    //       'modelling' aspect of a relationship, just in the externals)
    
    let dropped = oldFKeys.flatMap { newFKeys.contains($0) ? nil : $0 }
    let created = newFKeys.flatMap { oldFKeys.contains($0) ? nil : $0 }
    
    return SchemaSyncChangeSet(created: created, dropped: dropped)
  }
  
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
