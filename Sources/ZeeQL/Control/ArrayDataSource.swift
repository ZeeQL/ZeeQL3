//
//  ArrayDataSource.swift
//  ZeeQL3
//
//  Created by Helge Hess on 18/04/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
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
    return objects.count
  }
  
  override open func fetchObjects(yield cb: ( Object ) -> Void) throws {
    // FIXME: Not nice. Too many dupe code.
    // TODO:  optimize
    
    guard !objects.isEmpty else { return }
    
    if let fs = fetchSpecification {
      // this is a little lame
      
      let q : Qualifier?
      if let fsQ = fs.qualifier, let aQ = auxiliaryQualifier {
        q = fsQ.and(aQ)
      }
      else if let fsQ = fs.qualifier {
        q = fsQ
      }
      else {
        q = auxiliaryQualifier
      }
      
      // TODO: when there is no sort ordering, we could avoid that
      var filtered : [ Object ]
      if let q = q {
        if let qe = q as? QualifierEvaluation {
          var filter = [ Object ]()
          for object in objects {
            guard qe.evaluateWith(object: object) else { continue }
            filter.append(object)
          }
          filtered = filter
        }
        else {
          log.error("qualifier doesn't conform to `QualifierEvaluation`", self)
          filtered = objects
        }
      }
      else {
        filtered = objects
      }
      
      
      if !fs.sortOrderings.isEmpty {
        // TODO: sort
        log.warn("not applying sort orderings", self, fs.sortOrderings)
      }
      
      let count       = filtered.count
      let offset      = fs.fetchOffset ?? 0
      let limit       = fs.fetchLimit  ?? count
      let actualLimit = min(count - offset, limit)
      
      for i in offset..<(offset + actualLimit) {
        cb(filtered[i])
      }
    }
    else if let q = auxiliaryQualifier {
      if let qe = q as? QualifierEvaluation {
        for object in objects {
          if qe.evaluateWith(object: object) {
            cb(object)
          }
        }
      }
      else {
        log.error("auxiliaryQualifier doesn't conform to `QualifierEvaluation`",
                  self)
      }
    }
  }
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    ms += " #objects=\(objects.count)"
    if let fs = fetchSpecification { ms += " \(fs)" }
    if let q  = auxiliaryQualifier { ms += " \(q)"  }
  }
}
