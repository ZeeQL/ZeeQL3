//
//  Entity.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * Entity objects usually represent a database table or view. Entity objects
 * are contained in Model objects and are usually looked up by name. To work
 * on the entity (fetch objects, insert/update/delete objects etc) you retrieve
 * an ActiveDataSource for some Database object (which in turn has a
 * pointer to the Model).
 *
 * Entity objects can be 'pattern' objects. That is, they can be incomplete and
 * may need to be 'filled' by querying the database information schema. This can
 * involve incomplete attribute sets or a pattern name.
 */
public protocol Entity: AnyObject, EquatableType, SmartDescription {

  var name                     : String              { get }
  var externalName             : String?             { get }
  var schemaName               : String?             { get }
  
  var isReadOnly               : Bool                { get }
  var isPattern                : Bool                { get }
  
  /// Whether a row should be fetched right after it got inserted. This is
  /// useful to capture default values in the SQL schema (or modifications done
  /// by insert triggers).
  var shouldRefetchOnInsert    : Bool                { get }
  
  // MARK: - Attributes & Relationships
  
  var attributes               : [ Attribute    ]    { get }
  var relationships            : [ Relationship ]    { get }
  var primaryKeyAttributeNames : [ String       ]?   { get }
    // TBD: ^^^ should those be non-optional? (hh 2024-12-21)

  /**
   * Returns the names of class property attributes and relationships. Those are
   * attributes which are exposed as a part of the database object.
   *
   * The class properties are a subset of the attributes and relship arrays. Eg
   * in an application you would not want to expose database specific details
   * like primary and foreign keys as class properties.
   */
  var classPropertyNames       : [ String       ]?   { get }
  
  /**
   * Returns the attributes which are used for optimistic locking. Those are
   * checked for changes when an UPDATE is attempted in the database. For
   * example in OGo we only need the 'objectVersion' as a change marker.
   */
  var attributesUsedForLocking : [ Attribute    ]?   { get }
  
  subscript(attribute    n: String) -> Attribute?    { get }
  subscript(columnName   n: String) -> Attribute?    { get }
  subscript(relationship n: String) -> Relationship? { get }

  func connectRelationships(in model: Model)
  func disconnectRelationships()
  
  // MARK: - Fetch Specifications

  var restrictingQualifier : Qualifier? { get }

  subscript(fetchSpecification n: String) -> FetchSpecification? { get }
  subscript(adaptorOperation   n: String) -> AdaptorOperation?   { get }
  
  // MARK: - Attached Type
  
  var className  : String?              { get }
  var objectType : DatabaseObject.Type? { get }
}


public extension Entity { // default imp
  
  @inlinable var externalName          : String? { return nil   }
  @inlinable var schemaName            : String? { return nil   }

  @inlinable var isReadOnly            : Bool    { return false }
  @inlinable var shouldRefetchOnInsert : Bool    { return true  }

  @inlinable var className  : String? {
    if let t = objectType { return "\(t)" }
    return nil
  }
  @inlinable var objectType : DatabaseObject.Type? { return nil }

  @inlinable var primaryKeyAttributeNames : [ String ]? {
    return lookupPrimaryKeyAttributeNames()
  }
  
  @inlinable
  func lookupPrimaryKeyAttributeNames() -> [ String ]? {
    // FancyModelMaker also has a `assignPrimaryKeyIfMissing`
    guard !attributes.isEmpty else { return nil }
    
    // plain names, like 'CREATE TABLE pets ( id INT NOT NULL, name ... )'
    let autoAttributeNames = [ "id", "pkey" ]
    for attr in attributes {
      if autoAttributeNames.contains(attr.name) { return [ attr.name ] }
    }
    
    // e.g. table 'company', id 'company_id'
    if let tableName = externalName {
      let pkeyName       = tableName + "_id"
      var hadColumnNames = false
      
      for attr in attributes {
        if let columnName = attr.columnName {
          hadColumnNames = true
          if columnName == pkeyName { return [ pkeyName ] }
        }
      }
      if !hadColumnNames { // scan regular names
        for attr in attributes {
          if attr.name == pkeyName { return [ pkeyName ] }
        }
      }
    }
    
    return nil
  }
  
  
  // MARK: - GlobalIDs
  
  @inlinable
  func globalIDForRow(_ row: AdaptorRecord?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map { row[$0] }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }
  @inlinable
  func globalIDForRow(_ row: AdaptorRow?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map { row[$0] ?? nil }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }
  @inlinable
  func globalIDForRow(_ row: Any?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map {
      KeyValueCoding.value(forKey: $0, inObject: row)
    }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }
  
  @inlinable
  func qualifierForGlobalID(_ globalID: GlobalID) -> Qualifier {
    #if !GLOBALID_AS_OPEN_CLASS
    let kglobalID = globalID
    #else
    guard let kglobalID = globalID as? KeyGlobalID else {
      globalZeeQLLogger.warn("globalID is not a KeyGlobalID:", globalID,
                             type(of: globalID))
      assertionFailure("attempt to use an unsupported globalID \(globalID)")
      return BooleanQualifier.falseQualifier
    }
    #endif
    guard kglobalID.keyCount != 0 else {
      globalZeeQLLogger.warn("globalID w/o keys:", globalID)
      assertionFailure("globalID w/o keys: \(globalID)")
      return BooleanQualifier.falseQualifier
    }
    guard let pkeys = primaryKeyAttributeNames,
          pkeys.count == kglobalID.keyCount
     else { return BooleanQualifier.falseQualifier }
    
    if kglobalID.keyCount == 1 {
      return KeyValueQualifier(pkeys[0], .equalTo, kglobalID[0])
    }
    
    var qualifiers = [ Qualifier ]()
    qualifiers.reserveCapacity(kglobalID.keyCount)
    for i in 0..<kglobalID.keyCount {
      qualifiers.append(KeyValueQualifier(pkeys[i], .equalTo, kglobalID[i]))
    }
    return CompoundQualifier(qualifiers: qualifiers, op: .And)
  }

  
  // MARK: - Attributes & Relationships
  
  @inlinable
  subscript(attribute n: String) -> Attribute? {
    for attr in attributes { if attr.name == n { return attr } }
    return nil
  }
  @inlinable
  subscript(columnName n: String) -> Attribute? {
    for attr in attributes { if attr.columnName == n { return attr } }
    return nil
  }
  
  @inlinable
  subscript(relationship n: String) -> Relationship? {
    for rel in relationships { if rel.name == n { return rel } }
    return nil
  }
  
  @inlinable
  func attributesWithNames(_ names: [ String ]) -> [ Attribute ] {
    guard !names.isEmpty else { return [] }
    var attributes = [ Attribute ]()
    for name in names {
      if let a = self[attribute: name] {
        attributes.append(a)
      }
    }
    return attributes
  }
  
  @inlinable
  func keyForAttributeWith(name: String) -> Key {
    guard let attr = self[attribute: name] else { return StringKey(name) }
    return AttributeKey(attr, entity: self)
  }
  @inlinable
  func keyForAttributeWith(name: String, requireLookup: Bool) -> Key? {
    guard let attr = self[attribute: name]
     else { return requireLookup ? nil : StringKey(name) }
    return AttributeKey(attr, entity: self)
  }
  
  /**
   * Iterates over the relationships and calls
   * ``Relationship/connectRelationships(in:entity:)`` on them.
   *
   * - Parameters:
   *   - model: The model to resolve the entities.
   */
  @inlinable
  func connectRelationships(in model : Model) {
    for relship in relationships {
      relship.connectRelationships(in: model, entity: self)
    }
  }
  /**
   * Iterates over the relationships and calls
   * ``Relationship/disconnectRelationships()`` on them.
   */
  @inlinable
  func disconnectRelationships() {
    for relship in relationships {
      relship.disconnectRelationships()
    }
  }
  
  /**
   * Returns the names of the attributes and relationships of the entity.
   */
  @inlinable
  var classPropertyNames : [ String ]? {
    if attributes.isEmpty && relationships.isEmpty { return nil }
    var names = [ String ]()
    names.reserveCapacity(attributes.count + relationships.count)
    for attr in attributes    { names.append(attr.name) }
    for rs   in relationships { names.append(rs.name)   }
    return names
  }
  @inlinable
  var attributesUsedForLocking : [ Attribute ]? { return nil }

  
  // MARK: - Fetch Specifications
  
  @inlinable
  var restrictingQualifier: Qualifier? {
    assert(!(self is ModelEntity || self is CodeEntityBase))
    return nil
  }
  @inlinable
  subscript(fetchSpecification n: String) -> FetchSpecification? {
    assert(!(self is ModelEntity || self is CodeEntityBase))
    return nil
  }
  @inlinable
  subscript(adaptorOperation   n: String) -> AdaptorOperation?   { return nil }

  
  // MARK: - Description
  
  func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    if let cn = externalName {
      if let sn = schemaName { ms += "[\(sn).\(cn)]" }
      else                   { ms += "[\(cn)]"       }
    }
    
    if      let ot = objectType { ms += " \(ot)"   }
    else if let cn = className  { ms += " '\(cn)'" }
    
    if isReadOnly { ms += " r/o" }
    
    if let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty {
      if pkeys.count == 1 {
        ms += " pkey=" + pkeys[0]
      }
      else {
        ms += " pkeys="
        ms += pkeys.joined(separator: ",")
      }
    }
    
    ms += " #attrs=\(attributes.count)"
    
    if relationships.count > 0 { ms += " #rel=\(relationships.count)" }
    
    if let rq = restrictingQualifier {
      ms += " restrict=\(rq)"
    }

    // TODO: fetchspecs
  }
}

public extension Entity { // keypath attribute lookup
  
  @inlinable
  subscript(keyPath path: String) -> Attribute? {
    let parts = path.split(separator: ".")
    let count = parts.count
    guard count > 1 else { return self[attribute: path] }
    
    var cursor : Entity? = self
    for i in 0..<(count - 1) {
      let part = String(parts[i])
      guard let relship = cursor?[relationship: part] else { return nil }
      guard let entity  = relship.destinationEntity   else { return nil }
      cursor = entity
    }
    
    return cursor?[attribute: String(parts[count - 1])]
  }
}

public extension Entity { // primary keys
  
  /**
   * Extracts the primary key values contained in the given row (usually a 
   * Dictionary).
   * 
   * - parameter row: a row
   * - returns: a Dictionary containing the keys/values of the primary keys
   */
  func primaryKeyForRow(_ row: Any?) -> Snapshot? {
    /* we do KVC on the row, so it can be any kind of object */
    guard let row = row else {
      globalZeeQLLogger.warn("got no row to calculate primary key!")
      return nil
    }
    guard let pkeysNames = primaryKeyAttributeNames else {
      globalZeeQLLogger.warn("got no pkeys to calculate pkey:", self)
      return nil
    }
    
    let pkey = KeyValueCoding.values(forKeys: pkeysNames, inObject: row)
    guard !pkey.isEmpty else {
      globalZeeQLLogger.trace("could not calculate primary key:", pkeysNames,
                              "from row:", row)
      return nil
    }
    
    return pkey
  }
  
  /**
   * Extracts the primary key values contained in the given object and returns
   * a qualifier to match those.
   *
   * - parameter row: a database object (or snapshot)
   * - returns: a `Qualifier` matching the keys/values of the primary keys
   */
  func qualifierForPrimaryKey(_ row: Any?) -> Qualifier? {
    guard let row = row else { return nil }
    /* we do KVC on the row, so it can be any kind of object */
    guard let pkey = primaryKeyForRow(row) else { return nil }
    return qualifierToMatchAllValues(pkey)
  }
  
}

public extension Entity {
  
  @inlinable
  func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Entity else { return false }
    return other.isEqual(to: self)
  }
  
  @inlinable
  func isEqual(to other: Self) -> Bool {
    if other === self { return true  }
    guard name                  == other.name         else { return false }
    guard externalName          == other.externalName else { return false }
    guard className             == other.className    else { return false }
    guard objectType            == other.objectType   else { return false }
    guard schemaName            == other.schemaName   else { return false }
    guard isReadOnly            == other.isReadOnly   else { return false }
    guard isPattern             == other.isPattern    else { return false }

    guard attributes.count    == other.attributes.count    else { return false }
    guard relationships.count == other.relationships.count else { return false }
    guard attributesUsedForLocking?.count ==
            other.attributesUsedForLocking?.count else { return false }

    guard shouldRefetchOnInsert ==  other.shouldRefetchOnInsert else {
      return false
    }
    guard primaryKeyAttributeNames == other.primaryKeyAttributeNames else {
      return false
    }
    guard classPropertyNames == other.classPropertyNames else {
      return false
    }
    guard eq(restrictingQualifier, other.restrictingQualifier) else {
      return false
    }
    
    for attr in attributes {
      guard let other = other[attribute: attr.name] else { return false }
      guard attr.isEqual(to: other)                 else { return false }
    }
    if let v  = attributesUsedForLocking,
       let ov = other.attributesUsedForLocking
    {
      let mn = Set(v .lazy.map { $0.name })
      let on = Set(ov.lazy.map { $0.name })
      guard mn == on else { return false }
    }
    for rs in relationships {
      guard let other = other[relationship: rs.name] else { return false }
      guard rs.isEqual(to: other)                    else { return false }
    }

    return true
  }
  
  @inlinable
  static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}


/**
 * An Entity description which stores the info as variables.
 *
 * Suitable for use with models loaded from XML, or models fetched from a
 * database.
 */
open class ModelEntity : Entity, Equatable {
  
  /*
   * When adding ivars remember to clone them in:
   *   cloneForExternalName()
   *   resolveEntityPatternWithModel()
   */
  public final var name                     : String
  public final var externalName             : String?
  public final var schemaName               : String?
  public final var className                : String? // TBD: Hm.
  public final var dataSourceClassName      : String?
  public final var isReadOnly               = false
  public final var attributes               = [ Attribute    ]()
  public final var relationships            = [ Relationship ]()
  public final var primaryKeyAttributeNames : [ String    ]? = nil
  
  public final var codeGenerationType       : String?
  public final var userData                 = [ String : Any ]()
  
  /// A persistent ID used to track renaming when doing model-to-model
  /// migrations.
  public final var elementID                : String?
  
  /**
   * Returns the attributes which are used for optimistic locking. Those are
   * checked for changes when an UPDATE is attempted in the database. For
   * example in OGo we only need the 'objectVersion' as a change marker.
   */
  public final var attributesUsedForLocking : [ Attribute ]? = nil
  
  public final var restrictingQualifier     : Qualifier?
  public final var fetchSpecifications      = [ String : FetchSpecification ]()
  public final var adaptorOperations        = [ String : AdaptorOperation   ]()

  /**
   * Returns the names of class property attributes and relationships. Those are
   * attributes which are exposed as a part of the database object.
   *
   * The class properties are a subset of the attributes and relship arrays. Eg
   * in an application you would not want to expose database specific details
   * like primary and foreign keys as class properties.
   */
  public final var classPropertyNames : [ String ]? {
    set {
      _classPropertyNames = newValue
    }
    get {
      if let cpn = _classPropertyNames { return cpn }
      if attributes.isEmpty && relationships.isEmpty { return nil }
      
      // Note: threading, cannot push into _classPropertyNames
      
      var names = [ String ]()
      names.reserveCapacity(attributes.count + relationships.count)
      
      for attr in attributes    { names.append(attr.name) }
      for rs   in relationships { names.append(rs.name)   }
      return names
    }
  }
  final var _classPropertyNames : [ String ]?
  
  /* patterns */
  public final var isExternalNamePattern = false
  
  @inlinable
  public init(name: String, table: String? = nil, isPattern: Bool = false)
  {
    self.name                  = name
    self.externalName          = table
    self.isExternalNamePattern = isPattern
  }
  
  public init(entity: Entity, deep: Bool = false) {
    self.name                     = entity.name
    self.externalName             = entity.externalName
    self.schemaName               = entity.schemaName
    self.className                = entity.className
    self.isReadOnly               = entity.isReadOnly
    self.primaryKeyAttributeNames = entity.primaryKeyAttributeNames
    
    // TBD: does this need a copy?
    self.restrictingQualifier     = entity.restrictingQualifier
    
    if deep {
      var nameToNewAttribute = [ String : Attribute ]()
      attributes.reserveCapacity(entity.attributes.count)
      for attr in entity.attributes {
        let newAttr = ModelAttribute(attribute: attr)
        nameToNewAttribute[attr.name] = newAttr
        attributes.append(newAttr)
      }
      
      if let lockAttrs = entity.attributesUsedForLocking {
        attributesUsedForLocking = [ Attribute ]()
        attributesUsedForLocking?.reserveCapacity(lockAttrs.count)
        for attr in lockAttrs {
          attributesUsedForLocking?.append(nameToNewAttribute[attr.name]!)
        }
      }
    }
    else {
      self.attributes               = entity.attributes
      self.attributesUsedForLocking = entity.attributesUsedForLocking
    }
    
    if let me = entity as? ModelEntity {
      self.codeGenerationType     = me.codeGenerationType
      self.userData               = me.userData
      self.elementID              = me.elementID
      
      self.isExternalNamePattern  = me.isExternalNamePattern
      self.dataSourceClassName    = me.dataSourceClassName
      self._classPropertyNames    = me._classPropertyNames
      
      if deep {
        for (key, value) in me.fetchSpecifications {
          fetchSpecifications[key] =
            ModelFetchSpecification(fetchSpecification: value)
        }
        
        // TODO: deep support
        self.adaptorOperations    = me.adaptorOperations
      }
      else {
        // TBD: those may refer to the entity?
        self.fetchSpecifications  = me.fetchSpecifications
        self.adaptorOperations    = me.adaptorOperations
      }
    }
    
    // Relationships refer to their entity, hence we always need to copy
    // them.
    self.relationships = entity.relationships.map {
      ModelRelationship(relationship: $0, newEntity: self, disconnect: true)
    }
  }
  
  @inlinable
  public subscript(fetchSpecification n: String) -> FetchSpecification? {
    return fetchSpecifications[n]
  }

  @inlinable
  public subscript(adaptorOperation n: String) -> AdaptorOperation? {
    return adaptorOperations[n]
  }

  @inlinable
  public var isPattern : Bool {
    return isExternalNamePattern
        || attributes.contains(where: { $0.isPattern })
        || relationships.contains(where: { $0.isPattern })
  }
  
  // MARK: - Equatable
  
  @inlinable
  public static func ==(lhs: ModelEntity, rhs: ModelEntity) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}

/// Commonly used within the framework, but should not be public API
extension Entity {

  @inlinable
  var externalNameOrName : String { return externalName ?? name }
}
