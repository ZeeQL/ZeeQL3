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
    var parser = QualifierParser(string: q, arguments: args)
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
    var parser = QualifierParser(string: q, arguments: args)
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
    var parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}


// MARK: - Special Builder for CodeEntities

public extension TypedEntityType where FullEntity: CodeEntity<Self> {
  
  // TODO: select w/ pack iteration
  
  // Maybe the `where` should work on typed keys!

  /**
   * Qualify a property using a value.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany
   *   .where(\.type, .EqualTo, "group")
   * )
   * ```
   *
   * - Parameters:
   *   - key:       A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - operation: The ZeeQL `ComparisonOperation` to apply.
   *   - value:     A value of the same type (e.g. a `Date`)
   * - Returns:     The `TypedFetchSpecification` representing the query.
   */
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
  
  /**
   * Qualify a non-optional property being equal to another.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany.where(\.type, "group"))
   * ```
   *
   * - Parameters:
   *   - key:   A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - value: A value of the same type (e.g. a `Date`)
   * - Returns: The `TypedFetchSpecification` representing the query.
   */
  @inlinable
  static func `where`<A>(_ key: Swift.KeyPath<FullEntity, A>,
                         _ value: A.T) -> TypedFetchSpecification<Self>
    where A: TypedProperty
  {
    return `where`(key, .equalTo, value)
  }

  /**
   * Qualify a non-optional property being in a set of values.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany.where(\.type, [ "group", "case" ]))
   * ```
   *
   * - Parameters:
   *   - key:   A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - value: A collection value of the same type (e.g. a `Date`)
   * - Returns: The `TypedFetchSpecification` representing the query.
   */
  @inlinable
  static func `where`<A, C>(_ key: Swift.KeyPath<FullEntity, A>,
                            in value: C) -> TypedFetchSpecification<Self>
    where A: TypedProperty, C: Collection, C.Element == A.T
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let property = Self.e[keyPath: key]
    fs.qualifier = KeyValueQualifier(StringKey(property.name), .in, value)
    return fs
  }

  /**
   * Qualify an optional property using a value.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany
   *   .where(\.type, .EqualTo, "group")
   * )
   * ```
   *
   * - Parameters:
   *   - key:       A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - operation: The ZeeQL `ComparisonOperation` to apply.
   *   - value:     A value of the same type (e.g. a `Date`)
   * - Returns:     The `TypedFetchSpecification` representing the query.
   */
  @inlinable
  static func `where`<A>(
    _ key       : Swift.KeyPath<FullEntity, A>,
    _ operation : ComparisonOperation = .equalTo,
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
  
  /**
   * Qualify an optional property being equal to another.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany
   *   .where(\.type, "group")
   * )
   * ```
   *
   * - Parameters:
   *   - key:   A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - value: A value of the same type (e.g. a `Date`)
   * - Returns: The `TypedFetchSpecification` representing the query.
   */
  @inlinable
  static func `where`<A>(_ key: Swift.KeyPath<FullEntity, A>,
                         _ value: A.T) -> TypedFetchSpecification<Self>
    where A: TypedProperty, A.T: AnyOptional
  {
    return `where`(key, .equalTo, value)
  }
  
  /**
   * Qualify an optional property being in a set of values.
   *
   * Example:
   * ```swift
   * let objects = try oc.fetch(OGoCompany.where(\.type, [ "group", "case" ]))
   * ```
   *
   * - Parameters:
   *   - key:   A keypath to a ``TypedProperty`` (e.g. `\.startDate`)
   *   - value: A collection value of the same type (e.g. a `Date`)
   * - Returns: The `TypedFetchSpecification` representing the query.
   */
  @inlinable
  static func `where`<A, C>(_ key: Swift.KeyPath<FullEntity, A>,
                         in value: C) -> TypedFetchSpecification<Self>
    where A: TypedProperty, A.T: AnyOptional, C: Collection, C.Element == A.T
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let property = Self.e[keyPath: key]
    fs.qualifier = KeyValueQualifier(StringKey(property.name), .in, value)
    return fs
  }
}
