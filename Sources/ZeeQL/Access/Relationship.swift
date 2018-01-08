//
//  Relationship.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//


/**
 * A relationship connects two `Entity`'s using `Join`'s. It is one-way,
 * so you need to have separate `Relationship` objects for each direction.
 */
public protocol Relationship : Property, ExpressionEvaluation,
                               SmartDescription
{

  var  name              : String          { get }
  var  entity            : Entity          { get }
  var  destinationEntity : Entity?         { get }

  var  isToMany          : Bool            { get }
  var  minCount          : Int?            { get }
  var  maxCount          : Int?            { get }

  var  joins             : [ Join ]        { get }
  var  joinSemantic      : Join.Semantic   { get }
  
  func connectRelationships(in model : Model, entity: Entity)
  func disconnectRelationships()
  var  isPattern         : Bool            { get }
  
  var  updateRule        : ConstraintRule? { get }
  var  deleteRule        : ConstraintRule? { get }
  var  ownsDestination   : Bool            { get }
  
  var constraintName     : String?         { get }
  
  // TODO: var isMandatory : Bool (check whether target Attribute `allowsNull`)
}

/**
 * Specifies what happens with the target if the source object of a
 * relationship gets deleted.
 */
public enum ConstraintRule {
  case nullify      // SET NULL
  case cascade
  case deny         // RESTRICT
  case noAction     // NO ACTION
  case applyDefault // SET DEFAULT
  
  public var sqlString : String { // TBD: name of property
    switch self {
      case .nullify:      return "SET NULL"
      case .cascade:      return "CASCADE"
      case .deny:         return "RESTRICT"
      case .noAction:     return "NO ACTION"
      case .applyDefault: return "SET DEFAULT"
    }
  }
}

fileprivate var log : ZeeQLLogger { return globalZeeQLLogger }

public extension Relationship { // default imp
  
  var joinSemantic   : Join.Semantic   { return .innerJoin }
  var deleteRule     : ConstraintRule? { return nil        }
  var updateRule     : ConstraintRule? { return nil        }
  var constraintName : String?         { return nil        }

  var minCount       : Int? { return isToMany ? nil : (isMandatory ? 0 : 1) }
  var maxCount       : Int? { return isToMany ? nil : 1 }
  
  var isMandatory : Bool {
    if isToMany { return (minCount ?? 0) > 0 }
    
    // 1:1: figure out whether the relationship has one required join
    for join in joins {
      if let source = join.source {
        if let nullable = source.allowsNull, !nullable { return true }
      }
      else if let sourceName = join.sourceName {
        if let source = entity[attribute: sourceName] {
          if let nullable = source.allowsNull, !nullable { return true }
        }
        else {
          log.error("testing isMandatory on relship w/o proper joins:",
                    self, join)
        }
      }
      else {
        log.error("testing isMandatory on relship w/o proper joins:", self)
        assert(join.sourceName != nil, "missing source in join")
      }
    }
    return false
  }
  
  // MARK: - ExpressionEvaluation
  
  func valueFor(object: Any?) -> Any? {
    return KeyValueCoding.value(forKeyPath: name, inObject: object)
  }

  func connectRelationships(in model : Model, entity: Entity) {}
  func disconnectRelationships() {}

  var  ownsDestination : Bool {
    guard let deleteRule = deleteRule else { return false }
    
    // TBD: I think this is right, if a delete cascades, we own the target
    if case .cascade = deleteRule { return true }
    return false
  }
}

public extension Relationship { // extra methods

  /**
   * Returns true if this is a flattened relationship. A flattened relationship
   * is a shortcut for a longer path. For example to retrieve the addresses of
   * the companies assigned to a person you could use:
   *
   *   employments.company.addresses
   *
   * Or you could create a 'flattened' relationship 'companyAddresses' which
   * contains this path. The path of the real relationship can be retrieved
   * using the relationshipPath() method.
   */
  var isFlattened : Bool { return relationshipPath != nil }
  
  var isCompound  : Bool { return joins.count > 1 }

  
  /**
   * Returns the Relationship objects for each component of the
   * relationshipPath() of a flattened Relationship. Eg:
   *
   *     employments.company.addresses
   *
   * could return three Relationship objects:
   *
   *     'employments', source = Persons,     dest = Employments
   *     'company',     source = Employments, dest = Companies
   *     'addresses',   source = Companies,   dest = Addresses
   * 
   * The method returns nil if this is not a flattened relationship.
   */
  var componentRelationships : [ Relationship ]? {
    guard let relationshipPath = relationshipPath else { return nil }
    
    var relentity : Entity? = entity

    var relships = [ Relationship ]()
    let path = relationshipPath.components(separatedBy: ".")
    relships.reserveCapacity(path.count)

    for p in path {
      guard let rel = relentity?[relationship: p] else {
        return nil // TODO: log
      }
      
      assert(!rel.isFlattened, "Not implemented")
        // TODO: pathes containing flattened relships
      
      relentity = rel.destinationEntity
    }
    
    return relships
  }

  /**
   * Makes the Relationship check whether any of its joins reference the
   * given property.
   * A property is an Attribute or Relationship object.
   */
  func references(property: Property) -> Bool {
    for join in joins {
      if join.references(property: property) { return true }
    }
    
    if relationshipPath != nil {
      if let props = componentRelationships {
        for r in props {
          if r === property { return true }
          // TBD: do we need to call referencesProperty on the relationships?
        }
      }
    }
    
    return false
  }
  
  
  /**
   * Checks whether the Relationship got resolved (whether the Entity of
   * the destination entity was looked up).
   */
  var isConnected : Bool {
    if destinationEntity == nil { return false }
    for join in joins {
      if !join.isConnected { return false }
    }
    return true
  }
  
  
  /**
   * *Locates* an inverse relationship in the destination entity.
   *
   * Note: this does *not* create one.
   * 
   * Example: n:1
   *   person  ( person_id, company_id )
   *   company ( company_id )
   * Person:
   *   toCompany [toOne] ( SRC.company_id = TAR.company_id )
   * Company:
   *   toPerson [toMany] ( SRC.company_id = TAR.company_id )
   */
  var inverseRelationship : Relationship? {
    // TBD: implement me
    // TBD: consider N:M relationships
    // find a relationship in the target which joins the same columns
    guard !joins.isEmpty else { return nil }
    guard joins.count < 2 else {
      assert(joins.count < 2, "not supported: inv-relship with multiple joins")
      return nil
    }
    
    guard let dest = destinationEntity else { return nil }
    
    for rel in dest.relationships {
      guard entity === rel.destinationEntity else { continue }
        // other entity, does not point back
      
      guard rel.joins.count == joins.count else { continue }
        // join array sizes do not match
      
      // TBD: we only support one join for now ...
      let myJoin = self.joins[0]
      let enemy  = rel.joins[0]
      
      // TBD: equality might not be correct since joins can be directed
      //      (relevant for LEFT/RIGHT joins I guess)
      if myJoin == enemy || myJoin.isReciprocalTo(join: enemy) {
        return rel
      }
    }
    
    return nil
  }
  
}

public extension Relationship {

  func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    ms += isToMany ? "[1:n]" : "[1:1]"
    ms += " \(entity.name)"
    
    if let to = destinationEntity { ms += " to=\(to.name)" }
    
    if !joins.isEmpty {
      if joinSemantic != .innerJoin { ms += " \(joinSemantic)" }
      ms += " "
      for join in joins {
        ms += join.shortDescription
      }
    }
    else {
      ms += " no-joins?"
    }

    if isToMany {
      if let v = minCount { ms += " min=\(v)" }
      if let v = maxCount { ms += " max=\(v)" }
    }
    else {
      if isMandatory { ms += " mandatory" }
    }
  }
}


/**
 * A dynamic object representing a relationship.
 *
 * E.g. such are fetched during SQL database schema reflection.
 * The opposite is a relationship defined in code.
 *
 * CAREFUL: To avoid cycles relationships do not retain the entity!
 */
open class ModelRelationship : Relationship {

  open var log : ZeeQLLogger = globalZeeQLLogger
  
  public final var name                  : String
  public final var constraintName        : String?
  open unowned var entity                : Entity  // CAREFUL: Unowned!
  open    weak var destinationEntity     : Entity?
  public final var destinationEntityName : String?
  open         var joins                 = [ Join ]()
  public final var joinSemantic          = Join.Semantic.innerJoin
  open         var isToMany              = false
  public final var relationshipPath      : String?
  public final var deleteRule            : ConstraintRule?
  
  public final var minCount              : Int? {
    set { _minCount = newValue }
    get { return _minCount ?? (isToMany ? nil : (isMandatory ? 0 : 1)) }
  }
  public final var maxCount              : Int? {
    set { _maxCount = newValue }
    get { return _maxCount ?? (isToMany ? nil : 1) }
  }
  final var _minCount                    : Int?
  final var _maxCount                    : Int?

  public final var userData              = [ String : Any ]()

  public init(name   : String, isToMany    : Bool    = false,
              source : Entity, destination : Entity? = nil)
  {
    self.name                  = name
    self.isToMany              = isToMany
    self.entity                = source
    self.destinationEntity     = destination
    self.destinationEntityName = destination?.name
  }
  
  public init(relationship rs: Relationship, newEntity: Entity? = nil,
              disconnect: Bool = false)
  {
    name              = rs.name
    constraintName    = rs.constraintName
    joinSemantic      = rs.joinSemantic
    isToMany          = rs.isToMany
    deleteRule        = rs.deleteRule
    relationshipPath  = rs.relationshipPath
    entity            = newEntity ?? rs.entity
    
    if let mrs = rs as? ModelRelationship {
      minCount = mrs._minCount
      maxCount = mrs._maxCount
      userData = mrs.userData
      
      _ownsDestination = mrs._ownsDestination
      
      if disconnect {
        destinationEntityName = mrs.destinationEntityName
                                ?? mrs.destinationEntity?.name
      }
      else {
        destinationEntity     = mrs.destinationEntity
        destinationEntityName = mrs.destinationEntityName
      }
    }
    else {
      minCount        = rs.minCount
      maxCount        = rs.maxCount
      ownsDestination = rs.ownsDestination
      
      if disconnect {
        destinationEntityName = rs.destinationEntity?.name
      }
      else {
        destinationEntity     = rs.destinationEntity
        destinationEntityName = rs.destinationEntity?.name
      }
    }
    
    if disconnect || (newEntity != nil && newEntity !== rs.entity) {
      joins = rs.joins.map { Join(join: $0, disconnect: true) }
    }
    else {
      joins = rs.joins
    }
  }
  
  public var isPattern : Bool { return false } // not yet supported
  
  public func connectRelationships(in model : Model, entity: Entity) {
    guard !isConnected else {
      return
    }
    
    self.entity = entity
    
    guard let destName = destinationEntityName else {
      log.warn("relationship has no target name:", self)
      return
    }
    
    destinationEntity = model[entity: destName]
    guard let target = destinationEntity else {
      log.warn("could not resolve destination entity", destName,
               "of", self, "in", model)
      return
    }
    
    // log.log("CONNECTED:", self)
    
    var newJoins = [ Join ]() // value objects
    newJoins.reserveCapacity(joins.count)
    for join in joins {
      var joinCopy = join
      joinCopy.connectToEntities(from: entity, to: target)
      newJoins.append(joinCopy)
    }
    joins = newJoins
  }
  public func disconnectRelationships() {
    destinationEntity = nil
    
    var newJoins = [ Join ]() // value objects
    newJoins.reserveCapacity(joins.count)
    for join in joins {
      var joinCopy = join
      joinCopy.disconnect()
      newJoins.append(joinCopy)
    }
    joins = newJoins
  }
  
  var _ownsDestination : Bool? = nil
  public var ownsDestination : Bool {
    set {
      _ownsDestination = newValue
    }
    get {
      if let v = _ownsDestination { return v }

      // if we have no explicit value, check whether we have a delete-rule
      // hinting at the ownership.
      
      // copy of the default-imp
      guard let deleteRule = deleteRule else { return false }
      if case .cascade = deleteRule { return true }
      return false
    }
  }
  
  
  // MARK: - Own Description

  public func appendToDescription(_ ms: inout String) {
    if isPattern { ms += " pattern" }
    
    ms += " \(name)"
    ms += isToMany ? "[1:n]" : "[1:1]"
    ms += " \(entity.name)"
    
    if let to = destinationEntity {
      ms += " to=\(to.name)"
    }
    else if let ton = destinationEntityName {
      ms += " to=\(ton)!"
    }
    else {
      ms += " to=?"
    }
    
    if !joins.isEmpty {
      if joinSemantic != .innerJoin { ms += " \(joinSemantic)" }
      ms += " "
      for join in joins {
        ms += join.shortDescription
      }
    }
    else {
      ms += " no-joins?"
    }
    
    if isToMany {
      if let v = minCount { ms += " min=\(v)" }
      if let v = maxCount { ms += " max=\(v)" }
    }
    else {
      if isMandatory { ms += " mandatory" }
    }
    
    if !userData.isEmpty {
      ms += " ud=["
      for ( key, value ) in userData {
        ms += " "
        ms += key
        ms += ": "
        ms += String(describing: value)
      }
      ms += "]"
    }
  }
}
