//
//  DatabaseObject.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

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
      let value = self.value(forKey: key)
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
      let value = self.value(forKey: key)
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
  case ReadOnly(DatabaseObject)
  case NoDatabase(DatabaseObject)
}


/**
 * RelationshipManipulation
 *
 * Special KVC functions for toMany keys in ORM objects.
 */
public protocol RelationshipManipulation
  : AnyObject, KeyValueCodingType, MutableKeyValueCodingType
{
  
  /**
   * Add an object to the array stored under '_key'.
   */
  func addObject   (_ object: AnyObject, toPropertyWithKey key: String)
  
  /**
   * Remove an object to the array stored under '_key'.
   */
  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String)
  
  // MARK: - Both Sides (called by DatabaseChannel)

  func addObject   (_ object: RelationshipManipulation,
                    toBothSidesOfRelationshipWithKey key: String)
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
}

public extension RelationshipManipulation { // default imp
  
  func addObject(_ object: AnyObject, toPropertyWithKey key: String) {
    // TBD: this is, sigh.
    // also, the KVC access is still a little open, this should do
    // takeValueForKey in case the subclass overrides it
    let log = globalZeeQLLogger
    
    // If it is a to-one, we push the object itself into the relship.
    if let object = object as? DatabaseObject {
      do {
        try takeValue(object, forKey: key)
      }
      catch {
        log.error("Could not take toOne relationship for key:", key)
      }
      return
    }
    
    // TBD: Really AnyObject? Rather `DatabaseObject`?
    // Because the input is like that!
    do {
      if var list = value(forKey: key) as? [ AnyObject ] {
        list.append(object)
        try takeValue(list, forKey: key)
      }
      else {
        try takeValue([ object ], forKey: key)
      }
    }
    catch {
      log.error("Could not take toMany relationship for key:", key)
    }
  }
  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String) {
    // TODO
    fatalError("not implemented: \(#function)")
  }

  // MARK: - Both Sides
  
  func addObject   (_ object: RelationshipManipulation,
                    toBothSidesOfRelationshipWithKey key: String)
  {
    /* Note: we don't know the Entity here, so we can't access the inverse
     *       relationship. ActiveRecord COULD change this. It doesn't, because
     *       it creates a cycle.
     */
    addObject(object, toPropertyWithKey: key)
  }
  
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
  {
    /* Note: we don't know the Entity here, so we can't access the inverse
     *       relationship. ActiveRecord COULD change this. It doesn't, because
     *       it creates a cycle.
     */
    removeObject(object, fromPropertyWithKey: key)
  }
}
