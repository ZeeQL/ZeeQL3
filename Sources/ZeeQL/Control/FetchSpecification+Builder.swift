//
//  FetchSpecification+Builder.swift
//  ZeeQL3
//
//  Created by Helge Heß on 04.12.24.
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

  
  // MARK: - Prefetches

  /// Note: This overrides previous prefetches!
  @inlinable
  func prefetch(_ path: String, _ more: String...) -> Self {
    transform { $0.prefetchingRelationshipKeyPathes = [ path ] + more }
  }
  /// Note: This overrides previous prefetches!
  @inlinable
  func prefetch(_ path: Relationship, _ more: Relationship...)
       -> Self
  {
    // TODO: in here we cannot build pathes yet. Like:
    //         `fs.prefetch(Person.e.company.addresses)`
    transform {
      $0.prefetchingRelationshipKeyPathes = [ path.name ] + more.map { $0.name }
    }
  }

  
  // MARK: - Ordering
  
  @inlinable
  func order(by: SortOrdering, _ e: SortOrdering...) -> Self {
    transform {
      if let old = $0.sortOrderings { $0.sortOrderings = old + [ by ] + e }
      else                          { $0.sortOrderings = [ by ] + e }
    }
  }
  
  @inlinable
  func order(by: String, _ e: String...) -> Self {
    transform {
      var ops = [ SortOrdering ]()
      if let p = SortOrdering.parse(by) { ops += p }
      for by in e {
        if let p = SortOrdering.parse(by) { ops += p }
      }

      if let old = $0.sortOrderings { $0.sortOrderings = old + ops }
      else                          { $0.sortOrderings = ops }
    }
  }
}


// MARK: - Special Builder for CodeEntities

public extension DatabaseFetchSpecification
  where Object: TypedEntityType, Object.FullEntity: CodeEntity<Object>
{
  
  // TODO: select w/ pack iteration

  @inlinable
  func `where`<V>(_ key: Swift.KeyPath<Object.FullEntity, CodeAttribute<V>>,
                  _ operation: ComparisonOperation,
                  _ value: V) -> Self
    where V: AttributeValue
  {
    let attribute = Object.e[keyPath: key]
    return `where`(KeyValueQualifier(AttributeKey(attribute), operation, value))
  }
  
  @inlinable
  func `where`<V>(_ key: Swift.KeyPath<Object.FullEntity, CodeAttribute<V>>,
                  _ value: V) -> Self
    where V: AttributeValue
  {
    `where`(key, .EqualTo, value)
  }

  #if swift(>=5.9)
  @inlinable
  func order<each V: AttributeValue>(
    by key: repeat Swift.KeyPath<Object.FullEntity, CodeAttribute<each V>>,
    using selector: SortOrdering.Selector = .CompareAscending
  ) -> Self
  {
    transform {
      for key in repeat each key {
        let attribute = Object.e[keyPath: key]
        let so = SortOrdering(key: AttributeKey(attribute), selector: selector)
        if $0.sortOrderings == nil { $0.sortOrderings = [ so ] }
        else { $0.sortOrderings?.append(so) }
      }
    }
  }
  #else
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
  #endif // swift(>=5.9
}
