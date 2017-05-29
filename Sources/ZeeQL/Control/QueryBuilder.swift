//
//  QueryBuilder.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

// MARK: - Fetch Specification Convenience

public extension FetchSpecification {
  
  // MARK: - Qualifiers
  
  func `where`(_ q: Qualifier) -> FetchSpecification {
    var fs = self
    fs.qualifier = q
    return fs
  }
  func and(_ q: Qualifier?) -> FetchSpecification {
    var fs = self
    fs.qualifier = ZeeQL.and(fs.qualifier, q)
    return fs
  }
  func or(_ q: Qualifier?) -> FetchSpecification {
    var fs = self
    fs.qualifier = ZeeQL.or(fs.qualifier, q)
    return fs
  }
  
  func `where`(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
  func and(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.and(fs.qualifier, parser.parseQualifier())
    return fs
  }
  func or(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = self
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = ZeeQL.or(fs.qualifier, parser.parseQualifier())
    return fs
  }
  
  // MARK: - Limits
  
  func limit(_ value : Int) -> FetchSpecification {
    var fs = self
    fs.fetchLimit = value
    return fs
  }
  
  func offset(_ value : Int) -> FetchSpecification {
    var fs = self
    fs.fetchOffset = value
    return fs
  }

  
  // MARK: - Prefetches

  func prefetch(_ path: String, _ more: String...) -> FetchSpecification {
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path ] + more
    return fs
  }
  
  
  // MARK: - Ordering
  
  func order(by: SortOrdering, _ e: SortOrdering...) -> FetchSpecification {
    var fs = self
    if let old = fs.sortOrderings {
      fs.sortOrderings = old + [ by ] + e
    }
    else {
      fs.sortOrderings = [ by ] + e
    }
    return fs
  }
  
  func order(by: String, _ e: String...) -> FetchSpecification {
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


public extension FetchSpecification { // Qualifier Convenience Methods
  
  public mutating func conjoin(qualifier: Qualifier) {
    if let q = self.qualifier {
      self.qualifier = q.and(qualifier)
    }
    else {
      self.qualifier = qualifier
    }
  }
  public mutating func disjoin(qualifier: Qualifier) {
    if let q = self.qualifier {
      self.qualifier = q.or(qualifier)
    }
    else {
      self.qualifier = qualifier
    }
  }
  
  public mutating func setQualifier(_ format: String, _ args: String...) {
    qualifier = qualifierWith(format: format, args)
  }
  public mutating func conjoin(_ format: String, _ args: String...) {
    guard let q = qualifierWith(format: format, args) else { return }
    conjoin(qualifier: q)
  }
  public mutating func disjoin(_ format: String, _ args: String...) {
    guard let q = qualifierWith(format: format, args) else { return }
    disjoin(qualifier: q)
  }
}

