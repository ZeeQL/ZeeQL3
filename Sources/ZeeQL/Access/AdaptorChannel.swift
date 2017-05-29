//
//  AdaptorChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Adaptor channels represent database connections. Usually subclassed by
 * specific adaptors (e.g. there is a SQLite3AdaptorChannel) to implement
 * the operations.
 */
public protocol AdaptorChannel : AdaptorQueryType, ModelNameMapper {
  
  var expressionFactory : SQLExpressionFactory { get }
  
  // MARK: - Model Queries
  
  func evaluateQueryExpression(_ sqlexpr  : SQLExpression,
                               _ optAttrs : [ Attribute ]?,
                               result: ( AdaptorRecord ) throws -> Void) throws

  func evaluateUpdateExpression(_ sqlexpr  : SQLExpression) throws -> Int

  
  // MARK: - Transactions
  
  func begin()    throws
  func commit()   throws
  func rollback() throws
  var isTransactionInProgress : Bool { get }

  
  // MARK: - Reflection
  // TBD: this should rather be part of the adaptor? No need to subclass just
  //      to run custom SQL
  
  func describeTableNames()    throws -> [ String ]
  func describeSequenceNames() throws -> [ String ]
  func describeDatabaseNames() throws -> [ String ]
  func describeEntityWithTableName(_ table: String) throws -> Entity?

  
  // MARK: - Adaptor Operations
  
  func performAdaptorOperations(_ ops : [ AdaptorOperation ]) throws
  func performAdaptorOperation (_ op  : AdaptorOperation)     throws
  
  
  // MARK: - Operations
  
  /**
   * Locks the database row using the specified criterias. This performs a
   * select with a HOLD LOCK option.
   *
   * - parameters:
   *   - attrs:     the attributes to be fetched, or null to use the entity
   *   - entity:    the entity (usually the table) to be fetched
   *   - qualifier: the qualifier used to select the rows to be locked
   *   - snapshot:  a set of keys/values specifying a row to be locked
   */
  func lockRowComparingAttributes(_ attrs     : [ Attribute ]?,
                                  _ entity    : Entity,
                                  _ qualifier : Qualifier?,
                                  _ snapshot  : AdaptorRow?) throws
       -> Bool

  /**
   * This method fetches a set of database rows according to the specification
   * elements given. The method performs the name mappings specified in the
   * model by using the adaptors expressionFactory.
   *
   * Most parameters of the method are optional or optional in certain
   * combinations. For example if no attributes are specified, all the
   * attributes of the entity will be used (/fetched).
   *
   * Note: to perform a simple SQL query w/o any model mapping, the performSQL()
   * method is available.
   * 
   * - parameters:
   *   - attrs: the attributes to be fetched, or null to use the entity
   *   - fs:    the fetchspecification (qualifier/sorting/etc) to be used
   *   - lock:  whether the SELECT should include a HOLD LOCK
   *   - e:     the entity (usually the table) to be fetched
   */
  func selectAttributes(_ attrs : [ Attribute ]?,
                        _ fs    : FetchSpecification?,
                        lock    : Bool,
                        _ e     : Entity?,
                        result  : ( AdaptorRecord ) throws -> Void) throws

  /**
   * This method creates a SQLExpression which represents the UPDATE and
   * then calls evaluateUpdateExpression to perform the SQL.
   * 
   * - parameters:
   *   - values:    the values to be changed
   *   - qualifier: the qualifier which selects the rows to be updated
   *   - entity:    the entity which should be updated
   * - returns: number of affected rows or -1 on error
   */
  func updateValuesInRowsDescribedByQualifier(_ values    : AdaptorRow,
                                              _ qualifier : Qualifier,
                                              _ entity    : Entity) throws
       -> Int
  
  func deleteRowsDescribedByQualifier(_ q: Qualifier, _ e: Entity) throws -> Int

  /**
   * This method works like deleteRowsDescribedByQualifier() but only returns
   * true if exactly one row was affected by the DELETE.
   *
   * - parameters:
   *   - qualifier: the qualifier to select exactly one row to be deleted
   *   - entity:    the entity which contains the row
   * - returns:     true if exactly one row was deleted, false otherwise
   */
  func deleteRowDescribedByQualifier(_ qualifier: Qualifier, _ entity: Entity)
         throws -> Bool
  
  /**
   * This method inserts the given row into the table represented by the entity.
   * To produce the INSERT statement it uses the expressionFactory() of the
   * adaptor. The keys in the record map are converted to column names by using
   * the Entity.
   * The method returns true if exactly one row was affected by the SQL
   * statement. If the operation failed the error is thrown.
   *
   * - parameters:
   *   - row:        the record which should be inserted
   *   - entity:     the entity representing the table
   *   - refetchAll: the SQL schema may have default values assigned which are
   *                 applied if the corresponding values are not in 'row'.
   *                 Enabling 'refetchAll' makes sure all attributes of the
   *                 entity are being refetched. Requires the entity!
   * - returns:  the record, potentially refetched and updated
   */
  func insertRow(_ row: AdaptorRow, _ entity: Entity?, refetchAll: Bool) throws
       -> AdaptorRow
}

public protocol ModelNameMapper {
  
  func entityNameForTableName    (_ tableName : String) -> String
  func attributeNameForColumnName(_ colName   : String) -> String
  
}

public extension AdaptorChannel { // transactions, naive default imp

  func begin() throws {
    try performSQL("BEGIN TRANSACTION;")
  }
  func commit() throws {
    try performSQL("COMMIT TRANSACTION;")
  }
  func rollback() throws {
    try performSQL("ROLLBACK TRANSACTION;")
  }
  
  var isTransactionInProgress : Bool { return false }
  
}

public extension AdaptorChannel {
  
  // MARK: - Adaptor Operations

  /**
   * Currently this just calls performAdaptorOperation() on each of the given
   * operations. It stops on the first error.
   *
   * Later we might want to group similiar operations to speed up database
   * operations (useful for bigger inserts/deletes/updated).
   * E.g. combine deletes on the same entity into a single delete.
   * 
   * - parameters:
   *   - ops: the array of AdaptorOperation's to be performed
   */
  func performAdaptorOperations(_ ops: [ AdaptorOperation ]) throws {
    // TBD: we should probably open a transaction if count > 1? Or is this the
    //      responsibility of the user?
    
    // We could create update-batches for
    // changes which are the same.
    // TBD: we could group operations writing to the same table and possibly
    //      use a single prepared statement
    // This requires that the database checks constraints at the end of the
    // transaction, which AFAIK is an issue with M$SQL, possibly with Sybase.
    
    // TBD: deletes on the same table can be collapsed?! (join qualifier by
    //      OR)
    
    let didOpenTx = !isTransactionInProgress && ops.count > 1
    if didOpenTx { try begin() }
    
    do {
      for op in ops {
        try performAdaptorOperation(op)
      }
    }
    catch {
      if didOpenTx { try? rollback() } // throw the other error
      throw error
    }
    
    if didOpenTx { try commit() }
  }

  /**
   * This calls performAdaptorOperationN() and returns a success (null) when
   * exactly one row was affected.
   * 
   * - parameters:
   *   - op: the `AdaptorOperation` object
   */
  func performAdaptorOperation(_ op: AdaptorOperation) throws {
    let affectedRows = try performAdaptorOperationN(op)
    guard affectedRows == 1 else {
      throw AdaptorChannelError.OperationDidNotAffectOne
    }
  }

  /**
   * This methods calls lockRow..(), insertRow(), updateValuesInRows..()
   * or deleteRowsDescri...() with the information contained in the operation
   * object.
   *
   * This method is different to performAdaptorOperation() [w/o 'N' ;-)]
   * because it returns the count of affected objects (eg how many rows got
   * deleted or updated).
   */
  func performAdaptorOperationN(_ op: AdaptorOperation) throws -> Int {
    // TBD: we might want to move evaluation to this method and make
    // updateValuesInRows..() etc create AdaptorOperation's. This might
    // easen the creation of non-SQL adaptors.
    
    let affectedRows : Int
    
    defer {
      if let cb = op.completionBlock {
        op.completionBlock = nil
        cb()
      }
    }
    
    switch op.adaptorOperator {
      case .lock:
        let ok = try lockRowComparingAttributes(op.attributes, op.entity,
                                                op.qualifier,
                                                op.changedValues)
        affectedRows = ok ? 1 : 0 /* a bit hackish? */
      
      case .insert:
        guard let values = op.changedValues
         else { throw AdaptorChannelError.MissingRecordToInsert }

        // Note: we trigger a full refetch
        op.resultRow =
          try insertRow(values, op.entity,
                        refetchAll: op.entity.shouldRefetchOnInsert)
        affectedRows = 1
    
      case .update:
        guard let values = op.changedValues
         else { throw AdaptorChannelError.MissingRecordToUpdate }
        guard let q = op.qualifier
         else { throw AdaptorChannelError.MissingQualification }
        
        affectedRows = try updateValuesInRowsDescribedByQualifier(values,
                                                                  q, op.entity)
      
      case .delete:
        guard let q = op.qualifier
         else { throw AdaptorChannelError.MissingQualification }
        
        affectedRows = try deleteRowsDescribedByQualifier(q, op.entity)
      
      case .none:
        throw AdaptorChannelError.UnexpectedOperation
    }
    
    return affectedRows
  }
  
}

public typealias AdaptorRow = Dictionary<String, Any?>

public extension AdaptorChannel {
  // MARK: - Operations

  /**
   * Locks the database row using the specified criterias. This performs a
   * select with a HOLD LOCK option. 
   * 
   * - parameters:
   *   - attrs:     the attributes to be fetched, or null to use the entity
   *   - entity:    the entity (usually the table) to be fetched
   *   - qualifier: the qualifier used to select the rows to be locked
   *   - snapshot:  a set of keys/values specifying a row to be locked
   */
  public func lockRowComparingAttributes(_ attrs     : [ Attribute ]?,
                                         _ entity    : Entity,
                                         _ qualifier : Qualifier?,
                                         _ snapshot  : AdaptorRow?) throws
              -> Bool
  {
    let q  = snapshot != nil ? qualifierToMatchAllValues(snapshot!) : nil
    let fs = ModelFetchSpecification(entity: entity,
                                     qualifier: and(q, qualifier))
  
    var resultCount = 0 // TODO: no way to stop :-)
    try selectAttributes(attrs, fs, lock: true, entity) { record in
      resultCount += 1
    }
    guard resultCount == 1 else { return false }
      // more or less rows matched
    
    return true
  }

  /**
   * This method fetches a set of database rows according to the specification
   * elements given. The method performs the name mappings specified in the
   * model by using the adaptors expressionFactory.
   *
   * Most parameters of the method are optional or optional in certain
   * combinations. For example if no attributes are specified, all the
   * attributes of the entity will be used (/fetched).
   *
   * Note: to perform a simple SQL query w/o any model mapping, the performSQL()
   * method is available.
   * 
   * - parameters:
   *   - attrs: the attributes to be fetched, or null to use the entity
   *   - fs:    the fetchspecification (qualifier/sorting/etc) to be used
   *   - lock:  whether the SELECT should include a HOLD LOCK
   *   - e:     the entity (usually the table) to be fetched
   */
  public func selectAttributes(_ attrs : [ Attribute ]?,
                               _ fs    : FetchSpecification?,
                             lock    : Bool,
                             _ e     : Entity?,
                             result  : ( AdaptorRecord ) throws -> Void) throws
  {
    /* This is called by the DatabaseChannel
     *   selectObjectsWithFetchSpecification(fs)
     */
    let attributes : [ Attribute ]
    
    /* complete parameters */
    
    if let attrs = attrs {
      attributes = attrs
    }
    else if let entity = e {
      if let fs = fs, let an = fs.fetchAttributeNames {
        attributes = entity.attributesWithNames(an)
      }
      else {
        attributes = entity.attributes
      }
    }
    else {
      attributes = []
    }
    
    /* build SQL */
    
    let expr = expressionFactory
                 .selectExpressionForAttributes(attributes, lock: lock, fs, e)
    
    /* rawrows only relates to what is returned to the caller, NOT how the
     * SQL expression is built. The SQL expression can still use mapped attrs
     * and what else SQLExpression provides.
     * Sample model:
     *
     *     <fetch name="xx" flags="readonly,rawrows,allbinds">
     *       <attributes>objectId</attributes>
     *       <qualifier>objectId IN $ids</qualifier>
     *       <sql>
     *         %(select)s %(columns)s FROM %(tables)s %(where)s GROUP BY obj_id;
     *       </sql>
     */
    let isRawFetch = fs?.fetchesRawRows ?? true
    
    /* perform fetch */
    // TODO: do the mapping inline
    
    var rows = [ AdaptorRecord ]()
    try evaluateQueryExpression(expr, isRawFetch ? nil : attributes) { record in
      if isRawFetch { // no SQL name to Entity name mapping for rawrows
        try result(record)
      }
      else { // collect
        rows.append(record)
      }
    }
  
    if isRawFetch { // no SQL name to Entity name mapping for rawrows
      return // already fed results
    }
    if rows.isEmpty {
      return
    }
  
    
    /* map row names */
    
    let attributesToMap = attributesWhichRequireRowNameMapping(attributes)
    if !attributesToMap.isEmpty {
      // hack schema
      // TBD: We could also set a new, mapped, schema in all rows. But that sounds
      //      more expensive.
      let anyRow = rows[0]
      let schema = anyRow.schema
      for a in attributesToMap {
        schema.switchKey(columnNameForAttribute(a),
                         to: a.name) // TODO: column-name-deriver
      }
    }
    
    for record in rows {
      try result(record)
    }
  }
  
  func columnNameForAttribute(_ a: Attribute) -> String {
    if let c = a.columnName { return c }
    // TODO: derive column-name based on some configurable algorithm, e.g.
    //       'personId' => 'person_id'. Simple closure?
    return a.name
  }
  
  /**
   * This method creates a SQLExpression which represents the UPDATE and
   * then calls evaluateUpdateExpression to perform the SQL.
   * 
   * - parameters:
   *   - values:    the values to be changed
   *   - qualifier: the qualifier which selects the rows to be updated
   *   - entity:    the entity which should be updated
   * - returns: number of affected rows or -1 on error
   */
  public
  func updateValuesInRowsDescribedByQualifier(_ values    : [ String: Any? ],
                                              _ qualifier : Qualifier,
                                              _ entity    : Entity) throws
       -> Int
  {
    let expr =
          expressionFactory.updateStatementForRow(values, qualifier, entity)
    return try evaluateUpdateExpression(expr)
  }
  
  public func deleteRowsDescribedByQualifier(_ q: Qualifier, _ e: Entity) throws
              -> Int
  {
    let expr = expressionFactory.deleteStatementWithQualifier(q, e)
    return try evaluateUpdateExpression(expr)
  }

  /**
   * This method works like deleteRowsDescribedByQualifier() but only returns
   * true if exactly one row was affected by the DELETE.
   *
   * - parameters:
   *   - qualifier: the qualifier to select exactly one row to be deleted
   *   - entity:    the entity which contains the row
   * - returns:     true if exactly one row was deleted, false otherwise
   */
  public func deleteRowDescribedByQualifier(_ qualifier : Qualifier,
                                            _ entity    : Entity) throws
              -> Bool
  {
    return try deleteRowsDescribedByQualifier(qualifier, entity) == 1
  }
  
  /**
   * This method inserts the given row into the table represented by the entity.
   * To produce the INSERT statement it uses the expressionFactory() of the
   * adaptor. The keys in the record map are converted to column names by using
   * the Entity.
   * The method returns true if exactly one row was affected by the SQL
   * statement. If the operation failed the error is thrown.
   *
   * - parameters:
   *   - row:        the record which should be inserted
   *   - entity:     the entity representing the table
   *   - refetchAll: the SQL schema may have default values assigned which are
   *                 applied if the corresponding values are not in 'row'.
   *                 Enabling 'refetchAll' makes sure all attributes of the
   *                 entity are being refetched. Requires the entity!
   * - returns:  the record, potentially refetched and updated
   */
  public func insertRow(_ row: AdaptorRow, _ entity: Entity?,
                        refetchAll: Bool)
                throws -> AdaptorRow
  {
    return try defaultInsertRow(row, entity, refetchAll: refetchAll)
  }
  
  public func defaultInsertRow(_ row: AdaptorRow, _ entity: Entity?,
                               refetchAll: Bool)
                throws -> AdaptorRow
  {
    // So that we can reuse the default implementation ...
    if refetchAll && entity == nil {
      throw AdaptorError.InsertRefetchRequiresEntity
    }
    
    let expr = expressionFactory.insertStatementForRow(row, entity)
    
    guard try evaluateUpdateExpression(expr) == 1 else {
      throw AdaptorError.OperationDidNotAffectOne
    }
    
    guard let entity = entity else {
      // Note: we don't know the pkey w/o entity and we don't want to reflect in
      //       here
      return row
    }

    if let pkey = entity.primaryKeyForRow(row) {
      // already had the pkey assigned
      // TODO: properly refetch in a transaction
      return refetchAll ? row : pkey
    }
    
    throw AdaptorError.FailedToGrabNewPrimaryKey(entity: entity, row: row)
  }

  /**
   * This method inserts the given row into the table represented by the entity.
   * To produce the INSERT statement it uses the expressionFactory() of the
   * adaptor. The keys in the record map are converted to column names by using
   * the Entity.
   * The method returns true if exactly one row was affected by the SQL
   * statement. If the operation failed the error is thrown.
   *
   * - parameters:
   *   - row:    the record which should be inserted
   *   - entity: optionally an entity representing the table
   * - returns:  the record, potentially refetched and updated
   */
  public func insertRow(_ row: AdaptorRow, _ entity: Entity? = nil) throws
              -> AdaptorRow
  {
    return try insertRow(row, entity, refetchAll: entity != nil)
  }
}

extension AdaptorChannel {

  // MARK: - attribute name mapping
  
  /**
   * Scans the given array for attributes whose name does not match their
   * external name (the database column).
   * 
   * - parameters:
   *   - attributes: the attributes array to be checked
   * - returns: an array of attributes which need to be mapped
   */
  func attributesWhichRequireRowNameMapping(_ attributes: [ Attribute ])
       -> [ Attribute ]
  {
    guard !attributes.isEmpty else { return [] }
    
    return attributes.filter { attribute in
      let attrname = attribute.name
      guard let colname = attribute.columnName else { return false }
      return attrname != colname
    }
  }
  
}

public extension AdaptorChannel { // Utility

  /* utility */
  
  func fetchSingleStringRows(_ _sql: String, column: String) throws
       -> [ String ]
  {
    var values = [ String ]()
    
    try querySQL(_sql) { record in
      if let v = record[column] as? String {
        values.append(v)
      }
    }
    
    return values
  }
}

public extension AdaptorChannel {
  
  func entityNameForTableName(_ tableName : String) -> String {
    return tableName
  }

  func attributeNameForColumnName(_ colName   : String) -> String {
    return colName
  }
  
  func describeModelWithTableNames(_ tableNames : [ String ]) throws -> Model? {
    guard !tableNames.isEmpty else { return nil }
    
    var entities = [ Entity ]()
    entities.reserveCapacity(tableNames.count)
    
    for table in tableNames {
      guard let entity = try describeEntityWithTableName(table)
       else { return nil }
      
      entities.append(entity)
    }
   
    return Model(entities: entities)
  }
}
