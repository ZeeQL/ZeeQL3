//
//  QualifierParser.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

// public extension Qualifier {}
//   no static methods on protocols
  
@inlinable
public func qualifierWithFormat(_ format: String, _ args: Any?...) -> Qualifier? {
  var parser = QualifierParser(string: format, arguments: args)
  return parser.parseQualifier()
}

@available(*, deprecated, renamed: "qualifierWithFormat(_:_:)")
@inlinable
public func qualifierWith(format: String, _ args: Any?...) -> Qualifier? {
  var parser = QualifierParser(string: format, arguments: args)
  return parser.parseQualifier()
}

/**
 * Parses Qualifier objects from a char buffer. Qualifiers look like a
 * SQL WHERE statement, but some special rules apply.
 * 
 * ### KeyValueQualifier
 * Example:
 * ```
 * lastname like 'h*'
 * ```
 *
 * ### Comparison Operations
 *
 * - `=`
 * - `!=`
 * - `<`
 * - `>`
 * - `=<` `<=`
 * - `=>` `>=`
 * - `LIKE`
 * - `IN` (ComparisonOperation.CONTAINS) [TBD: a NOT IN array]
 * - `IS NULL` / `IS NOT NULL`
 * - custom identifiers/selectors, eg: `hasPrefix:`
 * - Note: you can use formats, eg: ("lastname %@ 'Duck'", "LIKE")
 *
 * ### Constants
 *
 * - numbers - `12345`
 * - strings - 'hello world' or "hello world"
 * - boolean - `true`/`false`/`YES`/`NO`
 * - null    - `NULL` / `null` (no support for nil!)
 * - casts   - start with a '(', eg (Date)'2007-09-21'
 *
 * ### Qualifier Bindings
 *
 * Bindings are used to fill values into the qualifier at a later time. Each
 * binding has a name which can be used multiple times in a single qualifier.
 * The binding is represented as a ``QualifierVariable`` object once it got
 * parsed.
 *
 * Example:
 * ```
 * lastname = $lastname AND firstname = $firstname
 * ```
 *
 * Matching code:
 * ```swift
 *    var q = Qualifier.parse("lastname = $lastname AND firstname = $firstname")
 *    q = q.qualifierWithBindings(self)
 * ```
 * The q.qualifierWithBindings method will ask 'self' for the
 * 'lastname' and 'firstname' keys using KVC.
 * 
 * ### Patterns
 *
 * You can embed patterns in a qualifier format, eg:
 * ```
 * lastname LIKE %@
 * ```
 *
 * The pattern is resolved during format parsing, in the above case the
 * matching Swift code would look like:
 * ```swift
 * let q = Qualifier.parse("lastname LIKE %@", "Duck");
 * ```
 *
 * (usually the argument will be some instance variable, eg one which is filled
 *  from a search field).
 *
 * There is no strict rule when to use Patterns and when to using Bindings.
 * Usually bindings are more convenient to map to control elements (because
 * the bindings dictionary can be filled conveniently using KVC).
 *
 * - `%@` - use given value as-is
 * - `%s` - convert value to String
 * - `%i` / %d - convert value to Integer
 * - `%f` - convert value to Double
 * - `%K` - a key, this will result in a ``KeyComparisonQualifier``
 * - `%%` - to escape %
 *
 * 
 * #### True/False Qualifiers
 * Those are sometimes useful in rules, they always match or fail:
 *
 * - `*true*`
 * - `*false*`
 *
 * ### SQL Qualifiers
 *
 * To embed SQL in your qualifiers, you can use the `SQL[]`
 * construct, e.g.:
 * ```
 * lastname = 'Duck' AND SQL[ EXISTS (SELECT 1 FROM permissions) ]
 * ```
 *
 * A SQL qualifier can even include bindings. The qualifier is represented as
 * a ``SQLQualifier`` object at runtime, which in turn is a sequence of 'parts'.
 * Those parts are either ``QualifierVariable``'s or ``RawSQLValue``'s (those
 * are output as-is by ``SQLExpression``).
 */
public struct QualifierParser {

  public enum ParserError: Swift.Error, Equatable, CustomStringConvertible {

    case emptyInput(string: String)
    case invalidSyntax(reason: String, position: Int, string: String)

    public var string: String {
      switch self {
        case .emptyInput(let string):             return string
        case .invalidSyntax(_, _, let string):    return string
      }
    }

    public var description: String {
      switch self {
        case .emptyInput:
          return "empty qualifier"
        case .invalidSyntax(let reason, let position, _):
          return "\(reason) at position \(position)"
      }
    }
  }

  public let log : ZeeQLLogger = globalZeeQLLogger
  
  /* input */
  let string          : String
  let args            : [ Any? ]

  /* processing status */
  var idx             : String.Index
  var currentArgument : Int = 0
  
  /* constructors */

  public init(string: String, arguments: [ Any? ] = []) {
    self.string = string
    self.args   = arguments
    self.idx    = self.string.startIndex
  }

  
  /* main entry */

  /// Parses a qualifier or throws a ``ParserError`` for invalid input.
  public static func parse(_ format: String, _ args: Any?...) throws
                     -> Qualifier
  {
    var parser = Self(string: format, arguments: args)
    return try parser.parse()
  }


  public mutating func parseQualifier() -> Qualifier? {
    do { return try parse() }
    catch ParserError.emptyInput { return nil }
    catch {
      log.error(String(describing: error))
      return nil
    }
  }

  private mutating func parse() throws -> Qualifier {
    guard skipSpaces() else { throw ParserError.emptyInput(string: string) }
    guard let qualifier = try parseCompoundQualifier() else {
      throw parseError("expected qualifier")
    }
    _ = skipSpaces()
    guard idx == string.endIndex else {
      throw parseError("unexpected trailing input")
    }
    return qualifier
  }
  
  /* parsing */

  mutating func parseOneQualifier() throws -> Qualifier? {
    guard skipSpaces() else { return nil } // EOF
    
    /* sub-qualifiers in parenthesis */
    if match("(") { return try parseCompoundQualifierInParenthesis() }
    
    /* NOT qualifier */
    if match(TOK_NOT) { return try parseNotQualifier() }
    
    /* raw SQL qualifier */
    if match(TOK_SQL) { return try parseRawSQLQualifier() }
    
    /* special constant qualifiers */

    if consumeIfMatch(TOK_STAR_TRUE)  { return BooleanQualifier.trueQualifier  }
    if consumeIfMatch(TOK_STAR_FALSE) { return BooleanQualifier.falseQualifier }
    return try parseKeyBasedQualifier()
  }
  
  mutating func nextNonNullStringArgument(_ _pat: String) throws -> String? {
    guard currentArgument < args.count else {
      throw parseError("more format patterns than arguments")
    }
    let arg = args[currentArgument]
    currentArgument += 1 /* consume */
    
    /* process format spec */
    
    let pidx = _pat.index(after: _pat.startIndex)
    switch _pat[pidx] {
      case "K", "s", "i", "d", "f", "@":
        if let arg = arg { return "\(arg)" } // ... toString
        else             { return "nil"    }
      
      case "%":
        throw parseError("not yet supported: %%")
      
      default:
        throw parseError("unknown string format specification: \(_pat)")
    }
  }
  
  mutating func parseKeyBasedQualifier() throws -> Qualifier? {
    // TODO: we need to improve and consolidate the argument handling, but hey,
    //       it works ;-)
    //       Maybe we want to move it to the identifier parsing?
    
    /* some identifier or keyword */
    guard var id = parseIdentifier(onlyBreakOnSpace: false) else {
      return nil /* found no ID, error */
    }
    
    /* process formats */
    if id.count > 1 && id.hasPrefix("%") {
      // the id itself is a format, eg: "%@ LIKE 'Hello*'"
      guard let pid = try nextNonNullStringArgument(id) else { return nil }
      id = pid
    }
    
    if !skipSpaces() {
      /* ok, it was just the ID. We treat this as a boolean kvqualifier,
       * eg: "isArchived"
       */
      return KeyValueQualifier(id, .equalTo, true)
    }
    
    /* check whether the qualifier is closed, that is, whether we are bool */
    
    if match(TOK_AND) || match(TOK_OR) || match(")") {
      /* ok, it was just the ID. We treat this as a boolean kvqualifier,
       * eg: "isArchived AND code > 10"
       *     "(code > 10 AND isArchived) AND is New"
       */
      return KeyValueQualifier(id, .equalTo, true)
    }
    
    /* OK, now we check for operations */
    
    // can be 'IN' or '<' or 'has:'..
    guard var operation = parseOperation() else {
      /* ok, it was just the ID and some spaces, no operation. We treat this as
       * a boolean kvqualifier, eg: "isArchived  "
       */
      return KeyValueQualifier(id, .equalTo, true)
    }
    
    /* process formats */
    
    if operation.count > 1 && operation.hasPrefix("%") {
      // the operation is a pattern, eg: "value %@ 5", "<"
      guard let pid = try nextNonNullStringArgument(operation) else {
        return nil
      }
      operation = pid
    }
    
    /* check for IS NULL and IS NOT NULL */
    
    if operation == "IS" {
      let saveIdx = idx
      
      if skipSpaces() {
        if consumeIfMatch(TOK_NOT) {
          if skipSpaces() {
            if consumeIfMatch(TOK_NULL) {
              return KeyValueQualifier(id, .notEqualTo, nil)
            }
          }
        }
        else if consumeIfMatch(TOK_NULL) {
          return KeyValueQualifier(id, .equalTo, nil)
        }
      }
      
      /* did not match, restore pointer */
      idx = saveIdx
    }
    
    // TBD: special support for "NOT IN" (do a regular IN, then wrap in NotQual)
    
    /* and finally the right hand side (either id or value) */

    guard skipSpaces() else {
      throw parseError(
        "expected value/id after identifier and operation " +
        "(op=\(operation), id=\(id))")
    }
    
    /* process variables ($name) */

    if (match("$")) {
      idx = string.index(after: idx) // consume $
      
      guard let varId = parseIdentifier(onlyBreakOnSpace: false) else {
        throw parseError("expected variable identifier after '$'?!")
      }
      
      let op = ComparisonOperation(string: operation)
      return KeyValueQualifier(id, op, QualifierVariable(key: varId))
    }
    
    /* process value arguments */
    
    if (match("%")) {
      /* Note: we do not support %%, and we do not support arbitrary
       *       strings, like "col_%K" or something like this
       */
      idx = string.index(after: idx) // consume %

      guard idx < string.endIndex else {
        throw parseError("missing format specification after '%'")
      }
      let fspec = string[idx]
      idx = string.index(after: idx) // consume format spec char
      
      /* retrieve argument */
      
      guard currentArgument < args.count else {
        throw parseError("more format patterns than arguments")
      }
      let arg = args[currentArgument]
      currentArgument += 1 /* consume */
      
      /* convert argument */
      
      switch fspec {
        case "@":
          return KeyValueQualifier(id, operation, arg)
        
        case "s":
          if let arg = arg as? String {
            return KeyValueQualifier(id, operation, arg)
          }
          else if let arg = arg {
            return KeyValueQualifier(id, operation, "\(arg)") // hm
          }
          else {
            return KeyValueQualifier(id, .equalTo, nil)
          }
        
        case "d", "i":
          if let arg = arg as? Int {
            return KeyValueQualifier(id, operation, arg)
          }
          else if let arg = arg {
            return KeyValueQualifier(id, operation, Int("\(arg)")) // hm
          }
          else {
            return KeyValueQualifier(id, .equalTo, nil)
          }
        
        case "f":
          if let arg = arg as? Double {
            return KeyValueQualifier(id, operation, arg)
          }
          else if let arg = arg as? Int {
            return KeyValueQualifier(id, operation, Double(arg))
          }
          else if let arg = arg {
            return KeyValueQualifier(id, operation, Double("\(arg)")) // hm
          }
          else {
            return KeyValueQualifier(id, .equalTo, nil)
          }
        
        case "K":
          if let arg = arg as? String {
            return KeyComparisonQualifier(id, operation, arg)
          }
          else if let arg = arg {
            return KeyComparisonQualifier(id, operation, "\(arg)") // hm
          }
          else {
            throw parseError(
              "Argument for %K pattern is nil, needs to be a key!")
          }
        
        case "%":
          throw parseError("not yet supported: %%")
        default:
          throw parseError("unknown format specification: %\(fspec)")
      }
    }
    
    /* process constants */

    if matchConstant() {
      /* KeyValueQualifier */
      let isIN = operation == "IN" || operation == "NOT IN"
      let v = try parseConstant(allowCast: !isIN /* allow cast */)
      
      return KeyValueQualifier(id, operation, v)
    }
    
    /* process identifiers */
    
    guard let rhs = parseIdentifier(onlyBreakOnSpace: false) else {
      throw parseError("expected value/id after identifier and operation?!")
    }
    
    return KeyComparisonQualifier(id, operation, rhs)
  }
  
  mutating func parseNotQualifier() throws -> Qualifier? {
    guard consumeIfMatch(TOK_NOT) else { return nil }
    
    guard skipSpaces() else { throw parseError("missing qualifier after NOT!") }
    
    guard let q = try parseOneQualifier() else { return nil }
    return q.not
  }
  
  mutating func parseCompoundQualifierInParenthesis() throws -> Qualifier? {
    guard consumeIfMatch("(") else { return nil } /* not in parenthesis */
    
    guard skipSpaces() else {
      throw parseError("missing closing parenthesis!")
    }
    
    /* parse qualifier */
    guard let q = try parseCompoundQualifier() else { return nil }
    
    _ = skipSpaces()
    guard consumeIfMatch(")") else {
      throw parseError("missing closing parenthesis!")
    }
    
    return q
  }
  
  mutating func parseCompoundQualifier(minimumPrecedence: Int = 1) throws
                -> Qualifier?
  {
    guard minimumPrecedence <= 2 else { return try parseOneQualifier() }
    guard let lhs =
      try parseCompoundQualifier(minimumPrecedence: minimumPrecedence + 1)
    else { return nil }
    
    var qualifiers : [ Qualifier ]?

    while idx < string.endIndex {
      let operatorStart = idx
      let argumentStart = currentArgument
      guard skipSpaces() else { break }
      if match(")") { break }

      guard var compoundOperator = parseIdentifier(onlyBreakOnSpace: false) else
      {
        throw parseError("could not parse compound operator, index: \(idx)")
      }
      if compoundOperator.count > 1 && compoundOperator.hasPrefix("%") {
        guard let value = try nextNonNullStringArgument(compoundOperator) else {
          return nil
        }
        compoundOperator = value
      }

      let precedence: Int
      switch compoundOperator {
        case STOK_AND: precedence = 2
        case STOK_OR:  precedence = 1
        default:
          throw parseError("unknown compound operator: \(compoundOperator)")
      }
      if precedence != minimumPrecedence {
        idx = operatorStart
        currentArgument = argumentStart
        break
      }

      guard skipSpaces() else {
        throw parseError("expected another qualifier after compound operator " +
                         "(op='\(compoundOperator)')")
      }
      guard let rhs =
        try parseCompoundQualifier(minimumPrecedence: precedence + 1)
       else { return nil }

      if qualifiers == nil { qualifiers = [ lhs, rhs ] }
      else                 { qualifiers?.append(rhs) }
    }

    guard let qualifiers else { return lhs }
    let operation: CompoundQualifier.Operator = minimumPrecedence == 2
                                              ? .and : .or
    return CompoundQualifier(qualifiers: qualifiers, op: operation)
  }
 
  /**
   * Parse something like this:
   * ```
   * SQL[select abc WHERE date_id = $dateId]
   * ```
   *
   * into:
   * ```
   * "select abc WHERE date_id ="
   * ```
   *
   * Note that the SQL strings are converted into RawSQLValue objects so
   * that they do not get quoted as SQL strings during SQL generation.
   */
  mutating func parseRawSQLQualifier() throws -> Qualifier? {
    guard consumeIfMatch(TOK_SQL) else { return nil }
    
    var parts = Array<SQLQualifier.Part>()
    var sql   = ""
    
    var pidx = idx
    while pidx < string.endIndex {
      if string[pidx] == "]" {
        idx = string.index(after: pidx) /* consume ] */
        break
      }
      else if string[pidx] == "$" {
        if !sql.isEmpty {
          parts.append(.rawValue(sql))
          sql.removeAll() /* reset char buffer */
        }
        
        idx = string.index(after: pidx) /* skip "$" */
        let varName = parseIdentifier(onlyBreakOnSpace: false)
        pidx = string.index(before: idx)
          /* will get bumped by next loop iteration */
        
        if let varName = varName {
          parts.append(.variable(varName))
        }
        else {
          throw parseError("could not parse SQL qualifier variable?!")
        }
      }
      else {
        /* regular char */
        sql.append(string[pidx])
      }
      
      pidx = string.index(after: pidx)
    }
    if !sql.isEmpty { parts.append(.rawValue(sql)) }
    
    return SQLQualifier(parts: parts)
  }
 
  /**
   * Parse an identifier. Identifiers do not start with numbers or spaces, they
   * are at least on char long.
   * 
   * @param _onlyBreakOnSpace - read ID until a space is encountered
   * @return String containing the ID or  if not could be found
   */
  mutating func parseIdentifier(onlyBreakOnSpace: Bool) -> String? {
    guard idx < string.endIndex else { return nil } // EOF
    
    guard !_isDigit(string[idx]) else { return nil }
      /* identifiers never start with a digit */
    guard !_isSpace(string[idx]) else { return nil } /* nor with a space */
    
    /* we are extremely tolerant here, everything is allowed as long as it
     * starts w/o a digit. processing ends at the next space.
     */
    var pidx = string.index(after: idx)
    while pidx < string.endIndex {
      if onlyBreakOnSpace {
        if _isSpace(string[pidx]) {
          break
        }
      }
      else if _isIdBreakChar(string[pidx]) { /* Note: this includes spaces */
        break
      }
      
      pidx = string.index(after: pidx)
    }
    
    /* Note: len==0 cannot happen, caught above */
    
    let id = string[idx..<pidx]
    idx = pidx  /* consume */
    return String(id)
  }
  
  /**
   * Parses qualifier operations. If none matches, parseIdentifier is called.
   */
  mutating func parseOperation() -> String? {
    guard canLA(2) else { return nil }
    
    if string[idx] == "=" {
      idx = string.index(after: idx)
      if string[idx] == ">" {
        idx = string.index(after: idx)
        return "=>"
      }
      if string[idx] == "<" {
        idx = string.index(after: idx)
        return "=<"
      }
      return "="
    }
    
    if string[idx] == "!" && string[string.index(after: idx)] == "=" {
      idx = string.index(idx, offsetBy: 2)
      return "!="
    }
    
    if string[idx] == "<" {
      idx = string.index(after: idx)
      if string[idx] == "=" {
        idx = string.index(after: idx)
        return "=<"
      }
      if string[idx] == ">" {
        idx = string.index(after: idx)
        return "<>"
      }
      return "<"
    }
    
    if string[idx] == ">" {
      idx = string.index(after: idx)
      if string[idx] == "=" {
        idx = string.index(after: idx)
        return "=>"
      }
      if string[idx] == "<" {
        idx = string.index(after: idx)
        return "<>"
      }
      return ">"
    }
    
    // Handle "NOT IN" as a single operation
    if match(TOK_NOT) {
      let saveIdx = idx
      idx = string.index(idx, offsetBy: TOK_NOT.count)
      if skipSpaces(), match(TOK_IN) {
        idx = string.index(idx, offsetBy: TOK_IN.count)
        return "NOT IN"
      }
      idx = saveIdx // restore if not "NOT IN"
    }

    // TODO: better an own parser? hm, yes.
    // the following stuff parses things like hasPrefix:, but also IN!
    
    return parseIdentifier(onlyBreakOnSpace: true)
  }
 
  mutating func matchConstant() -> Bool {
    guard idx < string.endIndex else { return false }
    
    if string[idx] == "(" {
      guard skipSpaces() else { return false } // TODO: bug? skip consumes
      return true // no further checks for: ID ')'
    }
    
    if _isDigit(string[idx]) { return true }
    if string[idx] == "'"    { return true }
    if string[idx] == "\""   { return true } // TODO: would be an ID in SQL
    
    if match(TOK_TRUE)  { return true }
    if match(TOK_FALSE) { return true }
    if match(TOK_NULL)  { return true }
    if match(TOK_null)  { return true }
    if match(TOK_nil)   { return true }
    if match(TOK_YES)   { return true }
    if match(TOK_NO)    { return true }
    
    return false
  }
 
  mutating func matchCast() -> Bool {
    guard canLA(2) else { return false } /* at least (a) */
    
    if (string[idx] == "(") {
      guard skipSpaces() else { return false } // TODO: bug? skip consumes
      return true // no further checks for: ID ')'
    }
    
    return false
  }
 
  mutating func parseCast() throws -> String? {
    guard canLA(2)           else { return nil } /* at least (a) */
    guard string[idx] == "(" else { return nil }
    
    guard skipSpaces() else {
      throw parseError("expected class cast identifier after parenthesis!")
    }
    
    guard let castClass = parseIdentifier(onlyBreakOnSpace: false /* on all */)
     else {
      throw parseError("expected class cast identifier after parenthesis!")
     }
    guard skipSpaces() else {
      throw parseError("expected closing parenthesis after class cast!")
    }
    guard consumeIfMatch(")") else {
      throw parseError("expected closing parenthesis after class cast!")
    }
    
    return castClass
  }
 
  /**
   * This parses:
   *
   * - single quoted strings
   * - double quoted strings
   * - numbers
   * - true/false, YES/NO
   * - null/NULL
   *
   * The constant can be prefixed with a cast, eg:
   *
   *     (int)"383"
   *
   * But the casts are not resolved yet ...
   */
  mutating func _parseConstant(allowCast: Bool) throws
       -> Constant?
  {
    let castClass = allowCast ? try parseCast() : nil
    guard idx < string.endIndex else {
      throw parseError("expected value after class cast")
    }
    let v : Constant?
    
    if string[idx] == "\'" {
      v = .string(try parseQuotedString())
    }
    else if string[idx] == "\"" { // TODO: could be a SQL id
      v = .string(try parseQuotedString())
    }
    else if _isDigit(string[idx]) {
      if let n = try parseNumber() {
        switch n {
          case .Int   (let i): v = .int(i)
          case .Double(let i): v = .double(i)
        }
      }
      else { v = nil }
    }
    else if consumeIfMatch(TOK_TRUE) || consumeIfMatch(TOK_YES) {
      v = .bool(true)
    }
    else if consumeIfMatch(TOK_FALSE) || consumeIfMatch(TOK_NO) {
      v = .bool(false)
    }
    else if match("(") {
      /* a plist array after an IN (otherwise a CAST is handled above!) */
      throw parseError("plist array values after IN are not yet supported!")
    }
    else if consumeIfMatch(TOK_NULL) {
      return nil // do not apply casts for nil
    }
    else if consumeIfMatch(TOK_null) {
      return nil // do not apply casts for nil
    }
    else if consumeIfMatch(TOK_nil) {
      return nil // do not apply casts for nil
    }
    else {
      return nil // hm, can't distinguish between this and nil => match..
    }
    
    if let castClass = castClass {
      // TBD: another option might be to support property lists, eg:
      //        code IN ( 'a', 'b', 'c' )
      //      maybe distinguish by checking for an ID?
      
      // TODO: handle casts, eg (Date)'2006-06-10'
      log.warn("not handling cast to '\(castClass)', value: \(v as Optional)")
    }
    return v
  }
  
  enum Constant {
    case string(String)
    case int   (Int)
    case double(Double)
    case bool  (Bool)
    
    var asAny : Any {
      switch self {
        case .string(let v): return v
        case .int   (let v): return v
        case .double(let v): return v
        case .bool  (let v): return v
      }
    }
  }
  
  mutating func parseConstant(allowCast: Bool) throws -> Any? {
    guard let c = try _parseConstant(allowCast: allowCast) else { return nil }
    return c.asAny
  }
 
  mutating func parseQuotedString() throws -> String {
    let quoteChar = string[idx]
    
    /* a quoted string */
    var pos      = string.index(after: idx) /* skip quote */
    let startPos = pos
    guard startPos != string.endIndex else {
      idx = startPos
      throw parseError("quoted string not closed (expected '\(quoteChar)')")
    }
    
    var containsEscaped = false
    
    /* loop until closing quote */
    while pos < string.endIndex && string[pos] != quoteChar {
      if string[pos] == "\\" {
        containsEscaped = true
        pos = string.index(after: pos) /* skip following char */
        if pos == string.endIndex {
          idx = pos
          throw parseError("escape in quoted string not finished!")
        }
      }
      pos = string.index(after: pos)
    }
    
    if pos == string.endIndex { /* syntax error, quote not closed */
      idx = pos
      throw parseError("quoted string not closed (expected '\(quoteChar)')")
    }
    
    idx = string.index(after: pos) /* skip closing quote, consume */
    
    if startPos == pos { /* empty string */
      return ""
    }
    
    if containsEscaped {
      // TODO: implement unescaping in quoted strings
      log.error("unescaping not implemented!")
    }
    return String(string[startPos..<pos])
  }
 
  enum Number {
    case Int(Int)
    case Double(Double)
  }
  mutating func parseNumber() throws -> Number? { // TODO: not just int
    guard idx < string.endIndex else { return nil } // EOF
    guard _isDigit(string[idx]) || string[idx] == "-" else { return nil }
    
    /* we are extremely tolerant here, almost everything is allowed ... */
    var pidx = string.index(after: idx)
    while pidx < string.endIndex {
      if _isIdBreakChar(string[pidx]) || string[pidx] == ")" { break }
      pidx = string.index(after: pidx)
    }
    
    /* Note: len==0 cannot happen, caught above */
    let numstr = string[idx..<pidx]
    idx = pidx // consume
    
    if numstr.contains(".") {
      guard let v = Double(numstr) else {
        throw parseError("failed to parse number: '" + numstr + "'")
      }
      return Number.Double(v)
    }
    else {
      guard let v = Int(numstr) else {
        throw parseError("failed to parse number: '" + numstr + "'")
      }
      return Number.Int(v)
    }
  }
  
  private func parseError(_ reason: String) -> ParserError {
    return .invalidSyntax(
      reason: reason,
      position: string.distance(from: string.startIndex, to: idx),
      string: string)
  }
 
  /* core parsing */
  
  func _isDigit(_ c: Character) -> Bool {
    switch c {
      case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": return true
      default: return false
    }
  }
  func _isSpace(_ c: Character) -> Bool {
    switch c {
      case " ", "\t", "\n", "\r": return true
      default: return false
    }
  }
  func _isIdBreakChar(_ c: Character) -> Bool {
    switch c {
      case " ", "\t", "\n", "\r", "<", ">", "=", "*", "/", "+",
           "-", "(", ")", "]", "!": /* eg NSFileName!="index.html" */
        return true
      default:
        return false
    }
  }

  mutating func skipSpaces() -> Bool {
    while idx < string.endIndex {
      if !_isSpace(string[idx]) {
        return true;
      }
      
      idx = string.index(after: idx)
    }
    return idx < string.endIndex
  }
  
  func la(_ i : Int) -> Character? {
    guard canLA(i) else { return nil }
    return string[string.index(idx, offsetBy: i)]
  }
  
  func match(_ tok: [ Character ]) -> Bool {
    guard canLA(tok.count) else { return false }
    
    var midx = idx
    for c in tok {
      guard c == string[midx] else { return false }
      midx = string.index(after: midx)
    }
    return true
  }
  
  /**
   * Returns true if the current parsing position matches the char. This does
   * NOT consume the char (use consumeIfMatch for that).
   * Example:
   *
   *   if (match(")")) return ...</pre>
   * 
   */
  func match(_ c: Character) -> Bool {
    guard idx < string.endIndex else { return false }
    return string[idx] == c
  }
  
  mutating func consumeIfMatch(_ tok: [ Character ]) -> Bool {
    guard match(tok) else { return false }
    idx = string.index(idx, offsetBy: tok.count)
    return true
  }
  
  mutating func consumeIfMatch(_ c: Character) -> Bool {
    guard match(c) else { return false }
    idx = string.index(after: idx);
    return true
  }
  
  func canLA(_ count : Int) -> Bool {
    return string.canLA(count, startIndex: idx)
  }

  
  /* tokens */
  
  let STOK_AND = "AND"
  let STOK_OR  = "OR"
  
  let TOK_NOT   : [ Character ] = [ "N", "O", "T" ]
  let TOK_NULL  : [ Character ] = [ "N", "U", "L", "L" ]
  let TOK_null  : [ Character ] = [ "n", "u", "l", "l" ]
  let TOK_nil   : [ Character ] = [ "n", "i", "l" ]
  let TOK_TRUE  : [ Character ] = [ "t", "r", "u", "e" ]
  let TOK_FALSE : [ Character ] = [ "f", "a", "l", "s", "e" ]
  let TOK_YES   : [ Character ] = [ "Y", "E", "S" ]
  let TOK_NO    : [ Character ] = [ "N", "O" ]
  let TOK_SQL   : [ Character ] = [ "S", "Q", "L", "[" ]
  let TOK_AND   : [ Character ] = [ "A", "N", "D" ]
  let TOK_OR    : [ Character ] = [ "O", "R" ]
  let TOK_IN    : [ Character ] = [ "I", "N" ]
  
  let TOK_STAR_TRUE  : [ Character ] = [ "*", "t", "r", "u", "e", "*" ]
  let TOK_STAR_FALSE : [ Character ] = [ "*", "f", "a", "l", "s", "e", "*" ]
}

extension String {
  
  func canLA(_ count: Int, startIndex: Index) -> Bool {
    if startIndex == endIndex { return false }
    
    guard count != 0 else { return true } // can always not lookahead
      // this asserts on overflow: string.index(idx, offsetBy: count), so it is
      // no good for range-checks.
    
    // TBD: is there a betta way?
    var toGo   = count
    var cursor = startIndex
    while cursor != endIndex {
      toGo -= 1
      if toGo == 0 { return true }
      cursor = index(after: cursor)
    }
    return toGo == 0
  }
  
}
