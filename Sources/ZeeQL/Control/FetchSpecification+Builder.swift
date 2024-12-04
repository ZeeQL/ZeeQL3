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

  @inlinable
  func prefetch(_ path: String, _ more: String...) -> Self {
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path ] + more
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
