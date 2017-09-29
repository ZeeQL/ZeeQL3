//
//  ModelSQLizer.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * The ModelSQLizer is the reverse to the FancyModelMaker. It takes a model
 * with no (or partial) external names assigned, and fills them in.
 *
 * Hence it is responsible to make 'fancy' SQL DDL statements.
 *
 * What it does:
 * - it lowercases entity names, a `Person` entity becomes the `person` table
 * - it expands primary keys, a `Person.id` becomes `person.person_id`
 * - it de-camel-cases attribute names: `bankAddress` becomes `bank_address`
 */
open class ModelSQLizer {
  
  public struct Options {
    var includeTableNameForPrimaryKeyID : String? = "id" // 'id' => 'person_id'
    var decamelizeAndInsertString : String? = "_"  // bankAddr => bank_addr
    var lowercaseTableNames                 = true // Person => person
    var lowercaseColumnNames                = true // ID => id
    
    public init() {}
  }
  
  let log : ZeeQLLogger = globalZeeQLLogger
  
  // TODO: IMPLEMENT ME :-)

  /**
   * Add external-names/column-names to model.
   *
   * Note: this patches the model inline!
   */
  open func sqlizeModel(_ model: Model, options: Options = Options()) -> Model {
    // TODO: only convert to Model on-demand
    for entity in model.entities {
      let me : ModelEntity
      if let se = entity as? ModelEntity {
        me = se
      }
      else {
        me = ModelEntity(entity: entity, deep: true)
        if let idx = model.entities.index(where: { $0 === entity }) {
          model.entities[idx] = me
        }
      }
      
      if entity.externalName == nil {
        var tableName = entity.name
        
        if let s = options.decamelizeAndInsertString {
          tableName = tableName.decamelize(insertString: s)
        }
        if options.lowercaseTableNames {
          tableName = tableName.lowercased()
        }
        
        me.externalName = tableName
      }
      
      let tableNamePKey : String? = {
        guard let pkey = options.includeTableNameForPrimaryKeyID
         else { return nil }
        guard let epkeys = entity.primaryKeyAttributeNames else { return nil }
        guard epkeys.contains(pkey)                        else { return nil }
        return pkey
      }()
      
      for attr in entity.attributes {
        guard attr.columnName == nil else { continue }
        
        let ma : ModelAttribute
        if let sa = attr as? ModelAttribute { ma = sa }
        else { ma = ModelAttribute(attribute: attr) }
        
        var columnName : String
        
        if let pkey = tableNamePKey, attr.name == pkey,
           let tableName = me.externalName
        {
          let s = options.decamelizeAndInsertString ?? "_"
          columnName = tableName + s + pkey.lowercased()
        }
        else {
          columnName = attr.name
          
          if let s = options.decamelizeAndInsertString {
            columnName = columnName.decamelize(insertString: s)
          }
        }
        
        if options.lowercaseTableNames {
          columnName = columnName.lowercased()
        }
        
        if me[columnName: columnName] != nil {
          log.error("SQLizer: duplicate colum name:", columnName,
                    "calculated for attribute", ma)
        }
        else {
          ma.columnName = columnName
        }
      }
    }
    
    return model
  }
  
}

extension String {
  
  func decamelize(insertString: String? = nil) -> String {
    guard !self.isEmpty else { return "" }
    var newChars = [ Character ]()
    
    var lastWasLowerOrDigit = false
    for c in characters {
      switch c {
        case "a"..."z", "0"..."9":
          lastWasLowerOrDigit = true
          newChars.append(c)
        
        case "A"..."Z":
          if lastWasLowerOrDigit {
            let s = String(c).lowercased()
            if let ist = insertString, !ist.isEmpty {
              newChars.append(contentsOf: ist.characters)
            }
            newChars.append(s[s.startIndex])
          }
          else {
            newChars.append(c)
          }
          lastWasLowerOrDigit = true
        
        default:
          lastWasLowerOrDigit = false
          newChars.append(c)
      }
    }
    
    guard !newChars.isEmpty else { return self }
    return String(newChars)
  }
  
}
