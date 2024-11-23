//
//  AdaptorDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017-2020 ZeeZide GmbH. All rights reserved.
//

public protocol AdaptorDataSourceType: AccessDataSourceType
  where Object == AdaptorRecord
{
  var adaptor : Adaptor { get }
  
  init(adaptor: Adaptor, entity: Entity?)
}

public extension AdaptorDataSourceType {
  
  @inlinable
  init(adaptor: Adaptor) { self.init(adaptor: adaptor, entity: nil) }
  
  @inlinable
  func findEntity(for _entityName: String?) -> Entity? {
    let ename : String
    if let entityName = _entityName {
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
}

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
open class AdaptorDataSource : AccessDataSource<AdaptorRecord>,
                               AdaptorDataSourceType
{
  // TBD: do we need a way to initialize a datasource with an EOAdaptorChannel?
  
  public let adaptor : Adaptor
  let _entity : Entity?
  
  required public init(adaptor: Adaptor, entity: Entity?) {
    self.adaptor = adaptor
    self._entity = entity
  }

  override open var entity : Entity? {
    return _entity ?? findEntity(for: _entityName)
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
