# Raw SQL Injection Notes

When your database schema becomes more complex, you may want to embed raw SQL
in your ORM queries.
ZeeQL supports various ways to do this.

TBD: cleanup & organize

## CustomQueryExpressionHintKey

*IMPORTANT*:
patterns use `%` (e.g. `%(oid)s`), NOT the `$abc` syntax of `Qualifier`s
- the hint is being processed by `SQLExpression`
  - you can also use `SQLQualifier` with `SQLExpression` (which uses the
    `$abc` binding syntax)
          
Raw SQL Patterns
    
If the 'CustomQueryExpressionHintKey' is set, the value of this key is
processed as a keyvalue-format pattern to produce the SQL. SQLExpression
will still prepare and provide the parts of the SQL (qualifiers, sorts)
but the assembly will be done using the SQL pattern.

Example:

    SELECT COUNT(*) FROM %(tables)s WHERE %(where)s %(limit)s
    
Keys:
- select       eg SELECT or SELECT DISTINCT
- columns      eg BASE.lastname, BASE.firstname
- tables       eg BASE.customer
- basetable    eg customer
- qualifier    eg lastname LIKE 'Duck%'
- orderings    eg lastname ASC, firstname DESC
- limit        eg OFFSET 0 LIMIT 1
- lock         eg FOR UPDATE
- joins

Compound:
- where        eg WHERE lastname LIKE 'Duck%'
- andQualifier eg AND lastname LIKE 'Duck%'   (nothing w/o qualifier) 
- orQualifier  eg OR  lastname LIKE 'Duck%'   (nothing w/o qualifier) 
- orderby      eg ORDER BY mod_date DESC (nothing w/o orderings) 

Note: when using joins in a query, the base table should be named
      'BASE', so that all the other features can be used.

- `CustomQueryExpressionHintKey` is also set by `DatabaseDataSource`
  `fetchObjectsFor(sql:)`
    

## CustomQueryExpressionHintKeyBindPattern

Example: `%%(tables)s WHERE id = %(id)s`

In Code: `fs.fetchSpecificationWith(bindings: [ "id":  1] )`

=> CustomQueryExpressionHintKey = `%(tables)s WHERE id = 1;`

- formatting is done using `KeyValueStringFormatter.format()`
- TBD, SEC: do we need to be careful about SQL injection?

Usage in an XML Model:

```xml
<fetch name="count" rawrows="true">
  <sql pattern="true/false">
    %(select)s COUNT(*) FROM %(tables)s %(where)s
  </sql>
</fetch>
```

Important: when using patterns, you need to escape SQL keys twice, eg:
           %%(select)s COUNT(*) FROM %%(table)s WHERE oid=%(oid)i


## SQLQualifier

Example: `"login = %@ OR SQL[balance IN $balance1, $balance2]"`

The SQL qualifier is getting split into parts, in this case:
- "balance IN "
- $balance1 (QualifierVariable name=balance1)
- ", "
- $balance2 (QualifierVariable name=balance2)

It is being processed in `SQLExpression` (sqlStringForRawQualifier(q)),
at this point all QualifierVariable's are resolved! (bindings to the
FetchSpecification)

Do not confuse SQL binding variables with FetchSpecification bindings!


## SQLValue

- To inject single values
- Currently only supported by `SQLExpression.addUpdateListAttribute`

Example:
```Swift
let values = [
  "status"  : "created",
  "modDate" : RawSQLValue("NOW()")
]
let op = AdaptorOperation(entity)
...
op.changedValues = values

let affected = channel.performAdaptorOperationN(op)
```

## Attribute Formats

One can also inject `readformat`/`writeformat` SQL, e.g. to change all values
to lowercase on writes:

    writeformat="LOWER(TRIM(%P))"

or case-stuff, like::

    readformat="CASE %P WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' END"

