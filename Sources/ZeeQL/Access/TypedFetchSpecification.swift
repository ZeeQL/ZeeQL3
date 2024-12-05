//
//  TypedFetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

// TODO: this is not done yet
// This is used for the fetch spec builder, like `OGoPersons.where....`

/**
 * A ``DatabaseFetchSpecification`` that is used when building fetch
 * specifications dynamically.
 *
 * Example:
 * ```swift
 * let fs = OGoPerson
 *            .where(OGoPerson.e.login.like("*he*"))
 *            .limit(4)
 *            .prefetch(OGoPerson.e.addresses)
 *            .order(by: OGoPerson.e.login)
 * ```
 */
public struct TypedFetchSpecification<Object: DatabaseObject>
              : DatabaseFetchSpecification
{
  // FIXME: Name, should be called "DynamicFetchSpecification" or something
  
  public var _entity             : Entity? = nil
  public var _entityName         : String?

  public var entity              : Entity? {
    if let entity = _entity { return entity }
    if let to = Object.self as? EntityType.Type { return to.entity }
    return nil
  }
  
  public var entityName          : String? {
    if let e = entity      { return e.name }
    if let n = _entityName { return n }
    return nil
  }
  
  public var fetchAttributeNames = [ String ]()
  public var qualifier           : Qualifier?
  public var sortOrderings       = [ SortOrdering ]()
  public var fetchLimit          : Int?
  public var fetchOffset         : Int?
  public var hints               = [ String : Any ]()
  
  public var usesDistinct        = false
  public var locksObjects        = false
  public var deep                = false
  public var fetchesRawRows      = false
  public var fetchesReadOnly     = false
  public var requiresAllQualifierBindingVariables = false
  public var prefetchingRelationshipKeyPathes = [ String ]()

  @inlinable
  public init(entityName    : String?          = nil,
              qualifier     : Qualifier?       = nil,
              sortOrderings : [ SortOrdering ] = [],
              limit         : Int?             = nil,
              prefetch      : [ String ]       = [],
              requiresAllQualifierBindingVariables: Bool = false)
  {
    self._entityName   = entityName
    self.qualifier     = qualifier
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
    self.prefetchingRelationshipKeyPathes = prefetch
    self.requiresAllQualifierBindingVariables =
      requiresAllQualifierBindingVariables
  }
  
  @inlinable
  public init(entity        : Entity,
              qualifier     : Qualifier?       = nil,
              sortOrderings : [ SortOrdering ] = [],
              limit         : Int?             = nil,
              prefetch      : [ String ]       = [],
              requiresAllQualifierBindingVariables: Bool = false)
  {
    self._entity       = entity
    self.qualifier     = qualifier
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
    self.prefetchingRelationshipKeyPathes = prefetch
    self.requiresAllQualifierBindingVariables =
      requiresAllQualifierBindingVariables
  }
  
  /// Initialize w/ a qualifier string.
  public init(entity        : Entity,
              _ q           : String,
              sortOrderings : [ SortOrdering ] = [],
              limit         : Int?             = nil,
              prefetch      : [ String ]       = [])
  {
    self._entity       = entity
    self.qualifier     = qualifierWith(format: q)
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
    self.prefetchingRelationshipKeyPathes = prefetch
  }
  
}
