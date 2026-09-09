//
//  ArrayDataSource.swift
//  ZeeQL3
//
//  Created by Helge Hess on 18/04/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

open class ArrayDataSource<Object: SwiftObject> : DataSource<Object>,
                                                  SmartDescription
{
  // TODO: sort
  
  let log : ZeeQLLogger  = globalZeeQLLogger
  
  public var auxiliaryQualifier : Qualifier?
  public var objects            : [ Object ]
  
  public init(_ objects: [ Object ] = []) {
    self.objects = objects
  }

  @inlinable
  open func fetchCount() throws -> Int {
    let primary   = fetchSpecification?.qualifier
    let auxiliary = auxiliaryQualifier
    guard primary != nil || auxiliary != nil else { return objects.count }

    let primaryEvaluation   = primary   as? QualifierEvaluation
    let auxiliaryEvaluation = auxiliary as? QualifierEvaluation
    guard primary == nil || primaryEvaluation != nil else {
      return objects.count
    }
    guard auxiliary == nil || auxiliaryEvaluation != nil else {
      return objects.count
    }

    var count = 0
    for object in objects {
      if let evaluation = primaryEvaluation,
         !evaluation.evaluate(with: object)
      {
        continue
      }
      if let evaluation = auxiliaryEvaluation,
         !evaluation.evaluate(with: object)
      {
        continue
      }
      count += 1
    }
    return count
  }
  
  override open func fetchObjects(yield cb: ( Object ) -> Void) throws {
    // FIXME: Not nice. Too many dupe code.
    // TODO:  optimize
    
    guard !objects.isEmpty else { return }
    
    if let fs = fetchSpecification {
      // this is a little lame
      
      let q : Qualifier?
      if let fsQ = fs.qualifier, let aQ = auxiliaryQualifier { q = fsQ.and(aQ) }
      else if let fsQ = fs.qualifier { q = fsQ }
      else { q = auxiliaryQualifier }
      
      let evaluation: QualifierEvaluation?
      if let q {
        if let value = q as? QualifierEvaluation { evaluation = value }
        else {
          log.error("qualifier doesn't conform to `QualifierEvaluation`", self)
          evaluation = nil
        }
      }
      else { evaluation = nil }

      if fs.sortOrderings.isEmpty {
        let range = fetchRange(fs, defaultLimit: objects.count)
        let matches = objects.lazy.filter {
          evaluation?.evaluate(with: $0) ?? true
        }
        for object in matches.dropFirst(range.offset).prefix(range.limit) {
          cb(object)
        }
        return
      }

      var sorted: [ Object ]
      if let evaluation {
        sorted = objects.filter { evaluation.evaluate(with: $0) }
      }
      else { sorted = objects }

      sort(&sorted, using: fs.sortOrderings)
      
      let count = sorted.count
      let range = fetchRange(fs, defaultLimit: count)
      guard range.offset < count, range.limit > 0 else { return }
      let actualLimit = min(count - range.offset, range.limit)
      
      for i in range.offset..<(range.offset + actualLimit) {
        cb(sorted[i])
      }
    }
    else if let q = auxiliaryQualifier {
      if let qe = q as? QualifierEvaluation {
        for object in objects {
          if qe.evaluate(with: object) { cb(object) }
        }
      }
      else {
        log.error("auxiliaryQualifier doesn't conform to `QualifierEvaluation`",
                  self)
      }
    }
    else {
      for object in objects { cb(object) }
    }
  }

  private func fetchRange(_ fs: FetchSpecification, defaultLimit: Int)
    -> (offset: Int, limit: Int)
  {
    let rawOffset = fs.fetchOffset ?? 0
    let rawLimit  = fs.fetchLimit  ?? defaultLimit
    if rawOffset < 0 {
      log.warn("negative fetch offset, using zero:", rawOffset)
    }
    if rawLimit < 0 {
      log.warn("negative fetch limit, using zero:", rawLimit)
    }
    return ( max(0, rawOffset), max(0, rawLimit) )
  }

  private func sort(_ objects: inout [ Object ],
                    using orderings: [ SortOrdering ])
  {
    for ordering in orderings {
      guard case .other(let selector) = ordering.selector else { continue }
      log.warn("not applying unsupported sort selector:", selector)
      return
    }
    objects.sort { lhs, rhs in ordered(lhs, before: rhs, using: orderings) }
  }

  private func ordered(_ lhs: Object, before rhs: Object,
                       using orderings: [ SortOrdering ]) -> Bool
  {
    for ordering in orderings {
      var left  = ordering.keyExpr.valueForObject(lhs)
      var right = ordering.keyExpr.valueForObject(rhs)
      let ascending: Bool

      switch ordering.selector {
        case .ascending:
          ascending = true
        case .descending:
          ascending = false
        case .caseInsensitiveAscending:
          if let string = left  as? String { left  = string.lowercased() }
          if let string = right as? String { right = string.lowercased() }
          ascending = true
        case .caseInsensitiveDescending:
          if let string = left  as? String { left  = string.lowercased() }
          if let string = right as? String { right = string.lowercased() }
          ascending = false
        case .other:
          return false
      }

      if eq(left, right) { continue }
      return ascending ? isSmaller(left, right) : isSmaller(right, left)
    }
    return false
  }
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    ms += " #objects=\(objects.count)"
    if let fs = fetchSpecification { ms += " \(fs)" }
    if let q  = auxiliaryQualifier { ms += " \(q)"  }
  }
}
