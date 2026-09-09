//
//  DatabaseChannelFetchHelper.swift
//  ZeeQL
//
//  Created by Helge Heß on 28.04.25.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * This helper class manages prefetches of relationships.
 *
 * For example if you fetch account objects, that have a relationship to
 * their person, which in turn has a relationship to the person's emails and
 * addresses.
 * A prefetch might look like:
 * ```swift
 * OGoAccount()
 *   .prefetch("person.emails", "person.addresses")
 * ```
 *
 * The helper does organize a fetch for ONE level, e.g. `person` in this case.
 */
class DatabaseChannelFetchHelper {
  
  /// The contains the database objects we want to fetch relationships for.
  let baseObjects             : [ DatabaseObject ]
  
  /// Maps a join attribute, e.g. `id`, to its distinct hashable values.
  var sourceKeyToValues       = [ String : [ AnyHashable ] ]()
  
  /// Maps a join attribute and value to the matching ``DatabaseObject``'s.
  var sourceKeyToValueObjects =
    [ String : [ AnyHashable : [ DatabaseObject ] ] ]()
  
  init(baseObjects: [ DatabaseObject ]) {
    self.baseObjects = baseObjects
  }
  
  func getSourceValues(_ srcName: String) throws -> [ AnyHashable ] {
    if let result = sourceKeyToValues[srcName] { return result }

    try fill(srcName)
    return sourceKeyToValues[srcName] ?? []
  }
  
  func getValueToObjects(_ srcName: String)
    throws -> [ AnyHashable : [ DatabaseObject ] ]
  {
    if let result = sourceKeyToValueObjects[srcName] { return result }
    
    try fill(srcName)
    return sourceKeyToValueObjects[srcName] ?? [:]
  }
  
  func fill(_ srcName: String) throws {
    guard !baseObjects.isEmpty else { return }
    
    /* not yet cached, calculate */
    var srcValues      = [ AnyHashable ]()
    var valueToObjects = [ AnyHashable : [ DatabaseObject ] ]()
    
    
    /* calculate */

    for baseObject in baseObjects {
      // The srcName is the value for the join in the baseObjects entity.
      
      // TBD: which one? storedValueForKey or valueForKey?
      guard let rv = baseObject.storedValueForKey(srcName) else { continue }
      // guard let rv = baseObject.valueForKey(srcName) else { continue }
      
      guard let v = try prefetchJoinKey(rv) else {
        continue
      }
      
      /* Most often the source key is unique and we have just one
       * entry, but its not a strict requirement
       */
      var vobjects = valueToObjects[v] ?? []
      vobjects.append(baseObject)
      valueToObjects[v] = vobjects
      
      /* Note: we could also use vobjects.keySet() */
      if !srcValues.contains(v) {
        srcValues.append(v)
      }
    }
    
    sourceKeyToValues[srcName ]      = srcValues
    sourceKeyToValueObjects[srcName] = valueToObjects
  }

}

func prefetchJoinKey(_ value: Any?) throws -> AnyHashable? {
  guard let value else { return nil }
  guard let key = value as? AnyHashable else {
    throw DatabaseChannelError.unsupportedPrefetchJoinValue(type(of: value))
  }
  return key
}
