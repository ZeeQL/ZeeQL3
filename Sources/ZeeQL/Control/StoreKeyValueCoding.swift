//
//  StoreKeyValueCoding.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * Stored KVC avoids calling extra logic applied when calling regular KVC.
 *
 * Conceptually it just reverses the key lookup path of KVC, that is, instead of
 * 1. check for set/get method
 * 2. check for instance var
 * It does the reverse
 * 1. check for instance var
 * 2. check for set/get method
 *
 * That is the idea. Not sure how to apply it to Swift :-)
 */
public protocol StoreKeyValueCodingType
                  : KeyValueCodingType, MutableKeyValueCodingType
{

  func storedValueForKey(_ k: String) -> Any?
  func takeStoredValue(_ v: Any?, forKey k: String)

}

public extension StoreKeyValueCodingType {

  @inlinable
  func takeStoredValue(_ v: Any?, forKey k: String) {
    fatalError("not implemented: \(#function)")
  }
  
}

public extension StoreKeyValueCodingType {
  
  @inlinable
  func storedValueForKey(_ k: String) -> Any? {
    return StoreKeyValueCoding.defaultStoredValueForKey(k, inObject: self)
  }

  @inlinable
  func takeStoredValues(_ values : [ String : Any? ]) {
    for ( key, value ) in values {
      takeStoredValue(value, forKey: key)
    }
  }
  @inlinable
  func storedValuesForKeys(_ keys: [ String ]) -> [ String : Any? ] {
    var values = [ String : Any? ]()
    for key in keys {
      values[key] = storedValueForKey(key)
    }
    return values
  }
}

public struct StoreKeyValueCoding {

  @inlinable
  public static func storedValueForKey(_ k: String, inObject o: Any?) -> Any? {
    if let kvc = o as? StoreKeyValueCodingType {
      return kvc.storedValueForKey(k)
    }
    return defaultStoredValueForKey(k, inObject: o)
  }

  @inlinable
  public static func defaultStoredValueForKey(_ k: String, inObject o: Any?)
                     -> Any?
  {
    (o as? KeyValueCodingType)?.valueForKey(k)
  }

}
