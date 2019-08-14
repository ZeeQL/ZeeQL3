//
//  SQLForeignKey.swift
//  ZeeQL3
//
//  Created by Helge Hess on 10/06/17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

// Note: intentionally not (yet) public API

extension Relationship {
  
  /**
   * Return the values relevant for the FOREIGN KEY constraint. That is,
   * table-name, and the column names of the sources/destinations.
   *
   * Note: Requires a connected model for proper operation.
   */
  var foreignKey : SQLForeignKey? {
    return SQLForeignKey(relationship: self)
  }

  var isForeignKeyRelationship : Bool {
    guard !isToMany      else { return false }
    guard !joins.isEmpty else { return false }
    return true
  }
  
}

struct SQLForeignKey : Equatable, Hashable, SmartDescription {
  
  let destinationTableName : String
  let sortedJoinColumns    : [ ( String, String ) ]
  let count                : Int
  
  // annotations, ignored by hash/equality
  let relationship         : Relationship // could be multiple!
  
  init?(relationship rs: Relationship) {
    guard !rs.isToMany                          else { return nil }
    guard let destEntity = rs.destinationEntity else { return nil }
    
    self.relationship         = rs
    self.destinationTableName = destEntity.externalNameOrName

    func mapColumns(_ join: Join) -> ( String, String )? {
      let sc = join.source     (in: rs.entity)?.columnNameOrName
      let dc = join.destination(in: rs.entity)?.columnNameOrName
      guard let sourceColumn = sc, let destColumn = dc else { return nil }
      return ( sourceColumn, destColumn )
    }
    let joinColumns = rs.joins.compactMap(mapColumns)

    if joinColumns.count > 1 {
      self.sortedJoinColumns = joinColumns.sorted { lhs, rhs in
        return lhs.0 == rhs.0 ? ( lhs.1 < rhs.1 ) : lhs.0 < rhs.0
      }
    }
    else {
      self.sortedJoinColumns = joinColumns
    }
    
    self.count = sortedJoinColumns.count
  }
  
  public static func ==(lhs: SQLForeignKey, rhs: SQLForeignKey) -> Bool {
    guard lhs.count                == rhs.count else { return false }
    guard lhs.destinationTableName == rhs.destinationTableName
     else { return false }
    for i in 0..<lhs.count {
      let lcs = lhs.sortedJoinColumns[i]
      let rcs = rhs.sortedJoinColumns[i]
      guard lcs.0 == rcs.0 && lcs.1 == rcs.1 else { return false }
    }
    return true
  }
  
  public func hash(into hasher: inout Hasher) {
    // FIXME: what is a proper function?
    guard count > 0 else { return destinationTableName.hash(into: &hasher) }
    destinationTableName  .hash(into: &hasher)
    sortedJoinColumns[0].0.hash(into: &hasher)
  }
  
  public var descriptionPrefix : String { return "ForeignKey:" }
  
  func appendToDescription(_ ms: inout String) {
    // ( target_id ) REFERENCES target( target_id )
    if count == 0 {
      if !destinationTableName.isEmpty { ms += " " + destinationTableName }
      ms += " no-columns?"
    }
    else if count == 1 {
      ms += " "
      ms += sortedJoinColumns[0].0 + " REFERENCES " + destinationTableName
      if sortedJoinColumns[0].0 != sortedJoinColumns[0].1 {
        ms += "(" + sortedJoinColumns[0].1 + ")"
      }
    }
    else {
      ms += " ( "
      ms += sortedJoinColumns.map { $0.0 }.joined(separator: ", ")
      ms += " ) REFERENCES " + destinationTableName + "( "
      ms += sortedJoinColumns.map { $0.0 }.joined(separator: ", ")
      ms += " )"
    }
  }
}
