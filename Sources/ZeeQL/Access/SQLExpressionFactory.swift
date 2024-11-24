//
//  SQLExpressionFactory.swift
//  ZeeQL
//
//  Created by Helge Hess on 21/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * SQLExpressionFactory
 *
 * The expression factory is exposed by the Adaptor. Most adaptors subclass
 * this object to add support for their own SQL syntax. For example MySQL uses
 * backticks for quoting schema identifiers while PostgreSQL uses double quotes.
 *
 * Such differences are covered by subclasses of ``SQLExpression`` which
 * generate the actual SQL.
 * This factory constructs the specific ``SQLExpression`` objects.
 *
 * Usually the methods of this class are called by ``AdaptorChannel`` to
 * build SQL for non-raw fetches and changes.
 * But you can use ``SQLExpression`` in your own code if you want to perform
 * raw SQL but still want to generate database independend SQL.
 * However its recommended to use ``FetchSpecification``'s with an SQL hint
 * instead, eg:
 * ```xml
 * <fetch name="selectCount">
 *   <sql>SELECT * FROM MyTable</sql>
 * </fetch>
 * ```
 */
open class SQLExpressionFactory {
  
  public init() {}
  
  /* factory */
  
  open func createExpression(_ entity: Entity?) -> SQLExpression {
    return SQLExpression(entity: entity)
  }
  
  open func expressionForString(_ sql: String) -> SQLExpression? {
    guard !sql.isEmpty else { return nil }
    let e = createExpression(nil /* entity */)
    e.statement = sql
    return e
  }
  
  open func deleteStatementWithQualifier(_ qualifier: Qualifier,
                                         _ entity: Entity) -> SQLExpression
  {
    let e = createExpression(entity)
    e.prepareDeleteExpressionFor(qualifier: qualifier)
    return e
  }
  
  open func insertStatementForRow(_ row : AdaptorRow, _ entity: Entity?)
            -> SQLExpression
  {
    let e = createExpression(entity)
    e.prepareInsertExpressionWithRow(row)
    return e
  }

  open func updateStatementForRow(_ row       : AdaptorRow,
                                  _ qualifier : Qualifier,
                                  _ entity    : Entity)
            -> SQLExpression
  {
    let e = createExpression(entity)
    e.prepareUpdateExpressionWithRow(row, qualifier)
    return e
  }
  
  open func selectExpressionForAttributes(_ attrs  : [ Attribute ],
                                          lock     : Bool = false,
                                          _ fs     : FetchSpecification?,
                                          _ entity : Entity?) -> SQLExpression
  {
    /* This is called by the AdaptorChannel to construct the SQL required to
     * execute a fetch. At this point no SQL has been processed and the SQL
     * hints are still in the fetch specification.
     */
    
    /*
     * Let the adaptor construct a new, database specific expression object. 
     */
    let e = createExpression(entity)
    
    /*
     * Note: Despite the name 'prepare' this already constructs the SQL inside
     *       the expression. It also processes the raw SQL hints in the fetch
     *       specification.
     *       
     *       Bindings are resolved *before* this step. Don't be confused by the
     *       difference between `FetchSpecification`/`Qualifier` binding
     *       variables and SQL bindings used in the SQL.
     */
    e.prepareSelectExpressionWithAttributes(attrs, lock, fs)
    return e
  }
  
}
