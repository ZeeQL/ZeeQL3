//
//  Pluralize.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04.06.17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

public extension String {
  // Inspired by:
  //   https://github.com/rails/rails/blob/master/activesupport/lib/active_support/inflections.rb
  
  var singularized : String {
    // FIXME: case
    
    switch self { // case compare
      // irregular
      case "people":   return "person"
      case "men":      return "man"
      case "children": return "child"
      case "sexes":    return "sex"
      case "moves":    return "move"
      case "zombies":  return "zombie"
      case "staff":    return "staff"
      
      // regular
      case "mice":     return "mouse"
      case "lice":     return "louse"
      case "mouse":    return "mouse"
      case "louse":    return "louse"

      // other
      case "axis",     "axes":     return "axis"
      case "analysis", "analyses": return "analysis"
      
      default: break
    }
    
    let len = self.count

    if len > 2 {
      if self.hasCISuffix("octopi")    { return self.cutoffTrailer(1) + "us" }
      if self.hasCISuffix("viri")      { return self.cutoffTrailer(1) + "us" }
      if self.hasCISuffix("aliases")   { return self.cutoffTrailer(2) }
      if self.hasCISuffix("statuses")  { return self.cutoffTrailer(2) }
      if self.hasCISuffix("oxen")      { return self.cutoffTrailer(2) }
      if self.hasCISuffix("vertices")  { return self.cutoffTrailer(4) + "ex" }
      if self.hasCISuffix("indices")   { return self.cutoffTrailer(4) + "ex" }
      if self.hasCISuffix("matrices")  { return self.cutoffTrailer(3) + "x"  }
      if self.hasCISuffix("quizzes")   { return self.cutoffTrailer(3) }
      if self.hasCISuffix("databases") { return self.cutoffTrailer(1) }
      if self.hasCISuffix("crises")    { return self.cutoffTrailer(2) + "is" }
      if self.hasCISuffix("crises")    { return self }
      if self.hasCISuffix("testes")    { return self.cutoffTrailer(2) + "is" }
      if self.hasCISuffix("testis")    { return self }
      if self.hasCISuffix("shoes")     { return self.cutoffTrailer(1) }
      if self.hasCISuffix("oes")       { return self.cutoffTrailer(2) }
      if self.hasCISuffix("buses")     { return self.cutoffTrailer(2) }
      if self.hasCISuffix("bus")       { return self }
      if self.hasCISuffix("mice")      { return self.cutoffTrailer(3) + "ouse" }
      if self.hasCISuffix("lice")      { return self.cutoffTrailer(3) + "ouse" }
      
      if self.hasCISuffix("xes")       { return self.cutoffTrailer(2) }
      if self.hasCISuffix("ches")      { return self.cutoffTrailer(2) }
      if self.hasCISuffix("sses")      { return self.cutoffTrailer(2) }
      if self.hasCISuffix("shes")      { return self.cutoffTrailer(2) }

      if self.hasCISuffix("ies") && len > 3 {
        if self.hasCISuffix("movies")  { return self.cutoffTrailer(1) }
        if self.hasCISuffix("series")  { return self }
        
        if self.hasCISuffix("quies")   { return self.cutoffTrailer(3) + "y" }

        let cidx = self.index(endIndex, offsetBy: -4)
        let c    = self[cidx]
        if c != "a" && c != "e" && c != "i" && c != "o" && c != "u" && c != "y"
        {
          return self.cutoffTrailer(3) + "y"
        }
      }
      
      if self.hasCISuffix("lves")      { return self.cutoffTrailer(3) + "f" }
      if self.hasCISuffix("rves")      { return self.cutoffTrailer(3) + "f" }

      if self.hasCISuffix("tives")     { return self.cutoffTrailer(1) }
      if self.hasCISuffix("hives")     { return self.cutoffTrailer(1) }
      
      if self.hasCISuffix("ves") && len > 3 {
        let cidx = self.index(endIndex, offsetBy: -4)
        if self[cidx] != "f" { return self.cutoffTrailer(3) + "fe" }
      }
      
      if self.hasCISuffix("sis") {
        if self.hasCISuffix("analysis")    { return self }
        if self.hasCISuffix("basis")       { return self }
        if self.hasCISuffix("diagnosis")   { return self }
        if self.hasCISuffix("parenthesis") { return self }
        if self.hasCISuffix("prognosis")   { return self }
        if self.hasCISuffix("synopsis")    { return self }
        if self.hasCISuffix("thesis")      { return self }
      }
      else if self.hasCISuffix("ses") {
        if self.hasCISuffix("analyses") { return self.cutoffTrailer(3) + "sis" }
        if self.hasCISuffix("bases")    { return self.cutoffTrailer(3) + "sis" }
        if self.hasCISuffix("diagnoses") {
          return self.cutoffTrailer(3) + "sis"
        }
        if self.hasCISuffix("parentheses") {
          return self.cutoffTrailer(3) + "sis"
        }
        if self.hasCISuffix("prognoses") {
          return self.cutoffTrailer(3) + "sis"
        }
        if self.hasCISuffix("synopses") { return self.cutoffTrailer(3) + "sis" }
        if self.hasCISuffix("theses")   { return self.cutoffTrailer(3) + "sis" }
      }
      
      if self.hasCISuffix("ta")        { return self.cutoffTrailer(2) + "um" }
      if self.hasCISuffix("ia")        { return self.cutoffTrailer(2) + "um" }
      if self.hasCISuffix("news")      { return self }
    }
    
    if self.hasCISuffix("ss") { return self.cutoffTrailer(2) }
    if self.hasCISuffix("s")  { return self.cutoffTrailer(1) }
  
    return self
  }

  var pluralized : String {
    // FIXME: case
    
    switch self {
      // irregular
      case "person": return "people"
      case "man":    return "men"
      case "child":  return "children"
      case "sex":    return "sexes"
      case "move":   return "moves"
      case "zombie": return "zombies"
      case "staff":  return "staff"
      
      // regular
      case "mice":   return "mice"
      case "lice":   return "lice"
      case "mouse":  return "mice"
      case "louse":  return "lice"
      
      default: break
    }
    
    if self.hasCISuffix("quiz")   { return self + "zes" }
    if self.hasCISuffix("oxen")   { return self }
    if self.hasCISuffix("ox")     { return self + "en" }

    if self.hasCISuffix("matrix") {
      return self.replaceSuffix("matrix", "matrices")
    }
    if self.hasCISuffix("vertex") {
      return self.replaceSuffix("vertex", "vertices")
    }
    if self.hasCISuffix("index") { return self.replaceSuffix("index", "indices") }

    if self.hasCISuffix("ch")     { return self + "es" }
    if self.hasCISuffix("ss")     { return self + "es" }
    if self.hasCISuffix("sh")     { return self + "es" }
    
    if self.hasCISuffix("quy")    { return self.replaceSuffix("quy", "quies") }
    if self.hasCISuffix("y") {
      if self.count > 2 {
        let idx = self.index(self.endIndex, offsetBy: -2)
        let cbY = self[idx]
        switch cbY {
          // https://www.youtube.com/watch?v=gUrJKN7F_so
          case "a", "e", "i", "o", "u": break
          default: return self.replaceSuffix("y",  "ies")
        }
        if self.hasCISuffix("ry")   { return self.replaceSuffix("ry",  "ries")  }
      }
    }
    
    if self.hasCISuffix("hive")   { return self + "hives" }
    
    // TODO: (?:([^f])fe|([lr])f) => '\1\2ves'
    
    if self.hasCISuffix("sis")    { return self + "ses" } // TODO: replace?

    if self.hasCISuffix("ta")     { return self }
    if self.hasCISuffix("ia")     { return self }
    
    if self.hasCISuffix("tum")    { return self.replaceSuffix("tum", "ta") }
    if self.hasCISuffix("ium")    { return self.replaceSuffix("ium", "ia") }

    if self.hasCISuffix("buffalo") {
      return self.replaceSuffix("buffalo", "buffaloes")
    }
    if self.hasCISuffix("tomato") {
      return self.replaceSuffix("tomato", "tomatoes")
    }
    
    if self.hasCISuffix("bus")    { return self.replaceSuffix("bus", "buses") }

    if self.hasCISuffix("alias")  { return self + "es" }
    if self.hasCISuffix("status") { return self + "es" }

    if self.hasCISuffix("octopi")  { return self }
    if self.hasCISuffix("viri")    { return self }
    if self.hasCISuffix("octopus") {
      return self.replaceSuffix("octopus", "octopi")
    }
    if self.hasCISuffix("virus")   { return self.replaceSuffix("virus", "viri") }
    
    if self == "axis"   { return "axes"   }
    if self == "testis" { return "testes" }
    
    if self.hasCISuffix("s") { return self }

    return self + "s"
  }
}

fileprivate extension String {
  
  func hasCIPrefix(_ s: String) -> Bool { // urks
    return lowercased().hasPrefix(s.lowercased())
  }
  func hasCISuffix(_ s: String) -> Bool { // urks
    return lowercased().hasSuffix(s.lowercased())
  }
  
  func cutoffTrailer(_ count: Int) -> String {
    guard self.count >= count else { return self }
    let endIdx = self.index(endIndex, offsetBy: -count)
    return String(self[startIndex..<endIdx])
  }
  
  func replaceSuffix(_ suffix: String, _ with: String) -> String {
    guard hasSuffix(suffix) else { return self }
    
    let endIdx = self.index(endIndex, offsetBy: -(suffix.count))
    return self[startIndex..<endIdx] + with
  }
}
