//
//  CodeFetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public extension FetchSpecification {
  // TBD: what do we want?
  // let objects = db.select(from: Persons.self)
  //       .where(Persons.login.like("*")
  //         .and(Persons.entity.addresses.zip.eq("39126"))
  //       .limit(4)
  //       .prefetch("addresses")
  // if FetchSpec would be a generic, we could derive a lot from the type
  //    let fs = FetchSpecification
  //               .select(from: Person) -> GFetchSpecification<Person>
  //               .where(login.like ...) // login can access Person
  // TBD: this could return a fetch-spec builder instead of recreating the
  //      specs all the time (FetchSpecificationRepresentable?)
  
  static func select<T: EntityType>(_ attributes: String..., from: T.Type)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: from.entity)
    fs.fetchAttributeNames = attributes.isEmpty ? nil : attributes
    return fs
  }

  
  // MARK: - Prefetches
  
  func prefetch(_ path: Relationship, _ more: Relationship...)
       -> FetchSpecification
  {
    // TODO: in here we cannot build pathes yet. Like:
    //         `fs.prefetch(Person.e.company.addresses)`
    var fs = self
    fs.prefetchingRelationshipKeyPathes = [ path.name ] + more.map { $0.name }
    return fs
  }

  
  // MARK: - Ordering
  
  func order(by    : Attribute...,
             asc   : Attribute? = nil,
             desc  : Attribute? = nil,
             iasc  : Attribute? = nil,
             idesc : Attribute? = nil)
       -> FetchSpecification
  {
    var fs = self
    
    var ops = [ SortOrdering ]()
    
    for by in by {
      let so = SortOrdering(key: AttributeKey(by), selector: .CompareAscending)
      ops.append(so)
    }
    if let by = asc {
      let so = SortOrdering(key: AttributeKey(by), selector: .CompareAscending)
      ops.append(so)
    }
    if let by = desc {
      let so = SortOrdering(key: AttributeKey(by), selector: .CompareDescending)
      ops.append(so)
    }
    if let by = iasc {
      let so = SortOrdering(key: AttributeKey(by),
                            selector: .CompareCaseInsensitiveAscending)
      ops.append(so)
    }
    if let by = idesc {
      let so = SortOrdering(key: AttributeKey(by),
                            selector: .CompareCaseInsensitiveDescending)
      ops.append(so)
    }
    
    guard !ops.isEmpty else { return self }
    
    if let old = fs.sortOrderings { fs.sortOrderings = old + ops }
    else                          { fs.sortOrderings = ops       }
    return fs
  }
}

public extension Attribute {
  
}
