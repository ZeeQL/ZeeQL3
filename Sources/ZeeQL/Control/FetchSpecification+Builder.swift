//
//  FetchSpecification+Builder.swift
//  ZeeQL
//
//  Created by Helge Heß on 04.12.24.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

// MARK: - Fetch Specification Convenience

public extension FetchSpecification { // Qualifier Convenience Methods

  @inlinable
  mutating func conjoin(qualifier: Qualifier) {
    if let q = self.qualifier { self.qualifier = q.and(qualifier) }
    else                      { self.qualifier = qualifier        }
  }
  @inlinable
  mutating func disjoin(qualifier: Qualifier) {
    if let q = self.qualifier { self.qualifier = q.or(qualifier) }
    else                      { self.qualifier = qualifier       }
  }
  
  @inlinable
  mutating func setQualifier(_ format: String, _ args: String...) {
    qualifier = qualifierWith(format: format, args)
  }
  @inlinable
  mutating func conjoin(_ format: String, _ args: String...) {
    guard let q = qualifierWith(format: format, args) else { return }
    conjoin(qualifier: q)
  }
  @inlinable
  mutating func disjoin(_ format: String, _ args: String...) {
    guard let q = qualifierWith(format: format, args) else { return }
    disjoin(qualifier: q)
  }
}

public extension FetchSpecification {
  // This is a clone of the Control QueryBuilder, but with the Generic type
  // signature ...
  
  // MARK: - Qualifiers
  
  @inlinable
  func `where`(_ q: Qualifier) -> Self { transform { $0.qualifier = q } }
  
  @inlinable
  func and(_ q: Qualifier) -> Self {
    transform { $0.qualifier = ZeeQL.and($0.qualifier, q) }
  }
  @inlinable
  func or(_ q: Qualifier) -> Self {
    transform { $0.qualifier = ZeeQL.or($0.qualifier, q) }
  }
  
  @inlinable
  func `where`(_ q: String, _ args: Any?...) -> Self {
    let parser = QualifierParser(string: q, arguments: args)
    return transform { $0.qualifier = parser.parseQualifier() }
  }
  @inlinable
  func and(_ q: String, _ args: Any?...) -> Self {
    let parser = QualifierParser(string: q, arguments: args)
    return transform {
      $0.qualifier = ZeeQL.and($0.qualifier, parser.parseQualifier())
    }
  }
  @inlinable
  func or(_ q: String, _ args: Any?...) -> Self {
    let parser = QualifierParser(string: q, arguments: args)
    return transform {
      $0.qualifier = ZeeQL.or($0.qualifier, parser.parseQualifier())
    }
  }
  
  // MARK: - Limits
  
  @inlinable
  func limit(_ value : Int) -> Self { transform { $0.fetchLimit = value } }
  
  @inlinable
  func offset(_ value : Int) -> Self { transform { $0.fetchOffset = value } }

  @inlinable
  func distinct(_ usesDistinct: Bool = true) -> Self {
    transform { $0.usesDistinct = usesDistinct }
  }

  
  // MARK: - Prefetches

  @inlinable
  func clearPrefetch() -> Self {
    transform { $0.prefetchingRelationshipKeyPathes = [] }
  }

  @inlinable
  func prefetch(_ path: String, _ more: String..., clear: Bool = false) -> Self
  {
    transform {
      if clear { $0.prefetchingRelationshipKeyPathes = [] }
      $0.prefetchingRelationshipKeyPathes.append(path)
      $0.prefetchingRelationshipKeyPathes.append(contentsOf: more)
    }
  }
  @inlinable
  func prefetch(_ path: Relationship, _ more: Relationship...,
                clear: Bool = false)
       -> Self
  {
    // TODO: in here we cannot build pathes yet. Like:
    //         `fs.prefetch(Person.e.company.addresses)`
    transform {
      if clear { $0.prefetchingRelationshipKeyPathes = [] }
      $0.prefetchingRelationshipKeyPathes.append(path.name)
      $0.prefetchingRelationshipKeyPathes.append(contentsOf: more.map(\.name))
    }
  }

  
  // MARK: - Ordering
  
  @inlinable
  func order(by: SortOrdering, _ e: SortOrdering...) -> Self {
    transform {
      $0.sortOrderings.append(by)
      $0.sortOrderings.append(contentsOf: e)
    }
  }
  
  @inlinable
  func order(by: String, _ e: String...) -> Self {
    transform {
      if let p = SortOrdering.parse(by) { $0.sortOrderings += p }
      else { assertionFailure("Could not parse order string")}
      for by in e {
        if let p = SortOrdering.parse(by) {
          $0.sortOrderings.append(contentsOf: p)
        }
        else { assertionFailure("Could not parse order string")}
      }
    }
  }
  @inlinable
  func order(by    : Attribute...,
             asc   : Attribute? = nil,
             desc  : Attribute? = nil,
             iasc  : Attribute? = nil,
             idesc : Attribute? = nil)
       -> Self
  {
    transform { fs in
      for by in by {
        let so = SortOrdering(key: AttributeKey(by), selector: .CompareAscending)
        fs.sortOrderings.append(so)
      }
      if let by = asc {
        let so = SortOrdering(key: AttributeKey(by), selector: .CompareAscending)
        fs.sortOrderings.append(so)
      }
      if let by = desc {
        let so = SortOrdering(key: AttributeKey(by), selector: .CompareDescending)
        fs.sortOrderings.append(so)
      }
      if let by = iasc {
        let so = SortOrdering(key: AttributeKey(by),
                              selector: .CompareCaseInsensitiveAscending)
        fs.sortOrderings.append(so)
      }
      if let by = idesc {
        let so = SortOrdering(key: AttributeKey(by),
                              selector: .CompareCaseInsensitiveDescending)
        fs.sortOrderings.append(so)
      }
    }
  }
}

extension FetchSpecification {
  
  @inlinable
  static func select<T: EntityType>(_ attributes: String..., from: T.Type)
              -> FetchSpecification // <= because we need the entity
  {
    var fs = ModelFetchSpecification(entity: from.entity)
    fs.fetchAttributeNames = attributes
    return fs
  }
}


// MARK: - Special Builder for CodeEntities

public extension DatabaseFetchSpecification
  where Object: TypedEntityType, Object.FullEntity: CodeEntity<Object>
{
  
  // TODO: select w/ pack iteration

  // MARK: - Qualifier

  // Maybe the `where` should work on typed keys!

  @inlinable
  func `where`<A: TypedProperty>(_ key: Swift.KeyPath<Object.FullEntity, A>,
                                 _ operation: ComparisonOperation,
                                 _ value: A.T) -> Self
  {
    let property = Object.e[keyPath: key]
    return `where`(KeyValueQualifier(StringKey(property.name), operation,value))
  }
  
  @inlinable
  func `where`<A: TypedProperty>(_ key: Swift.KeyPath<Object.FullEntity, A>,
                                 _ value: A.T) -> Self
  {
    return `where`(key, .EqualTo, value)
  }

  @inlinable
  func `where`<A: TypedProperty>(_ key: Swift.KeyPath<Object.FullEntity, A>,
                                 _ operation: ComparisonOperation,
                                 _ value: A.T) -> Self
    where A: TypedProperty, A.T: AnyOptional
  {
    let property = Object.e[keyPath: key]
    return `where`(KeyValueQualifier(StringKey(property.name), operation,value))
  }
  
  @inlinable
  func `where`<A: TypedProperty>(_ key: Swift.KeyPath<Object.FullEntity, A>,
                                 _ value: A.T) -> Self
    where A: TypedProperty, A.T: AnyOptional
  {
    return `where`(key, .EqualTo, value)
  }

  
  // MARK: - Ordering

  #if compiler(>=6)
  @inlinable
  func order<each A: Attribute>(
    by key: repeat Swift.KeyPath<Object.FullEntity, each A>,
    using selector: SortOrdering.Selector = .CompareAscending
  ) -> Self
  {
    transform {
      for key in repeat each key {
        let attribute = Object.e[keyPath: key]
        let so = SortOrdering(key: AttributeKey(attribute), selector: selector)
        $0.sortOrderings.append(so)
      }
    }
  }
  #else // !compiler(>=6)
  @inlinable
  func order<V>(by key: Swift.KeyPath<Object.FullEntity, CodeAttribute<V>>,
                _ selector: SortOrdering.Selector = .CompareAscending)
         -> Self
    where V: AttributeValue
  {
    let attribute = Object.e[keyPath: key]
    let so = SortOrdering(key: AttributeKey(attribute), selector: selector)
    return order(by: so)
  }
  #endif // !compiler(>=6)
  
  
  // MARK: - Prefetch

  #if compiler(>=6)
  @inlinable
  func prefetch<each O: CodeRelationshipType>(
    _ relationship:
      repeat Swift.KeyPath<Object.FullEntity, each O>,
    clear: Bool = false
  ) -> Self
  {
    transform {
      if clear { $0.prefetchingRelationshipKeyPathes = [] }
      for relationship in repeat each relationship {
        let relationship = Object.e[keyPath: relationship]
        $0.prefetchingRelationshipKeyPathes.append(relationship.name)
      }
    }
  }

  @inlinable
  func select<each A: Attribute>(
    _ attribute: repeat Swift.KeyPath<Object.FullEntity, each A>,
    clear: Bool = false
  ) -> Self
  {
    transform {
      if clear { $0.fetchAttributeNames = [] }
      for attributePath in repeat each attribute {
        let attribute = Object.e[keyPath: attributePath]
        $0.fetchAttributeNames.append(attribute.name)
      }
    }
  }
  #endif // compiler(>=6)
}
