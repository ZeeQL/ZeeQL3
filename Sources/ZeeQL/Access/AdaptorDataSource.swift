//
//  AdaptorDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * This datasource operates at the adaptor level, that is, it does not return
 * DatabaseObject instances but plain records.
 *
 * Important: If a model is set in the adaptor, the Map will contain mapped
 * keys! (the keys of the Map are the attribute names in the model, NOT the
 * column names in the database). Unless of course you specify 'rawrows' in
 * the FetchSpecification.
 *
 * THREAD: this class is for use in one thread.
 */
open class AdaptorDataSource : AccessDataSource<AdaptorRecord> {
  // TBD: do we need a way to initialize a datasource with an EOAdaptorChannel?
  
  let adaptor : Adaptor
  let _entity : Entity?
  
  public init(adaptor: Adaptor, entity: Entity? = nil) {
    self.adaptor = adaptor
    self._entity = entity
  }

  override open var entity : Entity? {
    if let entity = _entity { return entity } // set explicitly
    
    /* determine name of datasource entity */
    
    let ename : String
    if let entityName = entityName {
      ename = entityName
    }
    else if let fs = fetchSpecification, let entityName = fs.entityName {
      ename = entityName
    }
    else {
      return nil
    }
    
    /* retrieve model of adaptor */
    
    guard let model = adaptor.model else { return nil }
    return model[entity: ename]
  }

  override
  open func _primaryFetchObjects(_ fs: FetchSpecification,
                                 yield: ( AdaptorRecord ) throws -> Void) throws
  {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    /* This is the primary fetch method. Unfortunately AdaptorChannel
     * doesn't support incremental fetches yet, so we fetch the whole array
     * and build an iterator on top of that.
     */
    try channel.selectAttributes(nil, fs, lock: fs.locksObjects, entity) {
      try yield($0)
    }
  }
}
