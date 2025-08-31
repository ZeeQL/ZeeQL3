//
//  SQLExpression.swift
//  ZeeQL
//
//  Created by Helge Heß on 18.02.17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.Date
import struct Foundation.DateInterval

/**
 * This class is used to generate adaptor specific SQL. Usually for mapped
 * qualifiers and records (but it also works for 'raw' values if the entity is
 * missing).
 *
 * For example this class maps ``Qualifier``'s to their SQL representation. This
 * requires proper quoting of values and mapping of attribute names to columns
 * names.
 *
 * The final generation (prepare...) is triggered by the ``AdaptorChannel`` when
 * it is asked to perform an adaptor operation.
 * It turns the ``AdaptorOperation`` into a straight method call (e.g.
 * ``AdaptorChannel/selectAttributes(_:_:lock:_:result:)``) which in turn uses
 * the ``SQLExpressionFactory`` to create and prepare an expression.
 *
 * ## Raw SQL Patterns
 *
 * If the ``SQLExpression/CustomQueryExpressionHintKey`` is set, the value of
 * this key is processed as a keyvalue-format pattern to produce the SQL.
 * ``SQLExpression`` will still prepare and provide the parts of the SQL (e.g.
 * qualifiers, sorts), but the assembly will be done using the SQL pattern.
 *
 * Example:
 * ```sql
 * SELECT COUNT(*) FROM %(tables)s %(where)s %(limit)s
 * ```
 *
 * Keys:
 * ```
 * | select       | eg SELECT or SELECT DISTINCT
 * | columns      | eg BASE.lastname, BASE.firstname
 * | tables       | eg BASE.customer
 * | basetable    | eg customer
 * | qualifier    | eg lastname LIKE 'Duck%'
 * | orderings    | eg lastname ASC, firstname DESC
 * | limit        | eg OFFSET 0 LIMIT 1
 * | lock         | eg FOR UPDATE
 * | joins        |
 * ```
 *
 * Compound:
 * ```
 * | where        | eg WHERE lastname LIKE 'Duck%'
 * | andQualifier | eg AND lastname LIKE 'Duck%'   (nothing w/o qualifier)
 * | orQualifier  | eg OR  lastname LIKE 'Duck%'   (nothing w/o qualifier)
 * | orderby      | eg ORDER BY mod_date DESC (nothing w/o orderings)
 * | andOrderBy   | eg mod_date DESC (nothing w/o orderings)
 * ```
 *
 * Note: parts which involve bind variables (e.g. `andQualifier`) can only be
 *       used *ONCE*! This is because the bindings are generated only once, but
 *       the `?` in the SQL are generated multiple times. Hence the
 *       PreparedStatement will report that not all '?' bindings are set!
 *       (TBD: fix me, make generation dynamic)
 *
 *
 * ## How it works
 *
 * The main methods are the four prepare.. methods:
 * - ``prepareSelectExpressionWithAttributes(_:_:_:)``
 * - ``prepareUpdateExpressionWithRow(_:_:)``
 * - ``prepareInsertExpressionWithRow(_:)``
 * - ``prepareDeleteExpressionFor(qualifier:)``
 * Those methods are usually called by the ``SQLExpressionFactory``, which first
 * allocates the ``SQLExpression`` subclass (as provided by the specific
 * database adaptor subclass) and calls the prepare... method.
 */
open class SQLExpression: SmartDescription {
  // TODO(Swift): Maybe mark stuff as throws and throw generation errors.
  //              This would avoid some nil-values.
  // TODO(Swift): Naming.
  
  public static let CustomQueryExpressionHintKey =
                      "CustomQueryExpressionHintKey"
  public final let BaseEntityPath  = ""
  public final let BaseEntityAlias = "BASE"
  
  open var log : ZeeQLLogger = globalZeeQLLogger
  
  public var statement = "" // SQL result
  
  public let entity           : Entity?
  public var listString       = ""
  public var valueList        = ""
  
  /**
   * Contains the list of bindings which got created during SQL construction. A
   * bind dictionary contains such keys:
   *
   * - `BindVariableAttributeKey`   - the Attribute object
   * - `BindVariablePlaceHolderKey` - the placeholder used in the SQL (eg '?')
   * - `BindVariableNameKey`        - the name which is bound
   *
   * @return a List of bind records.
   */
  public struct BindVariable {
    public var attribute   : Attribute? = nil
    public var placeholder = "?"
    public var name        = ""
    public var value       : Any?   = nil
    
    public init() {}
  }
  public var bindVariables = [ BindVariable ]()
  
  public var useAliases       = false // only true for selects
  public var useBindVariables = false
  
  var relationshipPathToAlias        = [ String : String ]()
  var relationshipPathToRelationship = [ String : Relationship ]()
  var joinClauseString               = ""
  
  /* transient state */
  var qualifier : Qualifier?
  
  public init(entity: Entity? = nil) {
    self.entity = entity
    
    if entity != nil {
      relationshipPathToAlias[BaseEntityPath] = BaseEntityAlias
    }
  }
  
  
  /* preparation and assembly */
  
  open func prepareDeleteExpressionFor(qualifier q: Qualifier) {
    guard let entity = self.entity else { return } // required
    
    useAliases = false
    qualifier  = q
    
    /* where */
    
    guard let whereClause = whereClauseString else {
      log.error("got no whereClause despite qualifier?!", q)
      return
    }
    
    /* table list */
    
    let table = sqlStringFor(schemaObjectName: entity.externalName
                                               ?? entity.name)
    
    /* assemble */
    
    statement = assembleDeleteStatementWithQualifier(q, table, whereClause)
    
    /* tear down */
    qualifier = nil
  }
  open func assembleDeleteStatementWithQualifier(_ q           : Qualifier,
                                                 _ tableList   : String,
                                                 _ whereClause : String)
            -> String
  {
    return "DELETE FROM \(tableList) WHERE \(whereClause)"
  }
  
  /**
   * This method calls addInsertListAttribute() for each key/value in the given
   * row. It then builds the table name using tableListWithRootEntity().
   * And finally calls assembleInsertStatementWithRow() to setup the final
   * SQL.
   *
   * The result is stored in the 'self.statement' ivar.
   *
   * - Parameters:
   *   - row: The keys/values to INSERT
   */
  open func prepareInsertExpressionWithRow(_ row: AdaptorRow) {
    // TODO: add method to insert multiple rows
    
    // Note: we need the entity for the table name ...
    guard let entity = entity else {
      assertionFailure("SQLExpression is missing entity for row-INSERT")
      return
    }
    
    useAliases = false
    
    /* fields and values */
    
    for ( attr, value ) in row.attributesAndValues(in: entity) {
      if let value = value {
        addInsertListAttribute(attr, value: value)
      }
      else {
        addInsertListAttribute(attr, value: nil)
      }
    }
    
    /* table list */
    
    let tables = tableListWith(rootEntity: entity)
    
    /* assemble */
    
    statement =
      assembleInsertStatementWithRow(row, tables, listString, valueList)
  }
  
  func assembleInsertStatementWithRow(_ row        : AdaptorRow,
                                      _ tableList  : String,
                                      _ columnList : String?,
                                      _ valueList  : String)
       -> String
  {
    var sb = "INSERT INTO \(tableList)"
    if let cl = columnList { sb += " ( \(cl) )" }
    sb += " VALUES ( \(valueList) )"
    return sb
  }

  /**
   * Method to assemble multi-row inserts. Subclasses might onverride that to
   * generate multiple INSERT statements separated by a semicolon.
   *
   * In PostgreSQL this is available with 8.2.x, the syntax is:
   * ```sql
   * INSERT INTO Log ( a, b ) VALUES (1,2), (3,4), (5,6);
   * ```
   *
   * @param rows        - list of rows to insert
   * @param _tableList  - SQL table reference (eg 'address')
   * @param _columnList - SQL list of columns (eg 'firstname, lastname')
   * @param _valueLists - SQL list of values
   * @return assembles SQL, or null if there where no values
   */
  open func assembleInsertStatementWithRows(_ rows       : [ AdaptorRow ],
                                            _ tableList  : String,
                                            _ columnList : String?,
                                            _ valueLists : [ String ])
            -> String?
  {
    guard !valueLists.isEmpty else { return nil }
      // hm, PG also allows: INSERT INTO a DEFAULT VALUES;
    
    var sb = "INSERT INTO \(tableList)"
    if let cl = columnList { sb += " ( \(cl) )" }
    sb += " VALUES "
    
    var isFirst = true
    for v in valueLists {
      guard !v.isEmpty else { continue }
      if isFirst { isFirst = false }
      else { sb += ", " }
      
      sb += "( \(v) )"
    }
    return sb
  }
  
  open func prepareUpdateExpressionWithRow(_ row : AdaptorRow,
                                           _ q   : Qualifier)
  {
    guard !row.isEmpty else {
      log.error("missing row for update ...")
      statement.removeAll()
      return
    }
    guard let entity = entity else { return }
    
    useAliases = false
    qualifier  = q
    
    /* fields and values */
    /* Note: needs to be done _before_ the whereClause, so that the ordering of
     *       the bindings is correct.
     */
    for ( attr, value ) in row.attributesAndValues(in: entity) {
      if let value = value {
        addUpdateListAttribute(attr, value: value)
      }
      else {
        addUpdateListAttribute(attr, value: nil)
      }
    }
    
    /* where */
    
    guard let whereClause = whereClauseString else {
      log.error("got no where clause despite qualifier?!", q)
      return
    }
    
    /* table list */
    
    let tables = tableListWith(rootEntity: entity)
    
    /* assemble */
    
    statement = assembleUpdateStatementWithRow(row, q, tables, listString,
                                               whereClause)
    
    /* tear down */
    qualifier = nil
  }
  
  open func assembleUpdateStatementWithRow(_ row    : AdaptorRow,
                                           _ q      : Qualifier,
                                           _ table  : String,
                                           _ vals   : String,
                                           _ _where : String) -> String
  {
    var sb = "UPDATE \(table) SET \(vals)"
    if !_where.isEmpty { sb += " WHERE \(_where)" }
    return sb
  }
  
  /**
   * The primary entry point to create SQL SELECT expressions. Its usually
   * called by the SQLExpressionFactory after it instantiated an adaptor
   * specific SQLExpression class.
   *
   * What this method does:
   *
   * - checks for the CustomQueryExpressionHintKey
   * - conjoins the `restrictingQualifier` of the ``Entity`` with the one of the
   *   ``FetchSpecification``
   * - builds the select prefix (`SELECT, SELECT DISTINCT`) depending on the
   *   `usesDistinct` setting of the ``FetchSpecification``
   * - builds the list of columns by calling ``addSelectListAttribute(_:)`` with
   *   each ``Attribute`` given, or uses `*` if none are specified
   * - call `whereClauseString` to build the SQL `WHERE` expression, if
   *   relationships are used in the qualifiers, this will fill join related
   *   maps in the expression context (e.g. aliasesByRelationshipPath)
   * - builds sort orderings by calling ``addOrderByAttributeOrdering(_:)`` with
   *   each ``SortOrdering`` in the ``FetchSpecification``
   * - calls `joinClauseString` to create the SQL required for the JOINs
   *   to flatten relationships
   * - builds the list of tables
   * - builds lock and limit expressions
   * - finally assembles the statements using either
   *   ``assembleSelectStatementWithAttributes(_:_:_:_:_:_:_:_:_:_:_:_:)``
   *   or
   *   ``assembleCustomSelectStatementWithAttributes(_:_:_:_:_:_:_:_:_:_:_:_:_:)``.
   *   The latter is used if a `CustomQueryExpressionHintKey` was set.
   *
   * The result of the method is stored in the ``statement`` ivar.
   *
   * - Parameters:
   *   - attrs: The ``Attribute``'s to fetch, or null to fetch all (* SELECT).
   *   - lock:  Whether the rows/table should be locked in the database
   *   - fspec: The ``FetchSpecification`` containing the qualifier, etc
   */
  open func prepareSelectExpressionWithAttributes(_ attrs : [ Attribute ],
                                                  _ lock  : Bool,
                                                  _ fspec : FetchSpecification?)
  {
    /* check for custom statements */
    
    let customSQL =
          fspec?[hint: SQLExpression.CustomQueryExpressionHintKey] as? String
    
    useAliases = true
    qualifier  = fspec?.qualifier
    
    /* apply restricting qualifier */
    
    if let entity = entity,
       let restrictingQualifier = entity.restrictingQualifier
    {
      if let baseQualifier = qualifier {
        qualifier = baseQualifier.and(restrictingQualifier)
      }
      else {
        qualifier = restrictingQualifier
      }
    }
    
    /* check for distinct */
    
    let select = (fspec?.usesDistinct ?? false) ? "SELECT DISTINCT" : "SELECT"
    
    /* prepare columns to select */
    // TODO: Some database require that values used in the qualifiers and/or
    //       sort orderings are part of the SELECT. Support that.
    
    let columns : String
    if !attrs.isEmpty {
      listString.removeAll()
      for attr in attrs {
        self.addSelectListAttribute(attr)
      }
      columns = listString
      listString.removeAll()
    }
    else {
      columns = "*"
    }
    
    /* prepare where clause (has side effects for joins etc) */
    
    let whereClause = whereClauseString
    
    /* prepare order bys */

    let orderBy    : String?
    let fetchOrder = fspec?.sortOrderings
    if let fetchOrder = fetchOrder, !fetchOrder.isEmpty {
      listString.removeAll()
      for so in fetchOrder {
        addOrderByAttributeOrdering(so)
      }
      orderBy = listString
      listString.removeAll()
    }
    else {
      orderBy = nil
    }
    
    /* joins, must be done before the tablelist is generated! */
    
    let inlineJoins = doesIncludeJoinsInFromClause
    joinExpression()
    let joinClause : String? = inlineJoins
      ? nil /* will be processed in tableListAndJoinsWithRootEntity() */
      : joinClauseString
    
    /* table list */
    
    let tables : String?
    if let entity = entity {
      tables = inlineJoins
        ? tableListAndJoinsWith(rootEntity: entity)
        : tableListWith(rootEntity: entity)
    }
    else {
      tables = nil
    }
    
    /* lock */
    
    let lockClause = lock ? self.lockClause : nil
    
    /* limits */
    
    let limitClause = self.limitClause(offset: fspec?.fetchOffset ?? -1,
                                       limit: fspec?.fetchLimit   ?? -1)
    
    // TODO: GROUP BY expression [, ...]
    // TODO: HAVING condition [, ...]
    
    /* we are done, assemble */
    
    if let customSQL = customSQL {
      statement = assembleCustomSelectStatementWithAttributes(
                     attrs, lock, qualifier, fetchOrder,
                     customSQL,
                     select, columns, tables, whereClause, joinClause, orderBy,
                     limitClause, lockClause) ?? ""
    }
    else {
      statement = assembleSelectStatementWithAttributes(
                     attrs, lock, qualifier, fetchOrder,
                     select, columns, tables, whereClause, joinClause, orderBy,
                     limitClause, lockClause)
    }
  }
  
  open func assembleSelectStatementWithAttributes
    (_ _attrs : [ Attribute ], _ _lock : Bool, _ _qualifier : Qualifier?,
     _ _fetchOrder : [ SortOrdering ]?,
     _ _select     : String?,
     _ _cols       : String,
     _ _tables     : String?,
     _ _where      : String?,
     _ _joinClause : String?,
     _ _orderBy    : String?,
     _ _limit      : String?,
     _ _lockClause : String?) -> String
  {
    /* 128 was too small, SQL seems to be ~512 */
    var sb = ""
    sb.reserveCapacity(1024)
    
    sb += _select ?? "SELECT"
    sb += " "
    sb += _cols
    if let tables = _tables { sb += " FROM \(tables)" }
    
    let hasWhere      = !(_where ?? "").isEmpty
    let hasJoinClause = !(_joinClause ?? "").isEmpty
    
    if hasWhere || hasJoinClause {
      sb += " WHERE "
      if hasWhere                  { sb += _where ?? "" }
      if hasWhere && hasJoinClause { sb += " AND " }
      if hasJoinClause             { sb += _joinClause ?? "" }
    }
    
    if let ob = _orderBy, !ob.isEmpty { sb += " ORDER BY \(ob)" }
    
    if let limit      = _limit      { sb += " \(limit)"      }
    if let lockClause = _lockClause { sb += " \(lockClause)" }
    return sb
  }
  
  /**
   * Example:
   *
   *     SELECT COUNT(*) FROM %(tables)s WHERE %(where)s %(limit)s
   *   
   * Keys:
   *
   *     select       eg SELECT or SELECT DISTINCT
   *     columns      eg BASE.lastname, BASE.firstname
   *     tables       eg BASE.customer
   *     basetable    eg customer
   *     qualifier    eg lastname LIKE 'Duck%'
   *     orderings    eg lastname ASC, firstname DESC
   *     limit        eg OFFSET 0 LIMIT 1
   *     lock         eg FOR UPDATE
   *     joins
   *
   * Compound:
   *
   *     where        eg WHERE lastname LIKE 'Duck%'
   *     andQualifier eg AND lastname LIKE 'Duck%'   (nothing w/o qualifier)
   *     orQualifier  eg OR  lastname LIKE 'Duck%'   (nothing w/o qualifier)
   *     orderby      eg ORDER BY mod_date DESC (nothing w/o orderings)
   *     andOrderBy   eg , mod_date DESC (nothing w/o orderings)
   *
   */
  open func assembleCustomSelectStatementWithAttributes
    (_ _attrs : [ Attribute ], _ _lock : Bool, _ _qualifier: Qualifier?,
     _ _fetchOrder: [ SortOrdering ]?,
     _ _sqlPattern : String,
     _ _select     : String?,
     _ _cols       : String?,
     _ _tables     : String?,
     _ _where      : String?,
     _ _joinClause : String?,
     _ _orderBy    : String?,
     _ _limit      : String?,
     _ _lockClause : String?) -> String?
  {
    guard !_sqlPattern.isEmpty      else { return nil }
    guard _sqlPattern.contains("%") else { return _sqlPattern }
      /* contains no placeholders */

    /* prepare bindings */
    
    /* Note: we need to put empty strings ("") into the bindings array for
     *       missing "optional" keys (eg limit), otherwise the format()
     *       function will render references as '<null>'.
     *       Eg:
     *         %(select)s * FROM abc %(limit)s
     *       If not limit is set, this will result in:
     *         SELECT * FROM abc <null>
     */ 
    
    var bindings = [ String : Any? ]()
    bindings["select"]    = _select     ?? ""
    bindings["columns"]   = _cols       ?? ""
    bindings["tables"]    = _tables     ?? ""
    bindings["qualifier"] = _where      ?? ""
    bindings["joins"]     = _joinClause ?? ""
    bindings["limit"]     = _limit      ?? ""
    bindings["lock"]      = _lockClause ?? ""
    bindings["orderings"] = _orderBy    ?? ""

    /* adding compounds */
    
    if let w = _where, let jc = _joinClause {
      bindings["where"] = " WHERE \(w) AND \(jc)"
    }
    else if let w = _where {
      bindings["where"] = " WHERE \(w)"
    }
    else if let jc = _joinClause {
      bindings["where"] = " WHERE \(jc)"
    }
    else {
      bindings["where"] = ""
    }

    if let w = _where {
      bindings["andQualifier"] = " AND \(w)"
      bindings["orQualifier"]  = " OR \(w)"
    }
    else {
      bindings["andQualifier"] = ""
      bindings["orQualifier"]  = ""
    }
    
    if let ob = _orderBy {
      let s = " ORDER BY \(ob)"
      bindings["orderby"]    = s
      bindings["orderBy"]    = s
      bindings["andOrderBy"] = ", \(ob)"
    }
    else {
      bindings["orderby"]    = ""
      bindings["orderBy"]    = ""
      bindings["andOrderBy"] = ""
    }
    
    /* some base entity information */
  
    if let s = entity?.externalName, !s.isEmpty {
      bindings["basetable"] = s
    }
  
    /* format */
    
    return KeyValueStringFormatter.format(_sqlPattern, requiresAll: true,
                                          object: bindings)
  }
  
  
  /* column lists */
  
  /**
   * This method calls sqlStringForAttribute() to get the column name of the
   * attribute and then issues formatSQLString() with the configured
   * `readFormat` (usually empty).
   *
   * The result of this is added the the 'self.listString' using
   * appendItemToListString().
   *
   * The method is called by prepareSelectExpressionWithAttributes() to build
   * the list of attributes used in the SELECT.
   */
  open func addSelectListAttribute(_ attribute: Attribute) {
    var s = sqlStringForAttribute(attribute)
    s = formatSQLString(s, attribute.readFormat)
    
    self.appendItem(s, to: &listString)
  }
  
  open func addUpdateListAttribute(_ attribute: Attribute, value: Any?) {
    /* key */
    
    let a = self.sqlStringForAttribute(attribute)
    
    /* value */
    // TODO: why not call sqlStringForValue()?
    
    let useBind : Bool
    if let value = value {
      if value is QualifierVariable {
        useBind = true
      }
      else if value is RawSQLValue {
        useBind = false
      }
      else {
        useBind = shouldUseBindVariable(for: attribute)
      }
    }
    else {
      useBind = self.shouldUseBindVariable(for: attribute)
    }
    
    let v : String
    if useBind {
      let bind = bindVariableDictionary(for: attribute, value: value)
      v = bind.placeholder
      addBindVariableDictionary(bind)
    }
    else if let value = value as? RawSQLValue {
      v = value.value
    }
    else if let vv = formatValueForAttribute(value, attribute) {
      v = vv
    }
    else {
      log.error("could not format value:", value)
      v = String(describing: value)
    }
    
    let fv : String
    if let wf = attribute.writeFormat {
      fv = formatSQLString(v, wf)
    }
    else {
      fv = v
    }
    
    /* add to list */
    
    self.appendItem(a + " = " + fv, to: &listString)
  }
  
  open func addInsertListAttribute(_ attribute: Attribute, value: Any?) {
    /* key */
    
    self.appendItem(self.sqlStringForAttribute(attribute), to: &listString)
    
    /* value */
    // TODO: why not call sqlStringForValue()?
    
    let useBind : Bool
    if let value = value {
      if value is QualifierVariable {
        useBind = true
      }
      else if value is RawSQLValue {
        useBind = false
      }
      else {
        useBind = self.shouldUseBindVariable(for: attribute)
      }
    }
    else {
      useBind = self.shouldUseBindVariable(for: attribute)
    }
    
    var v : String
    if useBind {
      let bind = bindVariableDictionary(for: attribute, value: value)
      v = bind.placeholder
      addBindVariableDictionary(bind)
    }
    else if let value = value as? RawSQLValue {
      v = value.value
    }
    else if let vv = formatValueForAttribute(value, attribute) {
      v = vv
    }
    else {
      log.error("could not format value:", value)
      v = String(describing: value)
    }
    
    if let wf = attribute.writeFormat {
      v = formatSQLString(v, wf)
    }
    
    self.appendItem(v, to: &valueList)
  }

  
  /* limits */
  
  open func limitClause(offset: Int = -1, limit: Int = -1) -> String? {
    // TODO: offset = 0 is fine?
    guard offset >= 0 || limit >= 0 else { return nil }
    
    if offset > 0 && limit > 0 {
      return "LIMIT \(limit) OFFSET \(offset)"
    }
    else if offset > 0 {
      return "OFFSET \(offset)"
    }
    else {
      return "LIMIT \(limit)"
    }
  }
  
  
  /* orderings */
  
  open func addOrderByAttributeOrdering(_ ordering: SortOrdering) {
    let sel = ordering.selector
    
    var s : String
    if let attribute = entity?[attribute: ordering.key] {
      s = sqlStringForAttribute(attribute)
    }
    else { /* raw fetch, just use the key as the SQL name */
      s = ordering.key
    }
    
    if sel == SortOrdering.Selector.caseInsensitiveAscending ||
       sel == SortOrdering.Selector.caseInsensitiveDescending
    {
      s = formatSQLString(s, "UPPER(%P)")
    }
    
    if (sel == SortOrdering.Selector.caseInsensitiveAscending ||
        sel == SortOrdering.Selector.ascending)
    {
      s += " ASC"
    }
    else if sel == SortOrdering.Selector.caseInsensitiveDescending ||
            sel == SortOrdering.Selector.descending
    {
      s += " DESC"
    }
    
    /* add to list */
    appendItem(s, to: &listString)
  }
  
  /* where clause */
  
  var whereClauseString : String? {
    return qualifier != nil ? sqlStringForQualifier(qualifier!) : nil
  }
  
  /* join clause */
  
  var doesIncludeJoinsInFromClause : Bool { return true }

  func sqlJoinTypeFor(relationshipPath _relPath: String,
                      relationship _relship: Relationship) -> String
  {
    // TODO: rel.joinSemantic() <= but do NOT add this because it seems easy!;-)
    //      consider the effects w/o proper JOIN ordering
    return "LEFT JOIN" /* for now we always use LEFT JOIN */
  }
  
  /**
   * Returns the list of tables to be used in the FROM of the SQL.
   * 
   * @param _entity - root entity to use ("" alias)
   * @return the list of tables, eg "person AS BASE, address T0"
   */
  func tableListWith(rootEntity _entity: Entity) -> String {
    var sb = ""
    
    if useAliases, let alias = relationshipPathToAlias[""] {
      // used by regular SELECTs
      /* This variant just generates the table references, eg:
       *   person AS BASE, address AS T0, company AS T1
       * the actual join is performed as part of the WHERE, and is built
       * using the joinExpression() method.
       */

      /* the base entity */
      sb += sqlStringFor(schemaObjectName: _entity.externalName ?? _entity.name)
      sb += " AS "
      sb += alias
      
      for relPath in relationshipPathToAlias.keys {
        guard BaseEntityPath != relPath else { continue }


        guard let rel = relationshipPathToRelationship[relPath],
              let alias = relationshipPathToAlias[relPath],
              let entity = rel.destinationEntity
         else
        {
          continue
        }

        sb.append(", ")
        
        let tableName = entity.externalName ?? entity.name
        sb += sqlStringFor(schemaObjectName: tableName)
        sb += " AS "
        sb += alias
      }
    }
    else { // use by UPDATE, DELETE, etc
      // TODO: just add all table names ...
      sb += sqlStringFor(schemaObjectName: _entity.externalName ?? _entity.name)
    }
    
    return sb
  }
  
  /**
   * Returns the list of tables to be used in the FROM of the SQL,
   * plus all necessary JOIN parts of the FROM.
   *
   * Builds the JOIN parts of the FROM statement, eg:
   *
   *   person AS BASE
   *   LEFT JOIN address AS T0 ON ( T0.person_id = BASE.person_id )
   *   LEFT JOIN company AS T1 ON ( T1.owner_id  = BASE.owner_id)
   *
   * It just adds the joins from left to right, since I don't know yet
   * how to properly put the parenthesis around them :-)
   *
   * We currently ALWAYS build LEFT JOINs. Which is wrong, but unless we
   * can order the JOINs, no option.
   * 
   * @param _entity - root entity to use ("" alias)
   * @return the list of tables, eg "person AS BASE INNER JOIN address AS T0"
   */
  func tableListAndJoinsWith(rootEntity _entity: Entity) -> String {
    var sb = ""
    
    /* the base entity */
    if let base = relationshipPathToAlias[""] {
      sb += sqlStringFor(schemaObjectName: _entity.externalName ?? _entity.name)
      sb += " AS "
      sb += base
    }
    
    /* Sort the aliases by the number of components in their pathes. I
     * think later we need to consider their prefixes and collect them
     * in proper parenthesis
     */
    let aliases = relationshipPathToAlias.keys.sorted { a, b in
      return a.numberOfDots < b.numberOfDots
    }


    /* iterate over the aliases and build the JOIN fragments */

    for relPath in aliases {
      guard BaseEntityPath != relPath else { continue }

      guard let rel = relationshipPathToRelationship[relPath],
            let alias = relationshipPathToAlias[relPath],
            let entity = rel.destinationEntity
       else { continue }
      let joins = rel.joins
      guard !joins.isEmpty else {
        log.error("found no Join's for relationship", rel)
        continue /* nothing to do */
      }

      /* this does the 'LEFT JOIN' or 'INNER JOIN', etc */
      sb += " "
      sb += sqlJoinTypeFor(relationshipPath: relPath, relationship: rel)
      sb += " "

      /* table, eg: 'LEFT JOIN person AS T0' */
      let tableName = entity.externalName ?? entity.name
      sb += sqlStringFor(schemaObjectName: tableName)
      sb += " AS "
      sb += alias

      sb += " ON ( "
      
      let lastRelPath = relPath.lastRelPath

      /* add joins */
      var isFirstJoin = true
      for join in joins {
        guard let sa = join.source, let da = join.destination else {
          log.error("join has no source or dest", join)
          continue
        }

        //left  = join.sourceAttribute().name()
        //right = join.destinationAttribute().name()
        let left  = sqlStringForAttribute(sa, lastRelPath)
        let right = sqlStringForAttribute(da, relPath)
        
        if (isFirstJoin) { isFirstJoin = false }
        else { sb += " AND " }
        
        sb += left
        sb += " = "
        sb += right
      }

      sb += " )"
    }

    return sb
  }
  
  /**
   * This is called by prepareSelectExpressionWithAttributes() to construct
   * the SQL expression used to join the various Entity tables involved in
   * the query.
   *
   * It constructs stuff like T1.person_id = T2.company_id. The actual joins
   * are added using the addJoinClause method, which builds the expression
   * (in the self.joinClauseString ivar).
   */
  func joinExpression() {
    guard relationshipPathToAlias.count > 1 else { return } /* only the base */
    guard !doesIncludeJoinsInFromClause else { return }
      /* joins are included in the FROM clause */
    
    for relPath in relationshipPathToAlias.keys {
      guard relPath != "" else { continue } /* root entity */
      
      guard let rel = self.relationshipPathToRelationship[relPath]
       else { continue }
      let joins = rel.joins
      guard !joins.isEmpty else { continue } /* nothing to do */
      
      let lastRelPath = relPath.lastRelPath
      
      /* calculate prefixes */
      
      if self.useAliases {
        #if false // noop
          leftAlias  = relationshipPathToAlias[lastRelPath]
          rightAlias = relationshipPathToAlias[relPath]
        #endif
      }
      else {
        // TBD: presumably this has side-effects.
        let ln = rel.entity.externalName ?? rel.entity.name
        _ = sqlStringFor(schemaObjectName: ln) // left-alias
        
        if let de = rel.destinationEntity {
          let rn = de.externalName ?? de.name
           _ = sqlStringFor(schemaObjectName: rn)  // right-alias
        }
      }
      
      /* add joins */
      for join in joins {
        guard let sa = join.source, let da = join.destination else { continue }
        
        //left  = join.source.name
        //right = join.destination.name
        let left  = sqlStringForAttribute(sa, lastRelPath)
        let right = sqlStringForAttribute(da, relPath)
        
        addJoinClause(left, right, rel.joinSemantic)
      }
    }
  }
  
  /**
   * Calls assembleJoinClause() to build the join expression (eg
   * T1.person_id = T2.company_id). Then adds it to the 'joinClauseString'
   * using AND.
   *
   * The semantics trigger the proper operation, eg '=', '*=', '=*' or '*=*'.
   * 
   * @param _left     - left side join expression
   * @param _right    - right side join expression
   * @param _semantic - semantics, as passed on to assembleJoinClause()
   */
  func addJoinClause(_ left: String, _ right: String,
                     _ semantic: Join.Semantic)
  {
    let jc = assembleJoinClause(left, right, semantic)
    if joinClauseString.isEmpty {
      joinClauseString = jc
    }
    else {
      joinClauseString += " AND " + jc
    }
  }
  
  func assembleJoinClause(_ left: String, _ right: String,
                          _ semantic: Join.Semantic) -> String
  {
    // TODO: semantic
    let op : String
    switch semantic {
      case .innerJoin:      op = " = "
      case .leftOuterJoin:  op = " *= "
      case .rightOuterJoin: op = " =* "
      case .fullOuterJoin:  op = " *=* "
    }
    return left + op + right
  }
  
  
  /* basic construction */
  
  /**
   * Just adds the given _item String to the StringBuilder _sb. If the Builder
   * is not empty, a ", " is added before the item.
   *
   * Used to assemble SELECT lists, eg:
   *
   *     c_last_name, c_first_name
   *   
   * @param _item - String to add
   * @param _sb   - StringBuilder containing the items
   */
  func appendItem(_ item: String, to sb: inout String) {
    if !sb.isEmpty { sb += ", " }
    sb += item
  }
  
  
  /* formatting */
  
  /**
   * If the _format is null or contains no '%' character, the _sql is returned
   * as-is.<br>
   * Otherwise the '%P' String in the format is replaced with the _sql.
   * 
   * @param _sql    - SQL base expression (eg 'c_last_name')
   * @param _format - pattern (eg 'UPPER(%P)')
   * @return SQL string with the pattern applied
   */
  func formatSQLString(_ sql: String, _ format: String?) -> String {
    guard let format = format else { return sql }
    
    guard format.contains("%") else { return format }
      /* yes, the format replaces the value! */
    
    // TODO: any other formats? what about %%P (escaped %)
    return format.replacingOccurrences(of: "%P", with: sql)
  }
  
  /**
   * Escapes the given String and embeds it into single quotes.
   * Example:
   *
   *     Hello World => 'Hello World'
   * 
   * - parameter v: String to escape and quote (eg Hello World)
   * - returns:     the SQL escaped and quoted String (eg 'Hello World')
   */
  public func formatStringValue(_ v: String?) -> String {
    // TODO: whats the difference to sqlStringForString?
    guard let v = v else { return "NULL" }
    return "'" + escapeSQLString(v) + "'"
  }

  /**
   * Escapes the given String and embeds it into single quotes.
   * Example:
   *
   *     Hello World => 'Hello World'
   * 
   * - parameter v: String to escape and quote (eg Hello World)
   * - returns:     the SQL escaped and quoted String (eg 'Hello World')
   */
  public func sqlStringFor(string v: String?) -> String {
    // TBD: whats the difference to formatStringValue()? check docs
    guard let v = v else { return "NULL" }

    return "'" + escapeSQLString(v) + "'"
  }
  
  /**
   * Returns the SQL representation of a Number. For INTs this is just the
   * value, for float/doubles/bigdecs it might be database specific.
   * The current implementation just calls the numbers toString() method.
   * 
   * - parameter number: some Number object
   * - returns the SQL representation of the given Number (or NULL for nil)
   */
  public func sqlStringFor(number v: Int?) -> String {
    guard let v = v else { return "NULL" }
    return String(v)
  }
  // TBD: is this what we want?
  public func sqlStringFor<T: BinaryInteger>(number v: T?) -> String {
    guard let v = v else { return "NULL" }
    return String(describing: v)
  }
  
  /**
   * Returns the SQL representation of a Number. For INTs this is just the
   * value, for float/doubles/bigdecs it might be database specific.
   * The current implementation just calls the numbers toString() method.
   *
   * - parameter number: some Number object
   * - returns the SQL representation of the given Number (or NULL for nil)
   */
  public func sqlStringFor(number v: Double?) -> String {
    guard let v = v else { return "NULL" }
    return String(v)
  }
  
  /**
   * Returns the SQL representation of a Number. For INTs this is just the
   * value, for float/doubles/bigdecs it might be database specific.
   * The current implementation just calls the numbers toString() method.
   *
   * - parameter number: some Number object
   * - returns the SQL representation of the given Number (or NULL for nil)
   */
  public func sqlStringFor(number v: Float?) -> String {
    guard let v = v else { return "NULL" }
    return String(v)
  }
  
  /**
   * Returns the SQL representation of a Boolean. This returns TRUE and FALSE.
   * 
   * - parameter bool: some boolean
   * - returns the SQL representation of the given bool (or NULL for nil)
   */
  public func sqlStringFor(bool v: Bool?) -> String {
    guard let v = v else { return "NULL" }
    return v ? "TRUE" : "FALSE"
  }
  
  /**
   * The current implementation just returns the '\(d)' of the Date
   * (which is rarely the correct thing to do).
   * You should really use bindings for that.
   * 
   * - parameters:
   *   - v:    a Date object
   *   - attr: an Attribute containing formatting details
   * - returns: the SQL representation of the given Date (or NULL for nil)
   */
  public func formatDateValue(_ v: Date?, _ attr: Attribute? = nil) -> String? {
    // TODO: FIXME. Use format specifications as denoted in the attribute
    // TODO: is this called? Probably the formatting should be done using a
    //       binding in the JDBC adaptor
    guard let v = v else { return nil }
    return formatStringValue("\(v)") // TODO: FIXME
  }
  
  /**
   * Returns the SQL String representation of the given value Object.
   *
   * - 'nil' will be rendered as the SQL 'NULL'
   * - String values are rendered using formatStringValue()
   * - Number values are rendered using sqlStringForNumber()
   * - Date values are rendered using formatDateValue()
   * - toString() is called on RawSQLValue values
   * - arrays and Collections are rendered in "( )"
   * - KeyGlobalID objects with one value are rendered as their value
   *
   * When an QualifierVariable is encountered an error is logged and null is
   * returned.
   * For unknown objects the string representation is rendered.
   * 
   * - parameter v: some value to be formatted for inclusion in the SQL
   * - returns: a String representing the value
   */
  public func formatValue(_ v: Any?) -> String? {
    // own method for basic stuff
    guard let v = v else         { return "NULL" }
    if let v = v as? String      { return self.formatStringValue(v)    }
    if let v = v as? Int         { return self.sqlStringFor(number: v) }
    if let v = v as? Int32       { return self.sqlStringFor(number: v) }
    if let v = v as? Int64       { return self.sqlStringFor(number: v) }
      // TBD: do we need to list all Integer types?
    if let v = v as? Double      { return self.sqlStringFor(number: v) }
    if let v = v as? Float       { return self.sqlStringFor(number: v) }
    if let v = v as? Bool        { return self.sqlStringFor(bool:   v) }
    if let v = v as? Date        { return self.formatDateValue(v)      }
    if let v = v as? RawSQLValue { return v.value }
    if let v = v as? any BinaryInteger {
      return self.sqlStringFor(number: Int(v))
    }
    if let v = v as? any StringProtocol {
      return self.formatStringValue(String(v))
    }

    /* process lists */
    
    if let list = v as? [ Int ] {
      if list.isEmpty { return "( )" } // empty list
      return "( " + list.map { String($0) }.joined(separator: ", ") + " )"
    }

    if let list = v as? [ Any? ] {
      if list.isEmpty { return "( )" } // empty list
      return "( " + list.map { formatValue($0) ?? "ERROR" }
                    .joined(separator: ", ") + " )"
    }
    
    if let key = v as? KeyGlobalID {
      guard key.keyCount == 1 else {
        log.error("cannot format KeyGlobalID with more than one value:", key)
        return nil
      }
      return formatValue(key[0])
    }
    
    /* warn about qualifier variables */
    
    if v is QualifierVariable {
      log.error("detected unresolved qualifier variable:", v)
      return nil
    }
    
    /* fallback to string representation */
    
    log.error("unexpected SQL value, rendering as string:", v)
    return formatStringValue("\(v)")
  }
  
  /**
   * This method finally calls formatValue() but does some type coercion when
   * an Attribute is provided.
   * 
   * - parameters:
   *   - value: some value which should be formatted for a SQL string
   *   - attr:  an optional Attribute containing formatting info
   * - returns: String suitable for use in a SQL string (or null on error)
   */
  func formatValueForAttribute(_ value: Any?, _ attr: Attribute?) -> String? {
    guard let attr = attr else { return formatValue(value) }
    
    if let value = value as? Bool {
      /* convert Boolean values for integer columns */
      
      // somewhat hackish
      if attr.externalType?.hasPrefix("INT") ?? false {
        return value ? formatValue(1) : formatValue(0)
      }
    }
    else if let value = value as? Date {
      /* catch this here because formatValue() does not have the attribute */
      return formatDateValue(value, attr)
    }
    
    // TODO: do something with the attribute ...
    // Note: read formats are applied later on
    return formatValue(value)
  }
  
  /**
   * This is called by sqlStringForKeyValueQualifier().
   * 
   * - parameters:
   *   - _value:   value to format
   *   - _keyPath: keypath leading to the related attribute
   * - returns: SQL for the value
   */
  func sqlStringForValue(_ _value: Any?, _ _keyPath: String) -> String? {
    if let value = _value as? RawSQLValue { return value.value }
    
    let attribute = entity?[keyPath: _keyPath]
    let useBind : Bool
    
    // TBD: check whether the value is an Expression?
    
    if _value is QualifierVariable {
      useBind = true
    }
    else if let _ = _value as? [ Any? ] {
      /* Not sure whether this should really override the attribute? Its for
       * IN queries.
       */
      useBind = false
    }
    else if let attribute = attribute {
      useBind = self.shouldUseBindVariable(for: attribute)
    }
    else {
      /* no model to base our decision on */
      if _value != nil { /* we don't need a bind for NULL */
        /* we dont bind bools and numbers, no risk of SQL attacks? */
        useBind = !(_value is Int || _value is Double || _value is Bool)
      }
      else {
        useBind = false
      }
    }
    
    if useBind { // TBD: only if there is no attribute?
      let bind = bindVariableDictionary(for: attribute, value: _value)
      addBindVariableDictionary(bind)
      return bind.placeholder
    }
    
    return formatValueForAttribute(_value, attribute)
  }
  
  
  /* bind variables */
  
  /**
   * Checks whether binds are required for the specified attribute. Eg this
   * might be the case if its a BLOB attribute.
   *
   * The default implementation returns false.
   * 
   * - Parameters:
   *   - attr:   Attribute whose value should be added
   * - Returns:  whether or not binds ('?' patterns) should be used
   */
  func mustUseBindVariable(for attribute: Attribute) -> Bool {
    return false
  }
  
  /**
   * Checks whether binds should be used for the specified attribute. Eg this
   * might be the case if its a BLOB attribute. Currently we use binds for
   * almost all attributes except INTs and BOOLs.
   * 
   * - parameter attribute: Attribute whose value should be added
   * - returns: whether or not binds ('?' patterns) should be used
   */
  func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    if mustUseBindVariable(for: attribute) { return true }
    
    /* Hm, any reasons NOT to use binds? Actually yes, prepared statements are
     * slower if the query is used just once. However, its quite likely that
     * model based fetches reuse the same kind of query a LOT. So using binds
     * and caching the prepared statements makes quite some sense.
     * 
     * Further, for JDBC this ensures that our basetypes are properly escaped,
     * we don't need to take care of that (eg handling the various Date types).
     * 
     * Hm, lets avoid binding numbers and booleans.
     */
    if let exttype = attribute.externalType {
      if exttype.hasPrefix("INT")  { return false }
      if exttype.hasPrefix("BOOL") { return false }
    }
    else if let vType = attribute.valueType {
      return vType.shouldUseBindVariable(for: attribute)
    }
    
    return true
  }
  
  open func bindVariableDictionary(for attribute: Attribute?, value: Any?)
            -> BindVariable
  {
    var bind = BindVariable()
    bind.attribute = attribute
    bind.value     = value

    // This depends on the database, e.g. APR DBD uses %s, %i etc
    bind.placeholder = "?"
    
    /* generate and add a variable name */

    var name : String
    if let value = value as? QualifierVariable {
      name = value.key
    }
    else if let attribute = attribute {
      name = attribute.columnName ?? attribute.name
      name += "\(bindVariables.count)"
    }
    else {
      name = "NOATTR\(bindVariables.count)"
    }
    bind.name = name
    
    return bind
  }
  
  func addBindVariableDictionary(_ dict: BindVariable) {
    bindVariables.append(dict)
  }
  
  
  /* attributes */
  
  /**
   * Returns the SQL expression for the attribute with the given name. The name
   * can be a keypath, eg "customer.address.street".
   *
   * The method calls sqlStringForAttributePath() for key pathes,
   * or sqlStringForAttribute() for direct matches.
   * 
   * - parameters:
   *   - keyPath: the name of the attribute (eg 'name' or 'address.city')
   * - returns: the SQL (eg 'BASE.c_name' or 'T3.c_city')
   */
  func sqlStringForAttributeNamed(_ keyPath: String) -> String? {
    guard !keyPath.isEmpty else { return nil }
    
    /* Note: this implies that attribute names may not contain dots, which
     *       might be an issue with user generated tables.
     */
    if keyPath.contains(".") {
      /* its a keypath */
      return sqlStringForAttributePath(keyPath.components(separatedBy: "."))
    }
    
    if entity == nil {
      return keyPath /* just reuse the name for model-less operation */
    }
    
    if let attribute = entity?[attribute: keyPath] {
      /* Note: this already adds the table alias */
      return sqlStringForAttribute(attribute)
    }
    if let relship = entity?[relationship: keyPath] {
      // TODO: what about relationships?
      globalZeeQLLogger.error("unsupported, generating relationship match:\n",
                              "  path:", keyPath, "\n",
                              "  rs:  ", relship, "\n",
                              "  expr:", self)
      return keyPath
    }

    globalZeeQLLogger.trace("generating raw value for unknown attribute:",
                            keyPath, self)
    return keyPath
  }
  
  /**
   * Returns the SQL expression for the given attribute in the given
   * relationship path. Usually the path is empty (""), leading to a
   * BASE.column reference.
   *
   * Example:
   *
   *     attr = lastName/c_last_name, relPath = ""
   *     => BASE.c_last_name
   *   
   *     attr = address.city, relPath = "address"
   *     => T3.c_city
   * 
   * - parameters:
   *   - attr:    the Attribute
   *   - relPath: the relationship path, eg "" for the base entity
   * - returns: a SQL string, like: "BASE.c_last_name"
   */
  func sqlStringForAttribute(_ attr: Attribute, _ relPath: String)
       -> String
  {
    // TODO: not sure how its supposed to work,
    //       maybe we should also maintain an _attr=>relPath map? (probably
    //       doesn't work because it can be used in many pathes)
    // TODO: We need to support aliases. In this case the one for the
    //       root entity?
    let s = attr.valueFor(SQLExpression: self)
    if self.useAliases, let rp = relationshipPathToAlias[relPath] {
      return rp + "." + s
    }
    return s
  }
  
  /**
   * Returns the SQL string for a BASE attribute (using the "" relationship
   * path).
   * 
   * - parameter attr: the Attribute in the base entity
   * - returns:        a SQL string, like: "BASE.c_last_name"
   */
  func sqlStringForAttribute(_ attr: Attribute) -> String {
    return self.sqlStringForAttribute(attr, "" /* relship path, BASE */)
  }
  
  /**
   * This method generates the SQL column reference for a given attribute path.
   * For example employments.person.address.city might resolve to T3.city,
   * while a plain street would resolve to BASE.street.
   *
   * It is called by sqlStringForAttributeNamed() if it detects a dot ('.') in
   * the attribute name (eg customer.address.street).
   * 
   * - paramater path: the attribute path to resolve (eg customer.address.city)
   * - returns:        a SQL expression for the qualifier (eg T0.c_city)
   */
  func sqlStringForAttributePath(_ path: [ String ]) -> String? {
    guard !path.isEmpty  else { return nil }
    guard path.count > 1 else { return sqlStringForAttributeNamed(path[0]) }
    
    guard let entity = entity else {/* can't process relationships w/o entity */
      log.error("cannot process attribute pathes w/o an entity:", path)
      return nil
    }
    
    /* sideeffect: fill aliasesByRelationshipPath */
    var relPath : String? = nil
    
    var rel = entity[relationship: path[0]]
    guard rel != nil else {
      log.error("did not find relationship '\(path[0])' in entity:", entity)
      return nil
    }
    
    for i in 0..<(path.count - 1) {
      let key = path[i]
      guard !key.isEmpty else { /* invalid path segment */
        log.error("pathes contains an invalid path segment (..):", path)
        continue
      }
      
      if let p = relPath {
        relPath = p + "." + key
      }
      else {
        relPath = key
      }
      
      /* find Relationship */
      
      var nextRel = relationshipPathToRelationship[relPath!]
      if nextRel != nil {
        rel = nextRel
      }
      else {
        /* not yet cached */
        guard let de = i == 0 ? entity : rel?.destinationEntity else {
          log.error("did not find entity of relationship " +
                    "\(relPath as Optional):", rel)
          rel     = nil
          nextRel = nil
          break
        }
        
        rel = de[relationship: key]
        nextRel = rel
        if rel == nil {
          log.error("did not find relationship '\(key)' in:", de)
          // TODO: break?
        }
        
        relationshipPathToRelationship[relPath!] = rel
      }
      
      /* find alias */
      
      let alias = aliasForRelationshipPath(relPath!, key, rel)
      relationshipPathToAlias[relPath!] = alias
    }
    
    /* lookup attribute in last relationship */
    
    let ae = rel?.destinationEntity
    guard let attribute = ae?[attribute: path.last!] else {
      log.error("did not find attribute \(path.last!)" +
                " in relationship \(rel as Optional)"  +
                " entity:", ae)
      return nil
    }
    
    /* OK, we should now have an alias */
    return sqlStringForAttribute(attribute, relPath ?? "ERROR")
  }
  
  @discardableResult
  func aliasForRelationshipPath(_ relPath: String, _ key: String,
                                _ rel: Relationship?) -> String
  {
    // Alias registration is a MUST to ensure consistency
    
    if let alias = relationshipPathToAlias[relPath] { // cached already
      return alias
    }
    
    var alias : String
    if useAliases {
      let pc     = key
      let keyLen = key.count
      /* produce an alias */
      if pc.hasPrefix("to") && keyLen > 2 {
        /* eg: toCustomer => Customer" */
        let idx = key.index(key.startIndex, offsetBy: 2)
        alias = String(key[idx..<key.endIndex])
      }
      else {
        let pc0   = pc.first!
        let pcLen = pc.count
        alias = String(pc0).uppercased()
        if relationshipPathToAlias.values.contains(alias) && pcLen > 1 {
          let idx = pc.index(pc.startIndex, offsetBy: 2)
          alias = pc[pc.startIndex..<idx].uppercased()
        }
      }
      
      if relationshipPathToAlias.values.contains(alias) {
        /* search for next ID */
        let balias = alias
        for i in 1..<100 { /* limit */
          alias = "\(balias)\(i)"
          if !relationshipPathToAlias.values.contains(alias) { break }
          alias = balias
        }
      }
    }
    else if let de = rel?.destinationEntity { // not using aliases
      // TODO: check whether its correct
      alias = sqlStringFor(schemaObjectName: de.externalName ?? de.name)
    }
    else {
      log.error("Missing relationship or entity to calculate alias for path:",
                relPath, "key:", key, "relationship:", rel)
      return "ERROR" // TODO
    }
    
    relationshipPathToAlias[relPath] = alias
    return alias
  }
  
  
  
  // MARK: - Database SQL
  
  var externalNameQuoteCharacter : String? {
    /* char used to quote identifiers, eg backtick for MySQL! */
    return "\""
  }
  
  open func sqlStringFor(schemaObjectName name: String) -> String {
    if name == "*" { return "*" } /* maye not be quoted, not an ID */
    
    guard let q = externalNameQuoteCharacter else { return name }
    
    if name.contains(q) { /* quote by itself, eg ' => '' */
      let nn = name.replacingOccurrences(of: q, with: q + q)
      return q + nn + q
    }
    
    return q + name + q
  }
  
  open var lockClause : String? {
    return "FOR UPDATE" /* this is PostgreSQL 8.1 */
  }

  
  // MARK: - qualifiers
  
  /**
   * Returns the SQL operator for the given ComparisonOperation.
   * 
   * - parameters:
   *   - op:        the ComparisonOperation, eg .EqualTo or .Like
   *   - value:     the value to be compared (only tested for null)
   *   - allowNull: whether to use "IS NULL" like special ops
   * - returns: the String representing the operation, or null if none was found
   */
  open func sqlStringForSelector(_ op : ComparisonOperation,
                                 _ value: Any?, _ allowNull: Bool) -> String
  {
    /* Note: when used with key-comparison, the value is null! */
    // TODO: fix equal to for that case!
    let useNullVariant = value == nil && allowNull
    switch op {
      case .EqualTo:             return !useNullVariant ? "=" : "IS"
      case .NotEqualTo:          return !useNullVariant ? "<>" : "IS NOT"
      case .GreaterThan:         return ">"
      case .GreaterThanOrEqual:  return ">="
      case .LessThan:            return "<"
      case .LessThanOrEqual:     return "<="
      case .Contains:            return "IN"
      case .Like, .SQLLike:      return "LIKE"
      
      case .CaseInsensitiveLike, .SQLCaseInsensitiveLike:
        if let ilike = sqlStringForCaseInsensitiveLike { return ilike }
        return "LIKE"
      
      case .Unknown(let op):
        log.error("could not determine SQL operation for operator:", op)
        return op
    }
  }
  open var sqlStringForCaseInsensitiveLike : String? { return nil }
  
  /**
   * Converts the given Qualifier into a SQL expression suitable for the
   * WHERE part of the SQL statement.
   *
   * If the qualifier implements QualifierSQLGeneration, its directly asked
   * for the SQL representation.
   * Otherwise we call the appropriate methods for known types of qualifiers.
   * 
   * - parameters:
   *   - q: the qualifier to be converted
   * - returns: a String representing the qualifier, or nil on error
   */
  public func sqlStringForQualifier(_ q : Qualifier) -> String? {
    /* first support custom SQL qualifiers */
    
    if let q = q as? QualifierSQLGeneration {
      return q.sqlStringForSQLExpression(self)
    }
    
    /* next check builtin qualifiers */
    
    if let q = q as? NotQualifier {
      return sqlStringForNegatedQualifier(q.qualifier)
    }
    
    if let q = q as? KeyValueQualifier {
      return sqlStringForKeyValueQualifier(q)
    }
    if let q = q as? KeyComparisonQualifier {
      return sqlStringForKeyComparisonQualifier(q)
    }
    if let q = q as? CompoundQualifier {
      switch q.op {
        case .And: return sqlStringForConjoinedQualifiers(q.qualifiers)
        case .Or:  return sqlStringForDisjoinedQualifiers(q.qualifiers)
      }
    }

    if let q = q as? SQLQualifier     { return sqlStringForRawQualifier(q)  }
    if let q = q as? BooleanQualifier { return sqlStringForBooleanQualifier(q) }
    

    #if false // TODO
      if let q = q as? CSVKeyValueQualifier {
        return self.sqlStringForCSVKeyValueQualifier(q)
      }
      if let q = q as? OverlapsQualifier {
        return self.sqlStringForOverlapsQualifier(q)
      }
    #endif
      
    log.error("could not convert qualifier to SQL:", q)
    return nil
  }
  
  public func sqlStringForBooleanQualifier(_ q: BooleanQualifier) -> String {
    // TBD: we could return an empty qualifier for true?
    return !q.value ? "1 = 2" : "1 = 1"
  }
  
  /**
   * This returns the SQL for a raw qualifier (SQLQualifier). The SQL still
   * needs to be generated because a SQL qualifier is composed of plain strings
   * as well as 'dynamic' parts.
   *
   * QualifierVariables must be evaluated before this method is called.
   * 
   * - parameter q: the SQLQualifier to be converted
   * - returns:     the SQL for the qualifier, or null on error
   */
  public func sqlStringForRawQualifier(_ q: SQLQualifier) -> String {
    // TODO: Do something inside the parts? Pattern replacement?
    let parts = q.parts
    guard !parts.isEmpty else { return "" }
    
    var sb = ""
    for part in parts {
      switch part {
        case .rawValue(let value):
          assert(value != "authIds")
          let rv = RawSQLValue(value)
          if let s = formatValue(rv) { sb += s }
          
        case .value(.none):
          if let s = formatValue(nil) { sb += s }
        case .value(.some(let v)):
          // FIXME: Improve the whole mechanism
          switch v {
            case .int   (let v): sb += self.sqlStringFor(number: v)
            case .double(let v): sb += self.sqlStringFor(number: v)
            case .string(let v): sb += self.formatStringValue(v)
            case .intArray(let v):
              if let s = formatValue(v) { sb += s }
            case .stringArray(let v):
              if let s = formatValue(v) { sb += s }
          }

        case .variable(let name):
          log.error("SQL qualifier contains a variable: \(part) \(name)")
      }
    }
    return sb
  }
  
  /**
   * This method generates the SQL for the given qualifier and then negates it,
   * but embedded it in a "NOT ( Q )". Should work across all databases.
   * 
   * - parameter q: base qualifier, to be negated
   * - returns: the SQL string or null if no SQL was generated for the qualifier
   */
  public func sqlStringForNegatedQualifier(_ q: Qualifier) -> String? {
    guard let qs = sqlStringForQualifier(q), !qs.isEmpty else { return nil }
    return "NOT ( " + qs + " )"
  }
  
  open var sqlTrueExpression  : String { return "1 = 1" }
  open var sqlFalseExpression : String { return "1 = 0" }
  
  open func shouldCoalesceEmptyString(_ q: KeyValueQualifier) -> Bool {
    // TBD: Do we have attribute info? (i.e. is the column nullable in the
    //      first place)
    return q.operation == .Like || q.operation == .CaseInsensitiveLike
  }
  
  /**
   * Generates the SQL for an KeyValueQualifier. This qualifier compares a
   * column against some constant value using some operator.
   * 
   * - parameter q: the KeyValueQualifier
   * - returns:     the SQL or nil if the SQL could not be generated
   */
  public func sqlStringForKeyValueQualifier(_ q: KeyValueQualifier) -> String? {
    /* generate lhs */
    // TBD: use sqlStringForExpression with Key?
    
    // What if the LHS is a relationship? (like addresses.street). It will
    // yield the proper alias, e.g. "A.street"!
    guard let sqlCol = self.sqlStringForExpression(q.leftExpression) else {
      log.error("got no SQL string for attribute of LHS \(q.key):", q)
      return nil
    }
    
    // TODO: unless the DB supports a specific case-search LIKE, we need
    //       to perform an upper
    
    var v = q.value
    let k = q.key
    
    /* generate operator */
    // TODO: do something about caseInsensitiveLike (TO_UPPER?), though in
    //       PostgreSQL and MySQL this is already covered by special operators
    
    let opsel         = q.operation
    let op            = self.sqlStringForSelector(opsel, v, true)
    let needsCoalesce = shouldCoalesceEmptyString(q)
    
    var sb = ""
    
    if needsCoalesce { sb += "COALESCE(" } // undo NULL values for LIKE
    sb += sqlCol
    if needsCoalesce {
      sb += ", "
      sb += formatStringValue("")
      sb += ")"
    }
    
    /* generate operator and value */

    if op.hasPrefix("IS") && v == nil {
      /* IS NULL or IS NOT NULL */
      sb += " "
      sb += op
      sb += " NULL"
      return sb
    }
    
    if op == "IN" {
      if let v = v as? QualifierVariable {
        log.error("detected unresolved qualifier variable in IN qualifier:\n" +
                  "  \(q)\n  variable: \(v)")
        return nil
      }
      
      // we might need to add casting support, eg:
      //   varcharcolumn IN ( 1, 2, 3, 4 )
      // does NOT work with PostgreSQL. We need to do:
      //   varcharcolumn::int IN ( 1, 2, 3, 4 )
      // which is also suboptimal if the varcharcolumn does contain strings,
      // or: 
      //   varcharcolumn IN ( 1::varchar, 2::varchar, 3::varchar, 4::varchar )
      // which might be counter productive since it might get longer than:
      //   varcharcolumn = 1 OR varcharcolumn = 2 etc

      
      if let c = v as? [ Any ] {
        if let add = sqlStringForInValues(c, key: k) {
          return sb + add
        }
        else {
          /* An 'IN ()' does NOT work in PostgreSQL, weird. We treat such a
           * qualifier as always false. */
          return sqlFalseExpression
        }
      }
      
      if let c = v as? any Collection {
        if let add = sqlStringForInValues(c, key: k) {
          return sb + add
        }
        else {
          /* An 'IN ()' does NOT work in PostgreSQL, weird. We treat such a
           * qualifier as always false. */
          sb += sqlFalseExpression
          return sb
        }
      }
      
      // Coalesce
      if      let n = v as? DateInterval { v = OpenDateInterval(n) }
      else if let n = v as? Range<Date>  { v = OpenDateInterval(n) }

      if let range = v as? OpenDateInterval {
        // TBD: range query ..
        // eg: birthday IN 2008-09-10 00:00 - 2008-09-11 00:00
        // => birthday >= $start AND birthDay < $end
        // TBD: DATE, TIME vs DATETIME ...
        if range.isEmpty {
          sb.removeAll()
          sb += sqlFalseExpression
        }
        else {
          let date : Date?
          
          if let fromDate = range.start {
            sb += " "
            sb += self.sqlStringForSelector(.GreaterThanOrEqual,
                                            fromDate, false /* no null */)
            sb += " "
            sb += sqlStringForValue(fromDate, k) ?? "ERROR"
            
            if let toDate = range.end {
              sb += " AND "
              sb += sqlCol
              date = toDate
            }
            else {
              date = fromDate
            }
          }
          else {
            date = range.end
          }
          
          if let date = date {
            sb += " "
            sb += sqlStringForSelector(.LessThan, date, false /* nonull */)
            sb += " "
            sb += sqlStringForValue(date, k) ?? "ERROR"
          }
        }
      }
      else {
        /* Note: 'IN ( NULL )' at least works in PostgreSQL */
        log.error("value of IN qualifier was no list:", v)
        sb += " IN ("
        sb += sqlStringForValue(v, k) ?? "ERROR"
        sb += ")"
      }
      return sb
    }
    
    // Coalesce
    if      let n = v as? DateInterval { v = OpenDateInterval(n) }
    else if let n = v as? Range<Date>  { v = OpenDateInterval(n) }
    if let range = v as? OpenDateInterval {
      if opsel == .GreaterThan {
        if range.isEmpty { /* empty range, always greater */
          sb.removeAll()
          sb += sqlTrueExpression
        }
        else if let date = range.end {
          /* to dates are exclusive, hence check for >= */
          sb += " "
          sb += self.sqlStringForSelector(.GreaterThanOrEqual,
                                          date, false /* no null */)
          sb += " "
          sb += self.sqlStringForValue(date, k) ?? "ERROR"
        }
        else { /* open end, can't be greater */
          sb.removeAll()
          sb += self.sqlFalseExpression
        }
      }
      else if opsel == .LessThan {
        if range.isEmpty { /* empty range, always smaller */
          sb.removeAll()
          sb += self.sqlTrueExpression
        }
        else if let date = range.start {
          /* from dates are inclusive, hence check for < */
          sb += " "
          sb += op
          sb += " "
          sb += sqlStringForValue(date, k) ?? "ERROR"
        }
        else { /* open start, can't be smaller */
          sb.removeAll()
          sb += self.sqlFalseExpression
        }
      }
      else {
        log.error("TimeRange not yet supported as a value for op: ", op)
        return nil
      }
      return sb
    }
    
    // Other

    sb += " "
    sb += op
    sb += " "
    
    /* a regular value */
    if let vv = v {
      if opsel == .Like ||  opsel == .CaseInsensitiveLike {
        // TODO: unless the DB supports a specific case-search LIKE, we need
        //       to perform an upper
        v = self.sqlPatternFromShellPattern(String(describing: vv))
      }
    }
  
    // this does bind stuff if enabled
    sb += sqlStringForValue(v, k) ?? "ERROR"

    return sb
  }
  
  private func sqlStringForInValues<C>(_ c: C, key k: String) -> String?
    where C: Collection
  {
    // TBD: can't we move all this to sqlStringForValue? This has similiar
    //      stuff already
    guard !c.isEmpty else {
      /* An 'IN ()' does NOT work in PostgreSQL, weird. We treat such a
       * qualifier as always false. */
      return nil
    }
    var sb = " IN ("

    var isFirst = true
    for subvalue in c {
      guard let fv = sqlStringForValue(subvalue, k) else { continue }
      
      if isFirst { isFirst = false }
      else { sb += ", " }

      sb += fv
    }

    sb += ")"

    return sb
  }
  
  /**
   * Generates the SQL for an KeyComparisonQualifier, eg:
   *
   *     ship.city = bill.city
   *     T1.city = T2.city
   * 
   * - parameter _q: KeyComparisonQualifier to build
   * - returns:      the SQL for the qualifier
   */
  func sqlStringForKeyComparisonQualifier(_ _q: KeyComparisonQualifier)
       -> String?
  {
    /* generate operator */
    // TODO: do something about caseInsensitiveLike (TO_UPPER?)
    var sb = ""
    guard let l = sqlStringForExpression(_q.leftExpression)  else { return nil }
    guard let r = sqlStringForExpression(_q.rightExpression) else { return nil }
    sb += l
    sb += sqlStringForSelector(_q.operation, nil, false)
    sb += r
    return sb
  }
  
  /**
   * Calls sqlStringForQualifier() on each of the given qualifiers and joins
   * the results using the given _op (either " AND " or " OR ").
   *
   * Note that we do not add empty qualifiers (such which returned an empty
   * String as their SQL representation).
   * 
   * - parameters:
   *   - _qs: set of qualifiers
   *   - _op: operation to use, including spaces, eg " AND "
   * - returns: String containing the SQL for all qualifiers
   */
  func sqlStringForJoinedQualifiers(_ _qs : [ Qualifier ], _ _op: String)
       -> String?
  {
    guard !_qs.isEmpty else { return nil }
    if _qs.count == 1 { return sqlStringForQualifier(_qs[0]) }
    
    var sb = ""
    for q in _qs {
      guard let s = sqlStringForQualifier(q), !s.isEmpty else { continue }
        /* do not add empty qualifiers as per doc */ // TBD: explain
      
      // TBD: check for sqlTrueExpression, sqlFalseExpression?!
      
      if !sb.isEmpty { sb += _op }
      sb += "( \(s) )"
    }
    return sb
  }
  
  /**
   * Calls sqlStringForJoinedQualifiers with the " AND " operator.
   * 
   * - Parameters:
   *   - qs:    Qualifiers to conjoin
   * - Returns: SQL representation of the qualifiers
   */
  public func sqlStringForConjoinedQualifiers(_ qs: [ Qualifier ]) -> String? {
    return self.sqlStringForJoinedQualifiers(qs, " AND ")
  }
  /**
   * Calls sqlStringForJoinedQualifiers with the " OR " operator.
   * 
   * - Parameters:
   *   - qs:    Qualifiers to disjoin
   * - Returns: SQL representation of the qualifiers
   */
  public func sqlStringForDisjoinedQualifiers(_ qs: [ Qualifier ]) -> String? {
    return self.sqlStringForJoinedQualifiers(qs, " OR ")
  }
  
  /**
   * Converts the shell patterns used in Qualifiers into SQL `%` patterns.
   * Example:
   * ```
   * name LIKE '?ello*World*'
   * name LIKE '_ello%World%'
   * ```
   *
   * - Parameters:
   *   - _pattern: Shell based pattern
   * - Returns:    SQL pattern
   */
  @inlinable
  public func sqlPatternFromShellPattern(_ _pattern: String) -> String {
    // hm, should we escape as %%?

    return _pattern.reduce("") { res, c in
      switch c {
        case "%": return res + "\\%"
        case "*": return res + "%"
        case "_": return res + "\\_"
        case "?": return res + "_"
        default:  return res + String(c)
      }
    }
  }
  
  #if false // TODO
  func sqlStringForCSVKeyValueQualifier(_ q: CSVKeyValueQualifier) -> String {
    /* the default implementation just builds a LIKE qualifier */
    return self.sqlStringForQualifier(_q.rewriteAsPlainQualifier())
  }
  
  func sqlStringForOverlapsQualifier(_ q: OverlapsQualifier) -> String {
    /* the default implementation just builds the range qualifier manually */
    return self.sqlStringForQualifier(_q.rewriteAsPlainQualifier())
  }
  #endif
  
  /* expressions */
  
  /**
   * This method 'renders' expressions as SQL. This is similiar to an
   * Qualifier, but can lead to non-bool values. In fact, an Qualifier
   * can be used here (leads to a true/false value).
   *
   * The feature is that value expressions can be used in SELECT lists. Instead
   * of plain Attribute's, we can select stuff like SUM(lineItems.amount).
   *
   * Usually you need to embed the actual in an NamedExpression, so that the
   * value has a distinct name in the resulting dictionary. 
   * 
   * - parameter _expr: the expression to render (Attribute, Key, Qualifier,
   *                    Case, Aggregate, NamedExpression)
   * - returns:         SQL code which calculates the expression
   */
  func sqlStringForExpression(_ _expr: Any?) -> String? {
    if (_expr == nil    ||
        _expr is String ||
        _expr is Int    ||
        _expr is Double ||
        _expr is Bool)
    {
      // TBD: not sure whether this is correct
      return formatValue(_expr)
    }
    
    if let a = _expr as? Attribute {
      return formatSQLString(sqlStringForAttribute(a), a.readFormat)
    }

    if let k = _expr as? Key {
      // TBD: check what sqlStringForKeyValueQualifier does?
      return sqlStringForKey(k)
    }

    if let q = _expr as? Qualifier {
      return sqlStringForQualifier(q)
    }
    
    #if false // TODO
    if let c = _expr as? Case {
      log.error("Case generation not supported yet:", c)
      return nil
    }
    #endif
    
    log.error("unsupported expression:", _expr)
    return nil
  }
  
  public func sqlStringForKey(_ _key: Key) -> String? {
    let k = _key.key
    
    /* generate lhs */
    // TBD: use sqlStringForExpression with Key?
    
    guard let sqlCol = sqlStringForAttributeNamed(k) else {
      log.error("got no SQL string for attribute of key \(k):", _key)
      return nil
    }

    guard let a = entity?[attribute: k] else { return sqlCol }
    
    let aCol = formatSQLString(sqlCol, a.readFormat)
    
    // TODO: unless the DB supports a specific case-search LIKE, we need
    //       to perform an upper
    return aCol
  }
  
  
  
  /* DDL */
  
  open func addCreateClauseForAttribute(_ attribute: Attribute,
                                        in entity: Entity? = nil)
  {
    let isPrimaryKey = (entity?.primaryKeyAttributeNames ?? [])
                       .contains(attribute.name)
    
    /* separator */
    
    if !listString.isEmpty {
      listString += ",\n"
    }
    
    /* column name */
    
    let c = attribute.columnName ?? attribute.name
    listString += sqlStringFor(schemaObjectName: c)
    listString += " "
    
    /* column type */
    
    listString += columnTypeStringForAttribute(attribute)
    
    /* constraints */
    /* Note: we do not add primary keys, done in a separate step */

    let s = allowsNullClauseForConstraint(attribute.allowsNull ?? true)
    listString += s
    
    if isPrimaryKey {
      listString += " PRIMARY KEY"
    }
  }
  
  open func sqlForForeignKeyConstraint(_ rs: Relationship) -> String? {
    // This is for constraint statements, some databases can also attach the
    // constraint directly to the column. (which should be handled by the
    // method above).
    //   person_id INTEGER NOT NULL,
    //     FOREIGN KEY(person_id) REFERENCES person(person_id) DEFERRABLE
    guard let destTable = rs.destinationEntity?.externalName
                       ?? rs.destinationEntity?.name
     else {
      return nil
     }
    
    var sql = "FOREIGN KEY ( "
    var isFirst = true
    for join in rs.joins {
      if isFirst { isFirst = false } else { sql += ", " }
      
      
      guard let propName = join.sourceName ?? join.source?.name
       else { return nil }
      
      guard let attr = rs.entity[attribute: propName] else { return nil }
      let columnName = attr.columnName ?? attr.name
      
      sql += sqlStringFor(schemaObjectName: columnName)
    }
    sql += " ) REFERENCES "

    sql += sqlStringFor(schemaObjectName: destTable)
    
    sql += " ( "
    isFirst = true
    for join in rs.joins {
      if isFirst { isFirst = false } else { sql += ", " }
      
      guard let propName = join.destinationName ?? join.destination?.name
       else { return nil }
      
      guard let attr = rs.destinationEntity?[attribute: propName]
       else { return nil }
      let columnName = attr.columnName ?? attr.name
      
      sql += sqlStringFor(schemaObjectName: columnName)
    }
    sql += " )"
    
    
    if let updateRule = rs.updateRule {
      switch updateRule {
        case .applyDefault: sql += " ON UPDATE SET DEFAULT"
        case .cascade:      sql += " ON UPDATE CASCADE"
        case .deny:         sql += " ON UPDATE RESTRICT"
        case .noAction:     sql += " ON UPDATE NO ACTION"
        case .nullify:      sql += " ON UPDATE SET NULL"
      }
    }
    
    if let deleteRule = rs.deleteRule {
      switch deleteRule {
        case .applyDefault: sql += " ON DELETE SET DEFAULT"
        case .cascade:      sql += " ON DELETE CASCADE"
        case .deny:         sql += " ON DELETE RESTRICT"
        case .noAction:     sql += " ON DELETE NO ACTION"
        case .nullify:      sql += " ON DELETE SET NULL"
      }
    }
    
    return sql
  }
  open func externalTypeForValueType(_ type: AttributeValue.Type) -> String? {
    // FIXME: I don't like this stuff
    guard let et =
      ZeeQLTypes.externalTypeFor(swiftType: type.optionalBaseType ?? type,
                                 includeConstraint: false)
     else {
      log.error("Could not derive external type from Swift type:", type)
      return nil
     }
    
    return et
  }
  
  open func externalTypeForTypelessAttribute(_ attr: Attribute) -> String {
    log.warn("attribute has no type", attr)
    
    if let cn = attr.columnName, cn.hasSuffix("_id")          { return "INT" }
    if attr.name.hasSuffix("Id") || attr.name.hasSuffix("ID") { return "INT" }
    // TODO: More smartness. Though it doesn't really belong here but in a
    //       model postprocessing step.
    return "TEXT"
  }


  open func columnTypeStringForAttribute(_ attr: Attribute) -> String {
    let extType : String
    
    if let t = attr.externalType {
      extType = t
    }
    else if let t = attr.valueType, let et = externalTypeForValueType(t) {
      extType = et
    }
    else {
      extType = externalTypeForTypelessAttribute(attr)
    }
    
    if let precision = attr.precision, let width = attr.width {
      return "\(extType)(\(precision),\(width))"
    }
    else if let width = attr.width {
      return "\(extType)(\(width))"
    }
    return extType
  }
  
  public func allowsNullClauseForConstraint(_ allowNull: Bool) -> String {
    return allowNull ? " NULL" : " NOT NULL"
  }
  
  
  /* escaping */
  
  /**
   * This function escapes single quotes and backslashes with itself. Eg:
   *
   *   Hello 'World'
   *   Hello ''World''
   *
   * @param _value - String to escape
   * @return escaped String
   */
  public func escapeSQLString(_ _value: String) -> String {
    guard !_value.isEmpty else { return "" }

    return _value.reduce("") { res, c in
      switch c {
        case "\\": return res + "\\\\"
        case "'":  return res + "''"
        default:   return res + String(c)
      }
    }
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    if statement.isEmpty {
      ms += " EMPTY"
    }
    else {
      ms += " "
      ms += statement
    }
  }
}

/**
 * Implemented by Attribute and Entity to return the SQL to be used for
 * those objects.
 *
 * Eg the Attribute takes its columnName() and calls
 * sqlStringFor(schemaObjectName:) with it on the given SQLExpression.
 */
public protocol SQLValue {
  
  /**
   * Called by sqlStringFor(attribute:) and other methods to convert an
   * object to a SQL expression.
   */
  func valueFor(SQLExpression context: SQLExpression) -> String
  
}

/**
 * When the SQLExpression generates SQL for a given qualifier, it
 * first checks whether the qualifier implements this protocol. If so, it
 * lets the qualifier object generate the SQL instead of relying on the default
 * mechanisms.
 */
public protocol QualifierSQLGeneration {
  
  func sqlStringForSQLExpression(_ expr: SQLExpression) -> String
  
}


// MARK: - Helpers

fileprivate extension String {
  
  var numberOfDots : Int {
    return reduce(0) { $1 == "." ? ($0 + 1) : $0 }
  }
  
  var lastRelPath : String {
    guard let r = range(of: ".", options: .backwards) else { return "" }
    return String(self[self.startIndex..<r.lowerBound])
  }
}

/// Whether, when generating SQL for AdaptorRow's, the Entity order of
/// attributes should be maintained.
/// W/o this, the order of columns in generated SQL will be arbitrary as
/// Swift dictionaries do not have a stable order (intentionally).
fileprivate let maintainAttributeOrderingInRows = true

fileprivate extension AdaptorRow {
  
  func attributesAndValues(in entity: Entity)
       -> [ ( attribute: Attribute, value: Any? ) ]
  {
    // Adaptor
    let logger = globalZeeQLLogger
    var result = [ ( attribute: Attribute, value: Any? ) ] ()
    
    // This may not be actually slower in practice, because the attribute
    // subscript also just scans the array for the key?!
    if maintainAttributeOrderingInRows {
      var pendingKeys = Set(self.keys)
      var columns = [ ( attribute: Attribute, value: Any? ) ]()
      for attribute in entity.attributes {
        if let value = self[attribute.name] { // still an `Any?`!
          result.append( ( attribute, value ))
          pendingKeys.remove(attribute.name)
        }
        else if let column = attribute.columnName, column != attribute.name,
                let value = self[column] // still an `Any?`!
        {
          columns.append( ( attribute, value ) )
        }
        // else: Attribute not in set, we don't add a nil for it!
      }
      
      // process column references
      if !pendingKeys.isEmpty && !columns.isEmpty {
        for ( attribute, value ) in columns {
          assert(attribute.columnName != nil)
          guard let column = attribute.columnName else { continue }
          guard pendingKeys.contains(column) else { continue } // extra colmap
          result.append( ( attribute, value ) )
          pendingKeys.remove(column)
        }
      }

      if !pendingKeys.isEmpty {
        logger.log("did not find attributes for",
                   pendingKeys.sorted().joined(separator: ","),
                   "of", self, "in", entity)
      }
    }
    else {
      for ( key, value ) in self {
        guard let attr = entity[attribute: key] ?? entity[columnName: key] else {
          logger.log("did not find attribute", key, "of", self, "in", entity)
          continue
        }
        result.append(( attr, value ))
      }
    }
    return result
  }
}
