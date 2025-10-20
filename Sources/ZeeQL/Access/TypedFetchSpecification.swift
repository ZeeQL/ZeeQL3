//
//  TypedFetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
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
  
  public var fetchAttributeNames                  = [ String ]()
  public var qualifier                            : Qualifier?
  public var sortOrderings                        = [ SortOrdering ]()
  public var fetchLimit                           : Int?
  public var fetchOffset                          : Int?
  public var hints                                = [ String : Any ]()
  
  public var usesDistinct                         = false
  public var locksObjects                         = false
  public var deep                                 = false
  public var fetchesRawRows                       = false
  public var fetchesReadOnly                      = false
  public var refreshesRefetchedObjects            = false
  public var requiresAllQualifierBindingVariables = false
  public var prefetchingRelationshipKeyPathes     = [ String ]()

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

extension TypedFetchSpecification: Equatable {
  
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    guard lhs.usesDistinct        == rhs.usesDistinct,
          lhs.locksObjects        == rhs.locksObjects,
          lhs.deep                == rhs.deep,
          lhs.requiresAllQualifierBindingVariables ==
            rhs.requiresAllQualifierBindingVariables,
          lhs.prefetchingRelationshipKeyPathes ==
            rhs.prefetchingRelationshipKeyPathes,
          lhs.fetchesRawRows      == rhs.fetchesRawRows,
          lhs.fetchesReadOnly     == rhs.fetchesReadOnly,
          lhs.fetchAttributeNames == rhs.fetchAttributeNames,
          lhs.sortOrderings       == rhs.sortOrderings,
          lhs.fetchLimit          == rhs.fetchLimit,
          lhs.fetchOffset         == rhs.fetchOffset else { return false }

    if let lhs = lhs.qualifier { return lhs.isEqual(to: rhs.qualifier) }
    else if rhs.qualifier != nil { return false }

    guard lhs.entityName == rhs.entityName else { return false }
    if let lhs = lhs.entity { return lhs.isEqual(to: rhs.entity) }
    else if rhs.entity != nil { return false }
    
    if lhs.hints.count != rhs.hints.count { return false }
    return eq(lhs.hints, rhs.hints)
  }
}
extension TypedFetchSpecification: EquatableType {
  
  public func isEqual(to object: Any?) -> Bool {
    // TBD: Would we want to allow comparison to ModelFS and such? That *might*
    //      make sense?
    guard let typed = object as? Self else { return false }
    return self == typed
  }
}

extension TypedFetchSpecification {
  
  /**
   * Return a copy of the ``TypedFetchSpecification`` which has the qualifier
   * bindings resolved against the given argument. Plus all xyzBindPattern
   * hints.
   * If the fetch spec has no bindings, the exisiting object is returned.
   *
   * The syntax for bindings in string qualifiers is `$binding` (e.g.
   * `lastname = $lastname`).
   *
   * The syntax for bind-pattern hints is `%(binding)s` (note the trailing
   * format specifier!).
   */
  @inlinable
  public func resolvingBindings(_ bindings: Any?) throws -> Self {
    let newHints      = resolveHintBindPatterns(with: bindings)
    let hasUnresolved = qualifier?.hasUnresolvedBindings ?? false
    if newHints == nil && !hasUnresolved { return self }
    
    var boundFS = self
    if let newHints { boundFS.hints = newHints }
    if hasUnresolved, let q = boundFS.qualifier {
      boundFS.qualifier =
        try q.qualifierWith(bindings: bindings,
                            requiresAll: requiresAllQualifierBindingVariables)
    }
    return boundFS
  }

}
