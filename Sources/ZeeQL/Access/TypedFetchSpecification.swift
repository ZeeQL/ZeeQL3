//
//  TypedFetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

// TODO: this is not done yet

public struct TypedFetchSpecification<Object: DatabaseObject>
              : FetchSpecification
{
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
  
  public var fetchAttributeNames : [ String ]?
  public var qualifier           : Qualifier?
  public var sortOrderings       : [ SortOrdering ]?
  public var fetchLimit          : Int?
  public var fetchOffset         : Int?
  public var hints               = [ String : Any ]()
  
  public var usesDistinct        = false
  public var locksObjects        = false
  public var deep                = false
  public var fetchesRawRows      = false
  public var fetchesReadOnly     = false
  public var requiresAllQualifierBindingVariables = false
  public var prefetchingRelationshipKeyPathes : [ String ]?

  public init(entityName    : String?           = nil,
              qualifier     : Qualifier?        = nil,
              sortOrderings : [ SortOrdering ]? = nil,
              limit         : Int?              = nil)
  {
    self._entityName   = entityName
    self.qualifier     = qualifier
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
  }
  public init(entity        : Entity,
              qualifier     : Qualifier?        = nil,
              sortOrderings : [ SortOrdering ]? = nil,
              limit         : Int?              = nil)
  {
    self._entity       = entity
    self.qualifier     = qualifier
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
  }
  
  public init(entity        : Entity,
              _ q           : String,
              sortOrderings : [ SortOrdering ]? = nil,
              limit         : Int?              = nil,
              prefetch      : [ String ]?       = nil)
  {
    self._entity       = entity
    self.qualifier     = qualifierWith(format: q)
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
    self.prefetchingRelationshipKeyPathes = prefetch
  }
  
}


// MARK: - Query Runner

public extension TypedFetchSpecification where Object: ActiveRecordType {
  
  /**
   * Like so:
   *
   *     let _ = try Person.where("login like %@", "*he*")
   *                       .limit(4)
   *                       .fetch(in: db)
   *
   */
  func fetch(in db: Database) throws -> [ Object ] {
    let ds = ActiveDataSource<Object>(database: db)
    ds.fetchSpecification = self
    return try ds.fetchObjects()
  }
  
}

// MARK: - Typed QueryBuilder

public extension TypedFetchSpecification {
  // This is a clone of the Control QueryBuilder, but with the Generic type
  // signature ...
  
  // MARK: - Qualifiers
  
  func `where`(_ q: Qualifier) -> TypedFetchSpecification<Object> {
    var fs = self
    fs.qualifier = q
    return fs
  }
  
  func and(_ q: Qualifier) -> TypedFetchSpecification<Object> {
    var fs = self
    fs.qualifier = ZeeQL.and(fs.qualifier, q)
    return fs
  }
  func or(_ q: Qualifier) -> TypedFetchSpecification<Object> {
    var fs = self
    fs.qualifier = ZeeQL.or(fs.qualifier, q)
    return fs
  }
  
  func `where`(_ q: String, _ args: Any?...)
       -> TypedFetchSpecification<Object>
  {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
  func and(_ q: String, _ args: Any?...) -> TypedFetchSpecification<Object> {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.and(fs.qualifier, parser.parseQualifier())
    return fs
  }
  func or(_ q: String, _ args: Any?...) -> TypedFetchSpecification<Object> {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.or(fs.qualifier, parser.parseQualifier())
    return fs
  }
  
  // MARK: - Limits
  
  func limit(_ value : Int) -> TypedFetchSpecification<Object> {
    var fs = self
    fs.fetchLimit = value
    return fs
  }
  
  func offset(_ value : Int) -> TypedFetchSpecification<Object> {
    var fs = self
    fs.fetchOffset = value
    return fs
  }

  
  // MARK: - Prefetches

  func prefetch(_ path: String, _ more: String...)
       -> TypedFetchSpecification<Object>
  {
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path ] + more
    return fs
  }
  
  
  // MARK: - Ordering
  
  func order(by: SortOrdering, _ e: SortOrdering...)
       -> TypedFetchSpecification<Object>
  {
    var fs = self
    if let old = fs.sortOrderings {
      fs.sortOrderings = old + [ by ] + e
    }
    else {
      fs.sortOrderings = [ by ] + e
    }
    return fs
  }
  
  func order(by: String, _ e: String...) -> TypedFetchSpecification<Object> {
    var fs = self
    
    var ops = [ SortOrdering ]()
    if let p = SortOrdering.parse(by) {
      ops += p
    }
    for by in e {
      if let p = SortOrdering.parse(by) {
        ops += p
      }
    }

    guard !ops.isEmpty else { return self }
    
    if let old = fs.sortOrderings {
      fs.sortOrderings = old + ops
    }
    else {
      fs.sortOrderings = ops
    }
    return fs
  }
}
