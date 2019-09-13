//
//  Join.swift
//  ZeeQL
//
//  Created by Helge Hess on 18/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Used by `Relationship` objects to connect two entities. Usually
 * source/destination are the primary and foreign keys forming the
 * relationship.
 */
public struct Join : Equatable, SmartDescription {
  
  public enum Semantic : Hashable {
    case fullOuterJoin, innerJoin, leftOuterJoin, rightOuterJoin
  }
  
  // TBD: rather do unowned?
  public weak var source      : Attribute?
  public weak var destination : Attribute?
  
  public let sourceName      : String?
  public let destinationName : String?
  
  public init(source: Attribute, destination: Attribute) {
    self.source          = source
    self.destination     = destination
    self.sourceName      = source.name
    self.destinationName = destination.name
  }
  
  public init(source: String, destination: String) {
    self.sourceName      = source
    self.destinationName = destination
  }
  
  public init(join: Join, disconnect: Bool = false) {
    if disconnect {
      sourceName      = join.sourceName      ?? join.source?.name
      destinationName = join.destinationName ?? join.destination?.name
    }
    else {
      source          = join.source
      destination     = join.destination
      sourceName      = join.sourceName
      destinationName = join.destinationName
    }
  }

  
  public func references(property: Property) -> Bool {
    // TODO: look into data-path for flattened relationships
    // TODO: call ==
    return property === source || property === destination
  }
  
  
  // MARL: - resolve objects in models
  
  public mutating func connectToEntities(from: Entity, to: Entity) {
    if let n = sourceName      { source      = from[attribute: n] }
    if let n = destinationName { destination = to  [attribute: n] }
  }
  public mutating func disconnect() {
    source      = nil
    destination = nil
  }
  
  public var isConnected : Bool {
    if sourceName      != nil && source      == nil { return false }
    if destinationName != nil && destination == nil { return false }
    return true
  }
  
  
  // MARK: - operations
  
  public var inverse : Join {
    if let ndest = source, let nsource = destination {
      return Join(source: nsource, destination: ndest)
    }

    return Join(source      : destinationName ?? "ERROR",
                destination : sourceName      ?? "ERROR")
  }
  
  public func isReciprocalTo(join other: Join) -> Bool {
    /* fast check (should work often) */
    if let msource = self.source,
       let osource = other.source,
       let mdest   = self.destination,
       let odest   = other.destination
    {
      if msource === odest && mdest === osource { return true }
    }
    
    /* slow check */
    // hm
    guard let msn = sourceName ?? source?.name else { return false }
    guard let odn = other.destinationName ?? other.destination?.name
     else { return false }
    guard msn == odn else { return false }

    guard let osn = other.sourceName ?? other.source?.name else { return false }
    guard let mdn = destinationName ?? destination?.name   else { return false }
    guard osn == mdn else { return false }
    
    return true
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += shortDescription
  }

  var shortDescription : String {
    let fromKey: String?, toKey: String?
    
    if let s = source               { fromKey = s.name   }
    else if let s = sourceName      { fromKey = "'\(s)'" }
    else                            { fromKey = nil      }

    if let s = destination          { toKey = s.name     }
    else if let s = destinationName { toKey = "'\(s)'"   }
    else                            { toKey = nil        }
    
    if let from = fromKey, let to = toKey { return "\(from)=>\(to)" }
    else if let from = fromKey            { return "\(from)=>?"     }
    else if let to = toKey                { return "?=>\(to)"       }
    else                                  { return "?"              }
  }
  
  
  // MARK: - Equatable

  public static func ==(lhs: Join, rhs: Join) -> Bool {
    /* fast check (should work often) */
    if lhs.source === rhs.source && lhs.destination === rhs.destination {
      return true
    }
    
    /* slow check */
    // TODO: call ==
    return false
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Join else { return false }
    return self == other
  }
}

extension Join {
  // Maybe that should be public API, but then framework users don't usually
  // have to deal with this.
  
  func source(in entity: Entity) -> Attribute? {
    if let attr = source { return attr }
    if let name = sourceName, let attr = entity[attribute: name] { return attr }
    return nil
  }
  func destination(in entity: Entity) -> Attribute? {
    if let attr = destination { return attr }
    if let name = destinationName,
      let attr = entity[attribute: name] { return attr }
    return nil
  }
}
