//
//  DatabaseObject.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

#if compiler(>=6.2)
/**
 * Interface of read/write ORM objects.
 */
public protocol DatabaseObject : DatabaseObjectValidation,
                                 RelationshipManipulation,
                                 SnapshotObject, SendableMetatype
{
  /* initialization */
  // TODO: those are for AR, there are others for TC based objects
  
  func awakeFromFetch    (_ db: Database)
  func awakeFromInsertion(_ db: Database) // only makes sense w/ EC
  
  /* accessor management */
  
  func willRead()
  func willChange()
}
#else
/**
 * Interface of read/write ORM objects.
 */
public protocol DatabaseObject : DatabaseObjectValidation,
                                 RelationshipManipulation,
                                 SnapshotObject
{
  /* initialization */
  // TODO: those are for AR, there are others for TC based objects
  
  func awakeFromFetch    (_ db: Database)
  func awakeFromInsertion(_ db: Database) // only makes sense w/ EC
  
  /* accessor management */
  
  func willRead()
  func willChange()
}
#endif

public protocol SnapshotObject : SwiftObject, StoreKeyValueCodingType {
  
  /* snapshot management */
  
  func updateFromSnapshot (_ snap: Snapshot) -> Bool
  func changesFromSnapshot(_ snap: Snapshot) -> Snapshot
  // func reapplyChangesFromDictionary(_ snap: Snapshot) TODO
}

public protocol SnapshotHoldingObject : SnapshotObject {
  // Snapshot Management is an ActiveRecord only thing. Regular EOs use
  // the ObjectStore for snapshotting.
  
  /**
   * The snapshot associated with the object.
   */
  var snapshot : Snapshot? { get }

  /**
   * Revert all the changes recorded in the object's snapshot.
   */
  func revert()
}

/**
 * In a way a database row.
 *
 * Those have `Any?` values because they can be used standalone, that is w/o
 * an associated entity. To represent database NULL values, we need the
 * Optional.
 * Example:
 *
 *     [ "firstname": nil, "lastname": "Duck" ]
 *
 * (in objects w/ an entity attached we can just leave out the `firstname`, but
 *  in standalone records, we need to record the fact that the specific keys
 *  needs to be NULL in a qualifier (or be set to NULL in an UPDATE))
 */
public typealias Snapshot = Dictionary<String, Any?>

fileprivate let debugChanges = false

public extension DatabaseObject { // default imp
  
  /* initialization */
  
  func awakeFromFetch    (_ db: Database) {}
  func awakeFromInsertion(_ db: Database) {}
  
  /* accessor management */
  
  func willRead()   {}
  func willChange() {}
}

public extension SnapshotObject { // default imp
  
  // Careful: The snapshot has to cover ALL values, including nil values!
  // Otherwise it can't revert back properly or calculate changes!
  
  /* snapshot management */
  
  @discardableResult
  func updateFromSnapshot(_ snap: Snapshot) -> Bool {
    takeStoredValues(snap)
    return true
  }
  
  /**
   * Returns the changes in the object since the last snapshot was taken (since
   * the last fetch).
   */
  func changesFromSnapshot(_ snap: Snapshot) -> Snapshot {
    var changes = Snapshot()

    if debugChanges { globalZeeQLLogger.log("snapshot:", snap) }
    for ( key, snapValue ) in snap {
      let value = self.valueForKey(key)
      let eqv   = value as EquatableType
      
      if debugChanges {
        globalZeeQLLogger.log("  value \(key):", value, type(of:value),
                              snapValue, type(of: snapValue))
      }
      
      if eqv.isEqual(to: snapValue) { // still the same
        continue
      }
      if debugChanges {
        globalZeeQLLogger.log("  not equal", eqv, "vs", snapValue)
      }
      
      if debugChanges { globalZeeQLLogger.log("  change \(key):", value) }
      changes[key] = value
    }
    
    if debugChanges { globalZeeQLLogger.log("changes:", changes) }
    return changes
  }
  
  /**
   * Returns whether the object has changes since the last snapshot was taken
   * (since the last fetch).
   */
  func hasChangesFromSnapshot(_ snap: Snapshot) -> Bool {
    if debugChanges { globalZeeQLLogger.log("snapshot:", snap) }
    for ( key, snapValue ) in snap {
      let value = self.valueForKey(key)
      let eqv   = value as EquatableType
      
      if debugChanges {
        globalZeeQLLogger.log("  value \(key):", value, type(of:value),
                              snapValue, type(of: snapValue))
      }
      
      if eqv.isEqual(to: snapValue) { // still the same
        continue
      }
      if debugChanges {
        globalZeeQLLogger.log("  not equal", eqv, "vs", snapValue)
      }
      
      if debugChanges { globalZeeQLLogger.log("  change \(key):", value) }
      return true
    }
    
    if debugChanges { globalZeeQLLogger.log("no changes.") }
    return false
  }

  func reapplyChangesFromDictionary(_ snap: AdaptorRecord) {
    for ( key, snapValue ) in snap {
      takeStoredValue(snapValue, forKey: key) // TBD
    }
  }
}

public extension SnapshotHoldingObject {
  
  func revert() {
    guard let snapshot = snapshot else { return } // no snap?
    let changes = changesFromSnapshot(snapshot)
    guard !changes.isEmpty else { return } // nothing changed, feel the same.
    
    for key in changes.keys {
      guard let oldValue = snapshot[key] else { continue } // double any
      takeStoredValue(oldValue, forKey: key)
    }
  }
}


public protocol DatabaseObjectValidation {
  
  func validateForInsert() throws
  func validateForDelete() throws
  func validateForUpdate() throws
  func validateForSave()   throws
}

public extension DatabaseObjectValidation { // default imp
  
  func validateForInsert() throws {}
  func validateForDelete() throws {}
  func validateForUpdate() throws {}
  func validateForSave()   throws {}
}

public enum DatabaseObjectError : Swift.Error {
  case readOnly(DatabaseObject)
  case noDatabase(DatabaseObject)
}


/// KVC operations for adding and removing related objects.
public protocol RelationshipManipulation: AnyObject, KeyValueCodingType,
                                          MutableKeyValueCodingType
{
  
  /// Assign a to-one relationship or add an object to a to-many relationship.
  func addObject   (_ object: AnyObject, toPropertyWithKey key: String)
  
  /// Clear a to-one relationship or remove an object from a to-many collection.
  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String)
  
  // MARK: - Both Sides (called by DatabaseChannel)

  func addObject   (_ object: RelationshipManipulation,
                    toBothSidesOfRelationshipWithKey key: String)
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
}

public extension RelationshipManipulation { // default imp

  /**
   * Use instance or static entity metadata to detect toOne/Many.
   */
  func addObject(_ object: AnyObject, toPropertyWithKey key: String) {
    let log = globalZeeQLLogger
    do {
      if !isToManyRelationship(key) {
        try takeValue(object, forKey: key)
        return
      }

      if let value = valueForKey(key) {
        guard var objects = value as? [ AnyObject ] else {
          log.error("Expected a to-many collection for key:", key)
          return
        }
        guard !objects.contains(where: { $0 === object }) else { return }
        objects.append(object)
        try takeValue(objects, forKey: key)
      }
      else {
        try takeValue([ object ], forKey: key)
      }
    }
    catch {
      log.error("Could not add relationship object for key:", key, error)
    }
  }

  /// Remove by identity
  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String) {
    let log = globalZeeQLLogger
    guard let value = valueForKey(key) else { return }
    do {
      if !isToManyRelationship(key) {
        guard value as AnyObject === object else { return }
        try takeValue(nil, forKey: key)
        return
      }

      guard var objects = value as? [ AnyObject ] else {
        log.error("Expected a to-many collection for key:", key)
        return
      }
      guard let index = objects.firstIndex(where: { $0 === object }) else {
        return
      }
      objects.remove(at: index)
      try takeValue(objects, forKey: key)
    }
    catch {
      log.error("Could not remove relationship object for key:", key, error)
    }
  }

  private func isToManyRelationship(_ key: String) -> Bool {
    let entity: Entity?
    if let object = self as? ActiveRecordType {
      entity = object.entity
    }
    else if let entityType = type(of: self) as? EntityType.Type {
      entity = entityType.entity
    }
    else {
      entity = nil
    }
    return entity?[relationship: key]?.isToMany ?? true
  }

  // MARK: - Both Sides
  
  func addObject   (_ object: RelationshipManipulation,
                    toBothSidesOfRelationshipWithKey key: String)
  {
    // Preserve the single-side default. Conformers that maintain inverse
    // relationships can override this helper.
    addObject(object, toPropertyWithKey: key)
  }
  
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
  {
    // Preserve the single-side default. Conformers that maintain inverse
    // relationships can override this helper.
    removeObject(object, fromPropertyWithKey: key)
  }
}
