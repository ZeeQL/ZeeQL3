//
//  ModelFetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct ModelFetchSpecification : FetchSpecification {
  // TODO: This is a little funky now because we refer to Entity. It should be
  //       a protocol.
  
  public var entity              : Entity?
  public var _entityName         : String?

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
    self.entity        = entity
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
    self.entity        = entity
    self.qualifier     = qualifierWith(format: q)
    self.sortOrderings = sortOrderings
    self.fetchLimit    = limit
    self.prefetchingRelationshipKeyPathes = prefetch
  }
  
  public init(fetchSpecification fs: FetchSpecification) {
    entity              = fs.entity
    fetchAttributeNames = fs.fetchAttributeNames
    qualifier           = fs.qualifier
    sortOrderings       = fs.sortOrderings
    fetchLimit          = fs.fetchLimit
    fetchOffset         = fs.fetchOffset
    usesDistinct        = fs.usesDistinct
    locksObjects        = fs.locksObjects
    deep                = fs.deep
    fetchesRawRows      = fs.fetchesRawRows
    fetchesReadOnly     = fs.fetchesReadOnly
    hints               = fs.hints
    requiresAllQualifierBindingVariables =
      fs.requiresAllQualifierBindingVariables
    prefetchingRelationshipKeyPathes = fs.prefetchingRelationshipKeyPathes
    
    if let mfs = fs as? ModelFetchSpecification {
      _entityName = mfs._entityName
    }
  }
}
