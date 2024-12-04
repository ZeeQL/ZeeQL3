//
//  FetchSpecification+Builder.swift
//  ZeeQL3
//
//  Created by Helge Heß on 04.12.24.
//

public extension DatabaseFetchSpecification {
  // This is a clone of the Control QueryBuilder, but with the Generic type
  // signature ...
  
  // MARK: - Qualifiers
  
  @inlinable
  func `where`(_ q: Qualifier) -> Self {
    var fs = self
    fs.qualifier = q
    return fs
  }
  
  @inlinable
  func and(_ q: Qualifier) -> Self {
    var fs = self
    fs.qualifier = ZeeQL.and(fs.qualifier, q)
    return fs
  }
  @inlinable
  func or(_ q: Qualifier) -> Self {
    var fs = self
    fs.qualifier = ZeeQL.or(fs.qualifier, q)
    return fs
  }
  
  @inlinable
  func `where`(_ q: String, _ args: Any?...) -> Self {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
  @inlinable
  func and(_ q: String, _ args: Any?...) -> Self {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.and(fs.qualifier, parser.parseQualifier())
    return fs
  }
  @inlinable
  func or(_ q: String, _ args: Any?...) -> Self {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.or(fs.qualifier, parser.parseQualifier())
    return fs
  }
  
  // MARK: - Limits
  
  @inlinable
  func limit(_ value : Int) -> Self {
    var fs = self
    fs.fetchLimit = value
    return fs
  }
  
  @inlinable
  func offset(_ value : Int) -> Self {
    var fs = self
    fs.fetchOffset = value
    return fs
  }

  
  // MARK: - Prefetches

  /// Note: This overrides previous prefetches!
  @inlinable
  func prefetch(_ path: String, _ more: String...) -> Self {
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path ] + more
    return fs
  }
  /// Note: This overrides previous prefetches!
  @inlinable
  func prefetch(_ path: Relationship, _ more: Relationship...)
       -> Self
  {
    // TODO: in here we cannot build pathes yet. Like:
    //         `fs.prefetch(Person.e.company.addresses)`
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path.name ] + more.map { $0.name }
    return fs
  }

  
  // MARK: - Ordering
  
  @inlinable
  func order(by: SortOrdering, _ e: SortOrdering...) -> Self {
    var fs = self
    if let old = fs.sortOrderings {
      fs.sortOrderings = old + [ by ] + e
    }
    else {
      fs.sortOrderings = [ by ] + e
    }
    return fs
  }
  
  @inlinable
  func order(by: String, _ e: String...) -> Self {
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
}
