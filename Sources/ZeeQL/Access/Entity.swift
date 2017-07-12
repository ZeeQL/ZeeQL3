//
//  Entity.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
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
public protocol Entity: class, SmartDescription {

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
  
  var externalName          : String? { return nil   }
  var schemaName            : String? { return nil   }

  var isReadOnly            : Bool    { return false }
  var shouldRefetchOnInsert : Bool    { return true  }

  var className  : String? {
    if let t = objectType { return "\(t)" }
    return nil
  }
  var objectType : DatabaseObject.Type? { return nil }

  var primaryKeyAttributeNames : [ String ]? {
    return lookupPrimaryKeyAttributeNames()
  }
  
  func lookupPrimaryKeyAttributeNames() -> [ String ]? {
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
  
  func globalIDForRow(_ row: AdaptorRecord?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map { row[$0] }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }
  func globalIDForRow(_ row: AdaptorRow?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map { row[$0] ?? nil }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }
  func globalIDForRow(_ row: Any?) -> GlobalID? {
    guard let row = row else { return nil }
    guard let pkeys = primaryKeyAttributeNames, !pkeys.isEmpty
     else { return nil }
    
    let pkeyValues = pkeys.map {
      KeyValueCoding.value(forKey: $0, inObject: row)
    }
    return KeyGlobalID.make(entityName: name, values: pkeyValues)
  }

  
  // MARK: - Attributes & Relationships
  
  subscript(attribute n: String) -> Attribute? {
    for attr in attributes { if attr.name == n { return attr } }
    return nil
  }
  subscript(columnName n: String) -> Attribute? {
    for attr in attributes { if attr.columnName == n { return attr } }
    return nil
  }
  
  subscript(relationship n: String) -> Relationship? {
    for rel in relationships { if rel.name == n { return rel } }
    return nil
  }
  
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
  
  func keyForAttributeWith(name: String) -> Key {
    guard let attr = self[attribute: name] else { return StringKey(name) }
    return AttributeKey(attr, entity: self)
  }
  func keyForAttributeWith(name: String, requireLookup: Bool) -> Key? {
    guard let attr = self[attribute: name]
     else { return requireLookup ? nil : StringKey(name) }
    return AttributeKey(attr, entity: self)
  }
  
  func connectRelationships(in model : Model) {
    for relship in relationships {
      relship.connectRelationships(in: model, entity: self)
    }
  }
  func disconnectRelationships() {
    for relship in relationships {
      relship.disconnectRelationships()
    }
  }
  
  var classPropertyNames : [ String ]? {
    if attributes.isEmpty && relationships.isEmpty { return nil }
    var names = [ String ]()
    names.reserveCapacity(attributes.count + relationships.count)
    for attr in attributes    { names.append(attr.name) }
    for rs   in relationships { names.append(rs.name)   }
    return names
  }
  var attributesUsedForLocking : [ Attribute ]? { return nil }

  
  // MARK: - Fetch Specifications
  
  var restrictingQualifier: Qualifier? { return nil }
  subscript(fetchSpecification n: String) -> FetchSpecification? { return nil }
  subscript(adaptorOperation   n: String) -> AdaptorOperation?   { return nil }

  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    if let cn = externalName {
      if let sn = schemaName {
        ms += "[\(sn).\(cn)]"
      }
      else {
        ms += "[\(cn)]"
      }
    }
    
    if let ot = objectType {
      ms += " \(ot)"
    }
    else if let cn = className {
      ms += " '\(cn)'"
    }
    
    if isReadOnly {
      ms += " r/o"
    }
    
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
    
    if relationships.count > 0 {
      ms += " #rel=\(relationships.count)"
    }
    
    // TODO: restrictingQualifier, fetchspecs
  }
}

public extension Entity { // keypath attribute lookup
  
  subscript(keyPath path: String) -> Attribute? {
    let parts = path.components(separatedBy: ".")
    let count = parts.count
    guard count > 1 else { return self[attribute: path] }
    
    var cursor : Entity? = self
    for i in 0..<(count - 1) {
      let part = parts[i]
      guard let relship = cursor?[relationship: part] else { return nil }
      guard let entity  = relship.destinationEntity   else { return nil }
      cursor = entity
    }
    
    return cursor?[attribute: parts[count - 1]]
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
  public func primaryKeyForRow(_ row: Any?) -> Snapshot? {
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
  public func qualifierForPrimaryKey(_ row: Any?) -> Qualifier? {
    guard let row = row else { return nil }
    /* we do KVC on the row, so it can be any kind of object */
    guard let pkey = primaryKeyForRow(row) else { return nil }
    return qualifierToMatchAllValues(pkey)
  }
  
}


/**
 * An Entity description which stores the info as variables.
 *
 * Suitable for use with models loaded from XML, or models fetched from a
 * database.
 */
open class ModelEntity : Entity {
  
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
  public final var isExternalNamePattern    = false
  
  public init(name: String, table: String? = nil) {
    self.name         = name
    self.externalName = table
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
  
  public subscript(fetchSpecification n: String) -> FetchSpecification? {
    return fetchSpecifications[n]
  }

  public subscript(adaptorOperation n: String) -> AdaptorOperation? {
    return adaptorOperations[n]
  }

  public var isPattern : Bool {
    if isExternalNamePattern { return true }
    for attribute in attributes {
      if attribute.isPattern { return true }
    }
    for relship in relationships {
      if relship.isPattern { return true }
    }
    return false
  }
}

/// Commonly used within the framework, but should not be public API
extension Entity {
  var externalNameOrName : String { return externalName ?? name }
}
