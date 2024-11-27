//
//  Logger.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
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
    primaryLog(.Error, msg, values)
  }
  func warn (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Warn, msg, values)
  }
  func log  (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Log, msg, values)
  }
  func info (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Info, msg, values)
  }
  func trace(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Trace, msg, values)
  }
  
}

public enum ZeeQLLoggerLogLevel : Int8 { // cannot nest types in generics
  case Error
  case Warn
  case Log
  case Info
  case Trace
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
    let defaultLevel = ZeeQLLoggerLogLevel.Log
  #else
    let defaultLevel = ZeeQLLoggerLogLevel.Error
  #endif
  let logEnv = ProcessInfo.processInfo.environment["ZEEQL_LOGLEVEL"]?
                 .lowercased()
               ?? ""
  let level : ZeeQLLoggerLogLevel
  
  if      logEnv == "error"        { level = .Error }
  else if logEnv.hasPrefix("warn") { level = .Warn  }
  else if logEnv.hasPrefix("info") { level = .Info  }
  else if logEnv == "trace"        { level = .Trace }
  else if logEnv == "log"          { level = .Log   }
  else { level = defaultLevel }
  
  return ZeeQLPrintLogger(level: level)
}()


// MARK: - Simple Implementation

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

fileprivate let stderrLogLevel : ZeeQLLoggerLogLevel = .Error

public struct ZeeQLPrintLogger : ZeeQLLogger {
  // public, maybe useful for ZeeQL users as well.
  
  let logLevel : ZeeQLLoggerLogLevel
  
  public init(level: ZeeQLLoggerLogLevel = .Error) {
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
      case .Error: return "ERROR: "
      case .Warn:  return "WARN:  "
      case .Info:  return "INFO:  "
      case .Trace: return "Trace: "
      case .Log:   return ""
    }
  }
}
