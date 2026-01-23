//
//  Logger.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * Protocol used by ZeeQL to perform logging. Implement it using your favorite
 * logging framework ...
 *
 * Defaults to a simple Print based logger.
 */
public protocol ZeeQLLogger {
  
  func primaryLog(_ logLevel: ZeeQLLoggerLogLevel, _ msgfunc: () -> String,
                  _ values: [ Any? ] )
  
}

public extension ZeeQLLogger { // Actual logging funcs
  
  func error(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.error, msg, values)
  }
  func warn (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.warn, msg, values)
  }
  func log  (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.log, msg, values)
  }
  func info (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.info, msg, values)
  }
  func trace(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.trace, msg, values)
  }
  
}

public enum ZeeQLLoggerLogLevel : Int8 { // cannot nest types in generics
  case error
  case warn
  case log
  case info
  case trace
}


// MARK: - Global Logger

import class Foundation.ProcessInfo

/**
 * Other objects initialize their logger from this. Can be assigned to
 * something else if you care.
 * Log-level can be set using the `ZEEQL_LOGLEVEL` global.
 */
public var globalZeeQLLogger : ZeeQLLogger = {
  #if DEBUG
    let defaultLevel = ZeeQLLoggerLogLevel.log
  #else
    let defaultLevel = ZeeQLLoggerLogLevel.error
  #endif
  let logEnv = ProcessInfo.processInfo.environment["ZEEQL_LOGLEVEL"]?
                 .lowercased()
               ?? ""
  let level : ZeeQLLoggerLogLevel

  if      logEnv == "error"        { level = .error }
  else if logEnv.hasPrefix("warn") { level = .warn  }
  else if logEnv.hasPrefix("info") { level = .info  }
  else if logEnv == "trace"        { level = .trace }
  else if logEnv == "log"          { level = .log   }
  else { level = defaultLevel }

  return ZeeQLPrintLogger(level: level)
}()


// MARK: - Simple Implementation

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

fileprivate let stderrLogLevel : ZeeQLLoggerLogLevel = .error

public struct ZeeQLPrintLogger : ZeeQLLogger {
  // public, maybe useful for ZeeQL users as well.
  
  let logLevel : ZeeQLLoggerLogLevel
  
  public init(level: ZeeQLLoggerLogLevel = .error) {
    logLevel = level
  }
  
  public func primaryLog(_ logLevel : ZeeQLLoggerLogLevel,
                         _ msgfunc  : () -> String,
                         _ values   : [ Any? ] )
  {
    guard logLevel.rawValue <= self.logLevel.rawValue else { return }
    
    var s = logLevel.logPrefix + msgfunc()
    for v in values {
      s += " "
      if let v = v as? String { s += v }
      else if let v = v as? CustomStringConvertible { s += v.description }
      else if let v = v       { s += " \(v)" }
      else                    { s += "<nil>" }
    }
    
    if logLevel.rawValue <= stderrLogLevel.rawValue {
      s += "\n" // fputs, unlike puts, does not add a newline
      fputs(s, stderr)
    }
    else {
      print(s)
    }
  }
  
}

fileprivate extension ZeeQLLoggerLogLevel {
  
  var logPrefix : String {
    switch self {
      case .error: return "ERROR: "
      case .warn:  return "WARN:  "
      case .info:  return "INFO:  "
      case .trace: return "Trace: "
      case .log:   return ""
    }
  }
}
