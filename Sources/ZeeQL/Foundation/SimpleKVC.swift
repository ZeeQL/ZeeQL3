//
//  SimpleKVS.swift
//  ZeeQL3
//
//  Created by Helge Heß on 6/1/16.
//  Copyright © 2016-2024 ZeeZide GmbH. All rights reserved.
//

import class Foundation.NSObject

public protocol KeyValueCodingType {
  
  func value(forKey k: String) -> Any?
  
}

public protocol MutableKeyValueCodingType : AnyObject {
  // MutableKeyValueCodingType only really makes sense for classes, right?
  // Well, it could return 'self' with the updated struct?
  
  func takeValue(_ value : Any?, forKey k: String) throws
  func takeValues(_ values : [ String : Any? ]) throws
}

public extension MutableKeyValueCodingType {
  
  @inlinable
  func takeValues(_ values : [ String : Any? ]) throws {
    for ( key, value ) in values {
      try takeValue(value, forKey: key)
    }
  }
}

public protocol KeyValueCodingTargetValue : AnyObject {
  // Again, only makes sense for classes? But we'd like to have structs.
  func setValue(_ value: Any?) throws
}

public extension KeyValueCodingType {

  @inlinable
  func value(forKey k: String) -> Any? {
    return KeyValueCoding.defaultValue(forKey: k, inObject: self)
  }
  
}

public extension KeyValueCodingType {
  // TODO: own protocol for that
  
  @inlinable
  func values(forKeys keys: [String]) -> [ String : Any ] {
    var values = [ String : Any ]()
    values.reserveCapacity(keys.count)
    for key in keys {
      guard let value = self.value(forKey: key) else { continue }
      values[key] = value
    }
    return values
  }
  
}

public struct KeyValueCoding {
  
  public enum Error : Swift.Error {
    case UnsupportedDictionaryKeyType(Any.Type)
    case CannotCoerceValueForKey(Any.Type, Any?, String)
    case CannotCoerceValue(Any.Type, Any?)
    case EmptyKeyPath
    case CannotTakeValueForKey(String)
  }
  
  @inlinable
  public static func takeValue(_ v: Any?, forKeyPath p: String,
                               inObject o: Any?) throws
  {
    let path = p.split(separator: ".").map(String.init)
    try takeValue(v, forKeyPath: path, inObject: o)
  }
  @inlinable
  public static func takeValue(_ v: Any?, forKeyPath p: [ String ],
                               inObject o: Any?) throws
  {
    // TBD
    guard !p.isEmpty else { throw Error.EmptyKeyPath }
    guard let o = o  else { return } // no-op
    
    if p.count == 1 { return try takeValue(v, forKey: p[0], inObject: o) }
    
    let target = value(forKeyPath: Array(p[0..<(p.count - 1)]), inObject: o)
    guard let t = target else { return } // no-op
    try takeValue(v, forKey: p[p.count - 1], inObject: t)
  }

  @inlinable
  public static func value(forKeyPath p: String, inObject o: Any?) -> Any? {
    let path = p.split(separator: ".").map(String.init)
    return value(forKeyPath: path, inObject: o)
  }
  
  @inlinable
  public static func value(forKeyPath p: [ String ], inObject o: Any?) -> Any? {
    var cursor = o
    for key in p {
      cursor = value(forKey: key, inObject: cursor)
      if cursor == nil { break }
    }
    return cursor
  }

  @inlinable
  public static func takeValue(_ v: Any?, forKey k: String,
                               inObject o: Any?) throws
  {
    if let kvc = o as? MutableKeyValueCodingType {
      try kvc.takeValue(v, forKey: k)
    }
    else if let target = value(forKey: k, inObject: o)
                         as? KeyValueCodingTargetValue
    {
      if let v = v {
        try target.setValue(v)
      }
      else {
        try target.setValue(nil)
      }
    }
    else {
      throw Error.CannotTakeValueForKey(k)
    }
  }

  @inlinable
  public static func value(forKey k: String, inObject o: Any?) -> Any? {
    if let kvc = o as? KeyValueCodingType {
      return kvc.value(forKey: k)
    }
    return defaultValue(forKey: k, inObject: o)
  }

  @inlinable
  public static func defaultValue(forKey k: String, inObject o: Any?) -> Any? {
    // Presumably this is really inefficient, but well :-)
    guard let object = o else { return nil }
    
    let mirror = Mirror(reflecting: object)
    
    // extra guard against Optionals
    let isOpt  = mirror.displayStyle == .optional
    let isDict = mirror.displayStyle == .dictionary
    if isOpt {
      guard mirror.children.count > 0 else { return nil }
      let (_, some) = mirror.children.first!
      return value(forKey: k, inObject: some)
    }
    
    // support dictionary
    if isDict {
      return defaultValue(forKey: k, inDictionary: object, mirror: mirror)
    }
    
    // regular object, scan
    for ( label, value ) in mirror.children {
      guard let okey = label else { continue }
      guard okey == k        else { continue }
      
      let valueMirror = Mirror(reflecting: value)
      if valueMirror.displayStyle != .optional { return value }
      
      guard valueMirror.children.count > 0 else { return nil }
      
      let (_, some) = valueMirror.children.first!
      
      return some
    }
    return nil
  }
  
  @inlinable
  public static func values(forKeys keys: [String], inObject o: Any?)
                     -> [ String : Any ]
  {
    guard let o = o else { return [:] }
    
    if let ko = o as? KeyValueCodingType {
      return ko.values(forKeys: keys)
    }
    
    var values = [ String : Any ]()
    for key in keys {
      if let value = value(forKey: key, inObject: o) {
        values[key] = value
      }
    }
    return values
  }
}

public extension KeyValueCoding {
  
  @inlinable
  static func defaultValue(forKey k: String, inDictionary o: Any,
                           mirror: Mirror) -> Any?
  {
    for ( _, pair ) in mirror.children {
      let pairMirror = Mirror(reflecting: pair)
        // mirror on the (Key,Value) tuple of the Dictionary
        //   children[0] = ( Optional(".0"), String )
        //   children[1] = ( Optional(".1"), Any )
      
      // extract key
      let keyIdx        = pairMirror.children.startIndex
      let ( _, anyKey ) = pairMirror.children[keyIdx]
      let key           = (anyKey as? String) ?? "\(anyKey)"
      guard key == k else { continue } // break if key is not matching
      
      // extract value
      let valueIdx      = pairMirror.children.index(after: keyIdx)
      let ( _, value )  = pairMirror.children[valueIdx]
      
      // log.info("  \(key) = \(value)")
      
      let valueMirror = Mirror(reflecting: value)
      if valueMirror.displayStyle != .optional { return value }
      
      guard valueMirror.children.count > 0 else { return nil }
      
      let (_, some) = valueMirror.children.first!
        
      return some
    }
    return nil
  }
  
}


// MARK: - KVC for Swift Base Collections

extension Dictionary: KeyValueCodingType /*, MutableKeyValueCodingType */ {
  // Technically we would want to just extend Dictionary<String, Any?> but that
  // doesn't fly yet in Swift 3.0.
  // MutableKeyValueCodingType only really makes sense for classes, right?
  // Well, it could return 'self' with the updated struct?

  @inlinable
  public mutating func takeValue(_ value : Any?, forKey key: String) throws {
    // TODO: support the Int.Type key values below
    guard let k = key as? Key else {
      throw KeyValueCoding.Error.UnsupportedDictionaryKeyType(Key.self)
    }
    
    // TODO: more coercion
    guard let v = value as? Value else {
      throw KeyValueCoding.Error.CannotCoerceValueForKey(Value.self, value, key)
    }
    
    self[k] = v
  }
  
  @inlinable
  public func value(forKey k: String) -> Any? {
    if let k = k as? Key {
      guard let value : Value = self[k] else { return nil }
      return value
    }
    
    if Key.self is Int.Type {
      guard let ik = Int(k) else { return nil }
      guard let value : Value = self[ik as! Key] else { return nil }
      return value
    }
    
    return value
  }
  
}

extension Array : KeyValueCodingType {
  // KVC on an array is a map operation. Except for the special '@' functions.
  
  @inlinable
  public func value(forKey k: String) -> Any? {
    // Element
    if k.hasPrefix("@") {
      switch k {
        case "@count": return count
        // TODO: @avg etc
        default: break
      }
    }
    
    guard !isEmpty else { return [] }

    return map { KeyValueCoding.value(forKey: k, inObject: $0) }
  }
}


// MARK: - Box

open class KeyValueCodingBox<T> : KeyValueCodingTargetValue {
  
  public final var value : T
  
  @inlinable
  public init(_ value : T) {
    self.value = value
  }
  
  @inlinable
  public func setValue(_ value: Any?) throws {
    // TODO: more type coercion
    if let v = value as? T {
      self.value = v
    }
    else {
      throw KeyValueCoding.Error.CannotCoerceValue(T.self, value)
    }
  }
}
