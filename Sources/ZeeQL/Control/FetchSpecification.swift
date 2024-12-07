//
//  FetchSpecification.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * Represents the parameters for a fetch, usually a database fetch. Parameters
 * include the qualifier which restricts the set of objects, the required
 * ordering or attributes.
 *
 * Raw SQL hint: CustomQueryExpressionHintKey
 *
 * Also check out the QueryBuilder extension.
 */
public protocol FetchSpecification : SmartDescription {
  // TODO: This is a little funky now because we refer to Entity. It should be
  //       a protocol.
  
  var entity              : Entity?          { get } // Access, really
  var entityName          : String?          { get }
  var fetchAttributeNames : [ String ]       { get set }
  var qualifier           : Qualifier?       { get set }
  var sortOrderings       : [ SortOrdering ] { get set }
  var fetchLimit          : Int?             { get set }
  var fetchOffset         : Int?             { get set }
  
  var usesDistinct        : Bool             { get set }
  var locksObjects        : Bool             { get set }
  var deep                : Bool             { get set }
  var fetchesRawRows      : Bool             { get set }
  var fetchesReadOnly     : Bool             { get set }
  
  var requiresAllQualifierBindingVariables : Bool { get set }
  var prefetchingRelationshipKeyPathes     : [ String ] { get set }

  var hints               : [ String : Any ]  { get set }
  subscript(hint h: String) -> Any?           { get set }

  func resolvingBindings(_ bindings: Any?) throws -> FetchSpecification
}

public protocol AdaptorRecordFetchSpecification : FetchSpecification {
  // Those can be raw or not.
  
  typealias Object = AdaptorRecord
}

public protocol DatabaseFetchSpecification<Object>: FetchSpecification {
  
  associatedtype Object : DatabaseObject
}


public let CustomQueryExpressionHintKey = "CustomQueryExpressionHintKey"

extension FetchSpecification { // Default Imp

  @inlinable
  func transform(_ transform: (inout Self) throws -> Void) rethrows -> Self {
    var fs = self
    try transform(&fs)
    return fs
  }

  // MARK: - Hints
  
  public subscript(hint h: String) -> Any? {
    set {
      if let v = newValue { hints[h] = v }
      else { hints.removeValue(forKey: h) }
    }
    get { return hints[h] }
  }
  
  // MARK: - Bindings
  
  /**
   * FIXME: document me. This seems to return values for all hints which end in
   * 'BindPattern'. The values are retrieved by applying the
   * KeyValueStringFormatter with the given object.
   *
   * This formatter does stuff like '%(lastname)s'.
   *
   * Sample:
   *
   *     var fs = FetchSpecification()
   *     fs[hint: "CustomQueryExpressionHintKeyBindPattern"] =
   *                 "%%(tables)s WHERE id = %(id)s"
   */
  func resolveHintBindPatternsWith(bindings: Any?) -> [ String : Any ] {
    guard !hints.isEmpty else { return [:] }
    
    var boundHints = hints
    for ( key, value ) in hints {
      guard key.hasSuffix("BindPattern") else { continue }
      
      let sValue = "\(value)" // Hm
      
      let endIdx = key.index(key.endIndex, offsetBy: -11)
      let bKey   = String(key[key.startIndex..<endIdx])
      
      let fValue = KeyValueStringFormatter.format(sValue, object: bindings)
      
      boundHints.removeValue(forKey: key)
      boundHints[bKey] = fValue
    }
    return boundHints
  }
  
  /**
   * Return a copy of the ``FetchSpecification`` which has the qualifier
   * bindings resolved against the given argument. Plus all xyzBindPattern
   * hints.
   * If the fetch spec has no bindings, the exisiting object is returned.
   *
   * The syntax for bindings in string qualifiers is `$binding` (e.g.
   * `lastname = $lastname`).
   *
   * The syntax for bind-pattern hints is `%(binding)s` (note the trailing
   * format specifier!).
   */
  public func resolvingBindings(_ bindings: Any?) throws -> FetchSpecification {
    var boundFS = self
    
    boundFS.hints = resolveHintBindPatternsWith(bindings: bindings)
    
    if let q = qualifier {
      boundFS.qualifier =
        try q.qualifierWith(bindings: bindings,
                            requiresAll: requiresAllQualifierBindingVariables)
    }
    
    return boundFS
  }
}


// MARK: - Description

public extension FetchSpecification {

  func appendToDescription(_ ms: inout String) {
    if let entity = entity {
      ms += " \(entity.name)"
    }
    else if let ename = entityName {
      ms += " '\(ename)'"
    }
    
    if !fetchAttributeNames.isEmpty {
      ms += " attrs[\(fetchAttributeNames.joined(separator: ","))]"
    }
    
    if let q = qualifier { ms += " \(q)" }
    
    if !sortOrderings.isEmpty {
      ms += " sort="
      ms += sortOrderings.map({ "\($0)" }).joined(separator: ",")
    }
    
    if let limit = fetchLimit {
      if let offset = fetchOffset {
        ms += " range=\(offset)/#\(limit)"
      }
      else {
        ms += " limit=\(limit)"
      }
    }
    else if let offset = fetchOffset {
      ms += " offset=\(offset)"
    }
    
    if !prefetchingRelationshipKeyPathes.isEmpty {
      ms += " prefetch["
      ms += prefetchingRelationshipKeyPathes.joined(separator: ",")
      ms += "]"
    }
    
    if usesDistinct    { ms += " DISTINCT" }
    if locksObjects    { ms += " LOCKS"    }
    if deep            { ms += " DEEP"     }
    if fetchesRawRows  { ms += " RAW"      }
    if fetchesReadOnly { ms += " r/o"      }

    if !hints.isEmpty  { ms += " hints=\(hints)" }
  }
}


// MARK: - Count Fetches

public extension FetchSpecification { // Counts
  
  @inlinable
  var fetchSpecificationForCount : FetchSpecification? {
    // TODO: this may not be necessary anymore, see _primaryFetchCount()
    if hints["CustomQueryExpressionHintKey"]            != nil { return nil }
    if hints["CustomQueryExpressionHintKeyBindPattern"] != nil { return nil }
    
    let countPattern = "%(select)s COUNT(*) FROM %(tables)s %(where)s LIMIT 1"
    
    var countFS = self
    countFS[hint: "CustomQueryExpressionHintKey"] = countPattern
    countFS.fetchesRawRows = true
    return countFS
  }
}
