//
//  DatabaseObject.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Interface of read/write ORM objects.
 */
public protocol DatabaseObject : SwiftObject,
                                 StoreKeyValueCodingType,
                                 DatabaseObjectValidation,
                                 RelationshipManipulation
{

  /* initialization */
  // TODO: those are for AR, there are others for TC based objects
  
  func awakeFromFetch    (_ db: Database)
  func awakeFromInsertion(_ db: Database) // only makes sense w/ EC

  /* snapshot management */
  
  var snapshot : Snapshot? { get }
  func updateFromSnapshot (_ snap: Snapshot) -> Bool
  func changesFromSnapshot(_ snap: Snapshot) -> Snapshot
  // func reapplyChangesFromDictionary(_ snap: Snapshot) TODO
  
  /* accessor management */
  
  func willRead()
  func willChange()
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
  
  /* snapshot management */
  
  func updateFromSnapshot (_ snap: Snapshot) -> Bool {
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
  
  func reapplyChangesFromDictionary(_ snap: AdaptorRecord) {
    for ( key, snapValue ) in snap {
      takeStoredValue(snapValue, forKey: key) // TBD
    }
  }
  
  /* accessor management */
  
  func willRead()   {}
  func willChange() {}
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
public protocol RelationshipManipulation : class, KeyValueCodingType {
  
  /**
   * Add an object to the array stored under '_key'.
   */
  func addObject   (_ object: AnyObject, toPropertyWithKey key: String)
  
  /**
   * Remove an object to the array stored under '_key'.
   */
  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String)
  
  // MARK: - Both Sides

  func addObject   (_ object: RelationshipManipulation,
                    toBothSidesOfRelationshipWithKey key: String)
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
}

public extension RelationshipManipulation { // default imp
  
  func addObject(_ object: AnyObject, toPropertyWithKey key: String) {
    // TODO
    fatalError("not implemented: \(#function)")
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
     *       relationship. ActiveRecord changes this.
     */
    addObject(object, toPropertyWithKey: key)
  }
  
  func removeObject(_ object: RelationshipManipulation,
                    fromBothSidesOfRelationshipWithKey key: String)
  {
    /* Note: we don't know the Entity here, so we can't access the inverse
     *       relationship. ActiveRecord changes this.
     */
    removeObject(object, fromPropertyWithKey: key)
  }
}
