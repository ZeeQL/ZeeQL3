//
//  EntityType+Builder.swift
//  ZeeQL3
//
//  Created by Helge Heß on 04.12.24.
//

public extension EntityType {
  // TBD: maybe rename, 'select' should run the actual select, right?
  
  @inlinable
  static func select(_ attributes: String...) -> FetchSpecification {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = attributes
    return fs
  }
  
  // TBD: change this, 'select' should run the actual select, right?
  @inlinable
  static func select(_ a1: Attribute, _ attributes: Attribute...)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = ([ a1 ] + attributes).map { $0.name }
    return fs
  }
  
  
  // MARK: - Qualifiers
  
  @_disfavoredOverload
  @inlinable
  static func `where`(_ q: Qualifier) -> FetchSpecification {
    // if we need no attributes
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.qualifier = q
    return fs
  }
  
  @_disfavoredOverload
  @inlinable
  static func `where`(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = ModelFetchSpecification(entity: Self.entity)
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}

public extension TypedEntityType where Self: DatabaseObject {
  // TBD: maybe rename, 'select' should run the actual select, right?
  
  @inlinable
  static func select(_ attributes: String...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.fetchAttributeNames = attributes
    return fs
  }
  
  // TBD: change this, 'select' should run the actual select, right?
  @inlinable
  static func select(_ a1: Attribute, _ attributes: Attribute...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.fetchAttributeNames = ([ a1 ] + attributes).map { $0.name }
    return fs
  }
  
  
  // MARK: - Qualifiers
  
  @inlinable
  static func `where`(_ q: Qualifier) -> TypedFetchSpecification<Self> {
    // if we need no attributes
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.qualifier = q
    return fs
  }
  @inlinable
  static func `where`(_ q: String, _ args: Any?...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}

public extension TypedEntityObject {
  
  static func `where`(_ q: Qualifier) -> TypedFetchSpecification<Self> {
    var fs = TypedFetchSpecification<Self>()
    fs.qualifier = q
    return fs
  }
  static func `where`(_ q: String, _ args: Any?...)
    -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>()
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}


// MARK: - Special Builder for CodeEntities

public extension TypedEntityType where FullEntity: CodeEntity<Self> {
  
  // TODO: select w/ pack iteration
  
  // Maybe the `where` should work on typed keys!

  @inlinable
  static func `where`<A: TypedProperty>(
    _ key       : Swift.KeyPath<FullEntity, A>,
    _ operation : ComparisonOperation,
    _ value     : A.T
  ) -> TypedFetchSpecification<Self>
  {
    // if we need no attributes
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let property = Self.e[keyPath: key]
    fs.qualifier = KeyValueQualifier(StringKey(property.name), operation, value)
    return fs
  }
  
  @inlinable
  static func `where`<A>(_ key: Swift.KeyPath<FullEntity, A>,
                         _ value: A.T) -> TypedFetchSpecification<Self>
    where A: TypedProperty
  {
    return `where`(key, .EqualTo, value)
  }
  
  @inlinable
  static func `where`<A>(
    _ key       : Swift.KeyPath<FullEntity, A>,
    _ operation : ComparisonOperation = .EqualTo,
    _ value     : A.T
  ) -> TypedFetchSpecification<Self>
    where A: TypedProperty, A.T: AnyOptional
  {
    // if we need no attributes
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let property = Self.e[keyPath: key]
    fs.qualifier = KeyValueQualifier(StringKey(property.name), operation, value)
    return fs
  }
  
  @inlinable
  static func `where`<A>(_ key: Swift.KeyPath<FullEntity, A>,
                         _ value: A.T) -> TypedFetchSpecification<Self>
    where A: TypedProperty, A.T: AnyOptional
  {
    return `where`(key, .EqualTo, value)
  }
}
