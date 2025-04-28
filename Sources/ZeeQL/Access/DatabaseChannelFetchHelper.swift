//
//  DatabaseChannelFetchHelper.swift
//  ZeeQL
//
//  Created by Helge Heß on 28.04.25.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
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
  // TODO: fix abuse of GlobalID, workaround for Hashable-limitations
  // ^^ hh: what?
  
  /// The contains the database objects we want to fetch relationships for.
  let baseObjects             : [ DatabaseObject ]
  
  /// This is a map from the join key in the base objects, e.g. `id` to the
  /// the global ID's of those objects.
  var sourceKeyToValues       = [ String : [ GlobalID ] ]()
  
  /// This is a map from the join key in the base objects, e.g. `id` to the
  /// the actual ``DatabaseObject``'s.
  var sourceKeyToValueObjects = [ String : [ GlobalID : [ DatabaseObject ] ] ]()
  
  init(baseObjects: [ DatabaseObject ]) {
    self.baseObjects = baseObjects
  }
  
  func getSourceValues(_ srcName: String) -> [ GlobalID ] {
    if let result = sourceKeyToValues[srcName] { return result }

    fill(srcName)
    return sourceKeyToValues[srcName] ?? []
  }
  
  func getValueToObjects(_ srcName: String)
       -> [ GlobalID : [ DatabaseObject ] ]
  {
    if let result = sourceKeyToValueObjects[srcName] { return result }
    
    fill(srcName)
    return sourceKeyToValueObjects[srcName] ?? [:]
  }
  
  func fill(_ srcName: String) {
    guard !baseObjects.isEmpty else { return }
    
    /* not yet cached, calculate */
    var srcValues      = [ GlobalID ]()
    var valueToObjects = [ GlobalID : [ DatabaseObject ] ]()
    
    
    /* calculate */

    for baseObject in baseObjects {
      // The srcName is the value for the join in the baseObjects entity.
      
      // TBD: which one? storedValue(forKey:) or value(forKey:)?
      guard let rv = baseObject.storedValue(forKey: srcName) else { continue }
      // guard let rv = baseObject.value(forKey: srcName) else { continue }
      
      guard let v = hackValueHolder(rv) else { // TBD: do we know the entity?
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

func hackValueHolder(_ value : Any?) -> GlobalID? {
  // Swift GID hack
  // 2025-04-28: What does it hack? I think getting GID's?
  //             They could have the entityName?
  guard let rv = value else { return nil }
  
  if let gid = rv as? GlobalID { return gid }
  if let i   = rv as? Int {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: i)
  }
  if let i   = rv as? Int64 {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: Int(i))
  }
  if let i   = rv as? Int32 {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: Int(i))
  }
  fatalError("cannot process join value: \(rv)")
}
