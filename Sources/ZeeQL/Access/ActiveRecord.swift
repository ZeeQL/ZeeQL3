//
//  ActiveRecord.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * A concrete implementation of the `ActiveRecordType`. Can be used as a
 * standalone object, or as a base class for a model object.
 *
 * This type of object tracks the snapshot inside the object itself.
 * Which is different to CD, which tracks the snapshot in the database context.
 * The disadvantage is that we cannot map to POSOs but objects need to be
 * subclasses of ActiveRecord to implement change tracking.
 */
open class ActiveRecordBase : ActiveRecordType, SmartDescription {
  // Note: ActiveRecordBase is just here so that we can #ifdef Combine and
  //       Swift 5 features below.
  
  @inlinable
  open class var database : Database? {
    return nil
  }
  
  var _database : Database?
  func lookupDatabase() -> Database? {
    if let db = _database               { return db }
    if let db = type(of: self).database { return db }
    return nil
  }
  open var database : Database {
    guard let db = lookupDatabase() else {
      fatalError("could not determine database of ActiveRecord: \(self)")
    }
    return db
  }
  
  var _entity : Entity?
  func lookupEntity() -> Entity? {
    if let entity = _entity { return entity }
    
    if let refEntity = reflectedEntity {
      willChange()
      _entity = refEntity
      return refEntity
    }

    if let db = _database, let entity = db.entityForObject(self) {
      return entity
    }
    
    return nil
  }
  
  open var entity : Entity {
    if let entity = lookupEntity() { return entity }
    fatalError("missing entity for object")
  }
  
  public var isNew    : Bool = true // reset when awakeFromFetch is called!
  
  public var values   = [ String : Any  ]()
  public var snapshot : [ String : Any? ]?
 
  public required init() {}
  public func bind(to db: Database, entity: Entity?) {
    self._database = db
    self._entity   = entity
  }
  
  
  // MARK: - Awake
  
  open func willRead()   {}
  open func willChange() {}

  open func awakeFromFetch(_ db: Database) {
    // called by DatabaseChannel)
    _database = db
    isNew = false
    if _entity == nil { _entity = db.entityForObject(self) }
  }
  
  open func awakeFromInsertion(_ db: Database) {
    // called when a new object (never saved) enters a context.
    _database = db
    isNew = true // TBD?
    if _entity == nil { _entity = db.entityForObject(self) }
  }
  
  
  // MARK: - Object Information

  /**
   * Returns whether or not the object can be modified.
   *
   * Objects are r/o if the associated entity is marked r/o.
   * They are also marked r/o if no snapshot has been made during loading
   * (e.g. if the caller did a r/o transaction).
   */
  open var isReadOnly : Bool {
    // TBD: separate permission for 'isReadOnly' and 'canCreate'?
    if let entity = lookupEntity() { if entity.isReadOnly { return true } }
    if isNew { return false }
    if snapshot == nil { return true } // no snapshot was made!
    return false // got a snapshot
  }
  
  /**
   * Returns whether or not the object has any pending changes.
   *
   * The actual changes can be calculated using the `changesFromSnapshot`
   * function.
   */
  @inlinable
  public var hasChanges : Bool {
    if isNew                           { return true  }
    guard let snapshot = snapshot else { return false }
    return hasChangesFromSnapshot(snapshot)
  }
  

  // MARK: - KVC
  // TBD: the KVC and StoredKVC are very similar, but not the same? They should
  //      be the same as they perform no extra work here?

  open func takeValue(_ value: Any?, forKey k: String) throws {
    // Note: `values` itself is a [String:Any?], so all that may be superfluous.
    willChange()
    
    // Note: There is no default setter! This is why this always pushes into
    //       the dictionary!
    // TODO: Since the stable v5 ABI we *can* do KVC setters, implement them!
    if let value = value {
      values[k] = value // values is wrapped again in an Optional<Any>
    }
    else {
      values.removeValue(forKey: k)
    }
  }
  
  open func value(forKey k: String) -> Any? { // dupe for protocol override
    willRead()
    
    // first check extra properties
    if let v = values[k] {
      return v
    }
    
    // then fallback to KVC
    if let v = KeyValueCoding.defaultValue(forKey: k, inObject: self) {
      return v
    }
    
    return nil
  }
  
  
  open func storedValue(forKey k: String) -> Any? {
    willRead()
    
    if let v = value(forKey: k) { return v } // ask regular KVC
    if let v = values[k]        { return v }
    return nil
  }
  
  open func takeStoredValue(_ v: Any?, forKey k: String) {
    willChange() // TODO: only on actual change
    values[k] = v
  }
  
  public func addObject(_ object: AnyObject, toPropertyWithKey key: String) {
    // TBD: this is, sigh.
    willChange()
    
    // If it is a to-one, we push the object itself into the relship.
    if let relship = entity[relationship: key], !relship.isToMany {
      takeStoredValue(object, forKey: key)
      return
    }
    
    // TBD: Really AnyObject? Rather `DatabaseObject`?
    // Because the input is like that!
    if var list = storedValue(forKey: key) as? [ AnyObject ] {
      list.append(object)
      takeStoredValue(list, forKey: key)
    }
    else {
      takeStoredValue([ object ], forKey: key)
    }
  }
  public func removeObject(_ o: AnyObject, fromPropertyWithKey key: String) {
    willChange()

    // If it is a to-one, we clear the object itself into the relship.
    if let relship = entity[relationship: key], !relship.isToMany {
      takeStoredValue(nil, forKey: key)
      return
    }

    guard var list = storedValue(forKey: key) as? [ AnyObject ] else { return }
    #if swift(>=5)
      guard let idx = list.firstIndex(where: { $0 === o }) else { return }
    #else
      guard let idx = list.index(where: { $0 === o }) else { return }
    #endif
    
    list.remove(at: idx)
    takeStoredValue([ list ], forKey: key)
  }
  
  
  // MARK: - Save
  
  open func validateForSave() throws {
    guard !isReadOnly else { throw DatabaseObjectError.ReadOnly(self) }
  }
  
  open func save() throws {
    /* Note: we have no reference to the datasource which is why we can't
     *       just call the matching methods in there. But the datasource knows
     *       about us and lets us do the work.
     */
    guard let db = lookupDatabase() else {
      throw DatabaseObjectError.NoDatabase(self)
    }
    
    /* validate and create database operation */
    
    /* Note: there is no databaseOperationForSave() method because we return
     *       the exceptions.
     */
    
    var op : DatabaseOperation
    
    willChange()
    
    if isNew {
      try validateForInsert()
      op = DatabaseOperation(self)
      op.databaseOperator = .insert
      // TBD: shouldn't we do?:
      //        op.newRow  = changesFromSnapshot(this.snapshot)
    }
    else {
      try validateForUpdate()
      op = DatabaseOperation(self)
      op.databaseOperator = .update
    }
    
    if let snap = snapshot {
      op.dbSnapshot = snap
    }
    
    // if successful, this updates tracking state
    try db.performDatabaseOperations([ op ])
  }

  open func delete() throws {
    try validateForDelete()

    willChange()

    /* check for new objects */

    guard !isNew else { return } /* nothing to be done in the DB */

    guard let db = lookupDatabase() else {
      throw DatabaseObjectError.NoDatabase(self)
    }
    
    /* create database operation */

    let op = DatabaseOperation(self)
    op.databaseOperator = .delete
    
    if let snap = snapshot {
      op.dbSnapshot = snap
    }
    
    // if successful, this updates tracking state
    try db.performDatabaseOperations([ op ])
  }
  
  
  // MARK: - Description

  open func appendToDescription(_ ms: inout String) {
    ms += " [\(entity.name)]"
    
    if isNew { ms += " NEW" }
    
    for ( key, value ) in values {
      ms += " \(key)=\(value)"
    }
    
    if let snapshot = snapshot {
      ms += snapshot.isEmpty ? " empty-snap?" : " SNAPed"
    }
  }

  
  // MARK: - Create Entity by reflecting the record
  
  public var reflectedEntity : Entity? {
    // Note: Swift cannot reflect on a Type, the instance is required
    let mirror = Mirror(reflecting: self)
    
    var attributes = [ Attribute ]()
    var names      = [ String ]()
    
    for ( propname, propValue ) in mirror.children {
      guard let propname = propname else { continue }
      
      // TODO: SQLify column-name
      let attribute = ModelAttribute(name: propname)
      
      let valueMirror = Mirror(reflecting: propValue)
      if valueMirror.displayStyle == .optional {
        attribute.allowsNull = true
        
        if valueMirror.children.count > 0 {
          let (_, some) = valueMirror.children.first!
          
          // FIXME: I don't think we want to do this in here. Swift type to
          //        external type mapping needs to be done in the adaptor. And
          //        it already does some of it.
          let someMirror = Mirror(reflecting: some)
          if let extType = ZeeQLTypes.externalTypeFor(swiftType:
                                                        someMirror.subjectType,
                                                      includeConstraint: false)
          {
            attribute.externalType = extType
          }
          else { // skip
            continue
          }
        }
        else { // value is set to nil
          let s = "\(valueMirror.subjectType)" // Optional<String>
          // TBD: is there a better way?
          
          guard s.hasPrefix("Optional<") && s.hasSuffix(">") else { continue }
          let fromIdx = s.index(s.startIndex, offsetBy: 9)
          let toIdx   = s.index(before: s.endIndex)
          let type    = String(s[fromIdx..<toIdx])
          
          if let extType = ZeeQLTypes.externalTypeFor(swiftType: type) {
            attribute.externalType = extType
          }
          else { // skip
            continue
          }
        }
      }
      else {
        attribute.allowsNull = false
        
        if let extType = ZeeQLTypes.externalTypeFor(swiftType:
                                                      valueMirror.subjectType)
        {
          attribute.externalType = extType
        }
        else { // skip
          continue
        }
      }
      
      names.append(propname)
      attributes.append(attribute)
    }
    
    // TODO: do not use ModelEntity
    let entityName = "\(type(of: self))"
    let entity = ModelEntity(name: entityName)
    entity.attributes = attributes
    
    if names.contains("id") {
      entity.primaryKeyAttributeNames = [ "id" ]
    }
    // TODO: company_id
    
    return entity
  }
}

#if swift(>=5)
  @dynamicMemberLookup
  open class ActiveRecord : ActiveRecordBase {
    
    public subscript(dynamicMember member: String) -> Any? {
      set {
        do {
          try takeValue(newValue, forKey: member)
        }
        catch {
          globalZeeQLLogger.error("failed to take value for dynamic member:",
                                  member, error)
          assertionFailure("failed to take value for dynamic member: \(member)")
        }
      }
      get { return value(forKey: member) }
    }
  }
#else
  open class ActiveRecord : ActiveRecordBase {}
#endif


#if TBD
extension ActiveRecord {
  
  class func findBy<T>(id: T) -> Self? {
    // FIXME: this doesn't invoke the actual type `database` method
    guard let db = Self.database else { return nil }
    
    globalZeeQLLogger.error("DB:", db)
    // TODO: Well, what?
    // - get a datasource for 'Self'
    // - invoke findBy method, return?
    
    return nil
  }
}
#endif
