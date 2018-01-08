//
//  ModelLoader.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.URL
import CoreFoundation

/**
 * Load `Model` objects from files (vs. from the database or a code declaration)
 *
 * This version supports the format emitted by the CoreData modeling
 * application in Xcode.
 */
open class ModelLoader {

  let log : ZeeQLLogger = globalZeeQLLogger
  
  public enum Error : Swift.Error {
    case CouldNotLoadFile(url: URL, error: Swift.Error?)
    case InvalidPath(String)
    case InvalidFileFormat
    
    case SubclassResponsibility
    
    case CompiledModelsNotYetSupported
    
    case TODO(String)
  }
  
  public static func loadModel(from path: String) throws -> Model {
    guard !path.isEmpty     else { throw Error.InvalidPath(path) }
    
    let url = URL(fileURLWithPath: path)
    guard !url.path.isEmpty else { throw Error.InvalidPath(path) }
    
    return try loadModel(from: url)
  }
  
  public static func loadModel(from url: URL) throws -> Model {
    // peek at files/directories to load other model types
    let loader = CoreDataModelLoader()
    return try loader.loadModel(from: url)
  }
  
  
  // MARK: - Main Entrypoint
  
  open func loadModel(from url: URL) throws -> Model {
    throw Error.SubclassResponsibility
  }
  
}


import Foundation

open class CoreDataModelLoader : ModelLoader {
  // An actual implementation for CoreData .xcdatamodeld/.xcdatamodel
  
  // TODO: optimize performance, naive implementation
  
  enum Style {
    /// Use the schema used by CD itself - with those nize Z_ / Z names :-)
    /// Also add the maintenance tables?
    case CoreDataDatabase
    
    /// Create a model which makes sense in ZeeQL setups
    /// - add 'id' primary key, auto-increment
    case ZeeQLDatabase
  }
  
  let style = Style.ZeeQLDatabase
  
  struct ToManyEntry {
    let entity        : Entity
    let relationship  : ModelRelationship
    let inverseName   : String
    let inverseEntity : String
  }
  var toManyRelationshipFixups = [ ToManyEntry ]()
  
  
  // MARK: - XML Parsing
  
  final func boolValue(_ v: Any?, default: Bool = false) -> Bool {
    guard let v = v else { return `default` }
    if let b = v as? Bool { return b }
    if let i = v as? Int  { return i != 0 }
    let s = ((v as? String) ?? String(describing: v)).lowercased()
    return s == "true" || s == "yes" || s == "1"
  }
  
  open func loadDataModelContents(from xml: XMLDocument) throws -> Model {
    guard let root = xml.rootElement(), root.name == "model" else {
      throw Error.InvalidFileFormat
    }

    toManyRelationshipFixups.removeAll()
    var entities = [ Entity ]()
    
    // scan for entities
    for element in root.childElementsWithName("entity") {
      if let entity = loadEntity(from: element) {
        entities.append(entity)
      }
    }
    
    let model = Model(entities: entities)

    fixupToMany(in: model)
    
    for node in root.childElementsWithName("fetchRequest") {
      _ = loadFetchSpecification(from: node, into: model)
    }
    
    for _ in root.childElementsWithName("configurations") {
      // TODO: process configurations (@name + <memberEntity name="entity"/>)
    }
    
    return model
  }
  
  func fixupToMany(in model: Model) {
    for entry in toManyRelationshipFixups {
      guard let destEntity = model[entity: entry.inverseEntity]
       else {
        log.warn("did not find inverse entity of relationship:", entry)
        continue
       }
      entry.relationship.destinationEntity = destEntity // hook up, safe work
      
      guard let revRelship = destEntity[relationship: entry.inverseName]
       else {
        log.warn("did not find inverse of relationship:", entry,
                 "in", destEntity)
        continue
       }
      
      let inverseJoins = revRelship.joins.map { $0.inverse }
      entry.relationship.joins = inverseJoins
    }
  }

  @discardableResult
  func loadFetchSpecification(from xml: XMLElement, into model: Model)
       -> FetchSpecification?
  {
    // TODO: 
    // faulting stuff:
    // - returnObjectsAsFaults
    // - fetchBatchSize
    // Hierarchies:
    // - includeSubentities
    // State:
    // - includesPendingChanges
    
    assert(xml.name == "fetchRequest")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"], let entityName = attrs["entity"]
     else {
      log.warn("fetchspec has no name or entity:", xml)
      return nil
     }
    
    guard let entity = model[entity: entityName] as? ModelEntity
     else {
      log.warn("did not find entity of fetchspec:", entityName, xml)
      return nil
     }
    
    let q : Qualifier?
    if let qs = attrs["predicateString"] { q = qualifierWith(format: qs) }
    else                                 { q = nil                       }

    let limit : Int?
    if let l = attrs["fetchLimit"], !l.isEmpty { limit = Int(l) }
    else                                       { limit = nil    }
    
    let sos   : [ SortOrdering ]? = nil
    var fs = ModelFetchSpecification(entity: entity, qualifier: q,
                                     sortOrderings: sos, limit: limit)
    
    fs.usesDistinct = boolValue(attrs["returnDistinctResults"])
    
    if let fs = entity.fetchSpecifications[name] {
      log.warn("duplicate fetchspecs for name:", name, "in entity:", entity, fs)
    }
    
    entity.fetchSpecifications[name] = fs
    return fs
  }
  
  func loadEntity(from xml: XMLElement) -> Entity? {
    assert(xml.name == "entity")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] ?? attrs["representedClassName"]
     else { return nil }
    
    let entity = ModelEntity(name: name)
    
    if let v = attrs["elementID"], !v.isEmpty { entity.elementID          = v }
    if let v = attrs["representedClassName"]  { entity.className          = v }
    if let v = attrs["codeGenerationType"]    { entity.codeGenerationType = v }
    
    // support 'externalName' in userdata
    var ud = loadUserInfo(from: xml.firstChildElementWithName("userInfo"))
    if let extName = ud.removeValue(forKey: "externalName"), !extName.isEmpty {
      entity.externalName = extName
    }
    
    var idAttribute : Attribute? = nil
    for attribute in xml.childElementsWithName("attribute") {
      guard let attr = loadAttribute(from: attribute) else { continue }
      entity.attributes.append(attr)
      if attr.name == "id" { idAttribute = attr }
    }
    
    var toManyRelships = [ ( ModelRelationship, XMLElement ) ]()
    for rs in xml.childElementsWithName("relationship") {
      guard let ( attr, relship ) = loadRelationship(from: rs, entity: entity)
         else { continue }
      
      if let attr = attr { entity.attributes.append(attr) }
      entity.relationships.append(relship)
      
      // remember for inverse processing
      if relship.isToMany { toManyRelships.append((relship, rs)) }
    }
    
    addPrimaryKeyIfNecessary(to: entity, idAttribute: idAttribute)
    
    for ( toManyRS, node ) in toManyRelships {
      let attrs = node.attributesAsDict
      
      guard let iname = attrs["inverseName"], !iname.isEmpty
       else {
        log.warn("Consistency Error:", toManyRS.name, "relationship does not",
                 "have an inverse, this is an advanced setting")
        continue
       }
      
      let ient = attrs["inverseEntity"] ?? toManyRS.destinationEntityName
      let entry = ToManyEntry(entity: entity, relationship: toManyRS,
                              inverseName: iname,
                              inverseEntity: ient ?? "ERROR")
      toManyRelationshipFixups.append(entry)
    }
    
    return entity
  }
  
  func addPrimaryKeyIfNecessary(to entity   : ModelEntity,
                                idAttribute : Attribute? = nil)
  {
    if style == .ZeeQLDatabase {
      // Add primary key, those are not usually configured in CoreData. Though
      // you can add an 'id' attribute and we consider that the primary.
      if idAttribute == nil &&
         (entity.primaryKeyAttributeNames?.isEmpty ?? true)
      {
        let pkeyAttr = ModelAttribute(name: "id", allowsNull: false)
        pkeyAttr.isAutoIncrement = true // TBD. CD has a separate sequence
        
        entity.attributes.insert(pkeyAttr, at: 0)
        // TODO: adjust classProperties accordingly (w/o id to mirror CD)
        
        entity.primaryKeyAttributeNames = [ pkeyAttr.name ]
      }
      
      if entity.primaryKeyAttributeNames?.isEmpty ?? true,
         let idAttribute = idAttribute
      {
        entity.primaryKeyAttributeNames = [ idAttribute.name ]
      }
    }
  }
  
  func loadAttribute(from xml: XMLElement) -> Attribute? {
    // TODO: add support for minValueString/maxValueString
    // TODO: add support for 'indexed'
    assert(xml.name == "attribute")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] else { return nil }
    
    // Note: we don't care about usesScalarValueType
    let attribute = ModelAttribute(name: name)
    let allowsNull       = boolValue(attrs["optional"])
    attribute.allowsNull = allowsNull
    
    if let v = attrs["elementID"], !v.isEmpty { attribute.elementID = v }
    
    if let attrType = attrs["attributeType"], !attrType.isEmpty {
      let lc = attrType.lowercased()
      
      if lc == "string" {
        attribute.valueType = allowsNull ? Optional<String>.self : String.self
      }
      else if lc.hasPrefix("int") { // funny, ?: doesn't work here
        if attrType.hasSuffix("16") {
          if allowsNull { attribute.valueType = Optional<Int16>.self }
          else          { attribute.valueType = Int16.self           }
        }
        else if attrType.hasSuffix("32") {
          if allowsNull { attribute.valueType = Optional<Int32>.self }
          else          { attribute.valueType = Int32.self           }
        }
        else if attrType.hasSuffix("64") {
          if allowsNull { attribute.valueType = Optional<Int64>.self }
          else          { attribute.valueType = Int64.self           }
        }
        else {
          if allowsNull { attribute.valueType = Optional<Int>.self }
          else          { attribute.valueType = Int.self           }
        }
      }
      else if lc == "date" {
        attribute.valueType = allowsNull ? Optional<Date>.self : Date.self
      }
      else if lc == "binary" || lc ==  "data" {
        attribute.valueType = allowsNull ? Optional<Data>.self : Data.self
      }
      else if lc == "decimal" {
        // TODO: 'usesScalarValueType=YES'
        if allowsNull { attribute.valueType = Optional<Decimal>.self }
        else          { attribute.valueType = Decimal.self           }
      }
      else if lc.hasPrefix("bool") {
        attribute.valueType = allowsNull ? Optional<Bool>.self : Bool.self
      }
      else if lc.hasPrefix("transformable") {
        // valueTransformerName="xx"
        // customClassName="xx"
        log.warn("unsupported attr type in CoreData model: ", attrType)
      }
      else {
        log.warn("unsupported attr type in CoreData model: ", attrType)
      }
    }
    
    return attribute
  }
  
  func loadRelationship(from xml: XMLElement, entity: Entity)
       -> ( Attribute?, ModelRelationship )?
  {
    // TODO: Add support 'ordered=YES/NO'
    
    assert(xml.name == "relationship")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] else { return nil }
    
    let relship = ModelRelationship(name: name, source: entity)
    relship.isToMany   = boolValue(attrs["toMany"])
    
    if let de = attrs["destinationEntity"], !de.isEmpty {
      relship.destinationEntityName = de
    }

    if let v = attrs["minCount"], let num = Int(v) { relship.minCount = num }
    if let v = attrs["maxCount"], let num = Int(v) { relship.maxCount = num }
    
    if let delrule = attrs["deletionRule"], !delrule.isEmpty {
      // nullify
      let lc = delrule.lowercased()
      
      if      lc.hasPrefix("null")    { relship.deleteRule = .nullify      }
      else if lc.hasPrefix("cascade") { relship.deleteRule = .cascade      }
      else if lc.hasPrefix("deny")    { relship.deleteRule = .deny         }
      else if lc.hasPrefix("no")      { relship.deleteRule = .noAction     }
      else if lc.hasSuffix("default") { relship.deleteRule = .applyDefault }
      else { log.warn("unsupported CoreData delete rule:", lc) }
    }
    
    let attributeOpt : Attribute?
    if relship.isToMany {
      attributeOpt = nil // the fkey lives in the reverse, we do that later
    }
    else {
      // 'person' => 'personId'
      let attributeName = name + foreignKeyRelationshipSuffix
      
      let attribute = ModelAttribute(name: attributeName)

      if let v = attrs["elementID"], !v.isEmpty { attribute.elementID = v }
      
      let allowsNull       = boolValue(attrs["optional"])
      attribute.allowsNull = allowsNull
      
      relship.joins = [ Join(source      : attributeName,
                             destination : primaryKeyAttributeName) ]
      attributeOpt = attribute
    }
    
    return ( attributeOpt, relship )
  }
  
  let primaryKeyAttributeName      = "id"
  let foreignKeyRelationshipSuffix = "Id"
  
  func loadUserInfo(from xml: XMLElement?) -> [ String : String ] {
    guard let xml = xml else { return [:] }
    
    var userInfo = [ String : String ]()
    
    for element in xml.childElementsWithName("entry") {
      let attrs = element.attributesAsDict
      guard let name  = attrs["name"], !name.isEmpty else { continue }
      guard let value = attrs["value"]               else { continue }
      
      // TBD: could be arrays?
      userInfo[name] = value
    }
    
    return userInfo
  }
  
  
  
  // MARK: - File System Lookup

  let fm = FileManager.default
  
  override open func loadModel(from url: URL) throws -> Model {
    /*
     - abc.xcdatamodeld/
       - .xccurrentversion // proplist
       - abc.xcdatamodel/
         - contents
     */
    var isDirectory : ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      throw Error.CouldNotLoadFile(url:url, error: nil) // wrap
    }
    
    // it is a file
    if !isDirectory.boolValue {
      return try loadDataModelContents(from: url)
    }
    
    // it is a directory

    let contentsURL = url.appendingPathComponent("contents", isDirectory: false)
    if fm.fileExists(atPath: contentsURL.path) {
      // an .xcdatamodel (contains the 'contents' file)
      return try loadDataModel(from: url)
    }
    
    let contents : [ String ]
    do {
      contents = try fm.contentsOfDirectory(atPath: url.path)
    }
    catch {
      throw Error.CouldNotLoadFile(url:url, error: error) // wrap
    }
    
    let hasDataModel = contents.contains {
      $0.hasSuffix(".xcdatamodel") || $0.hasSuffix(".mom")
    }
    guard hasDataModel else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    return try loadDataModelDirectory(from: url)
  }
  
  open func loadDataModelDirectory(from url: URL, versionName v: String? = nil)
              throws -> Model
  {
    var versionName : String? = nil
    
    if let v = v {
      versionName = v
    }
    else { // determine version
      let versionFileURL = url.appendingPathComponent(".xccurrentversion",
                                                      isDirectory: false)
      if fm.fileExists(atPath: versionFileURL.path) {
        let data  = try Data(contentsOf: versionFileURL)
        let plist = try? PropertyListSerialization
                           .propertyList(from: data, options: [], format: nil)
        if let dict = plist as? [ String : Any] {
          versionName = dict["_XCCurrentVersionName"] as? String
        }
      }
      
      if versionName == nil {
        let contents : [ String ]
        do {
          contents = try fm.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".xcdatamodel") || $0.hasSuffix(".mom") }
        }
        catch {
          throw Error.CouldNotLoadFile(url:url, error: error) // wrap
        }
        guard !contents.isEmpty else {
          throw Error.CouldNotLoadFile(url:url, error: nil)
        }
        
        // just pick the first :-) FIXME: sort by modification date?
        if contents.count > 1 {
          log.warn("data model directory contains multiple files,",
                   "but no version info:", url)
        }
        versionName = contents[0]
      }
    }
    
    guard let filename = versionName, !filename.isEmpty
     else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
     }
    
    let dmURL = url.appendingPathComponent(filename)
    return try loadDataModel(from: dmURL)
  }
  
  open func loadDataModel(from url: URL) throws -> Model {
    var isDirectory : ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      throw Error.CouldNotLoadFile(url:url, error: nil) // wrap
    }

    // it is a file
    if !isDirectory.boolValue {
      return try loadDataModelContents(from: url)
    }
    
    let contentsURL = url.appendingPathComponent("contents", isDirectory: false)
    guard fm.fileExists(atPath: contentsURL.path) else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    return try loadDataModelContents(from: contentsURL)
  }
  
  
  // MARK: - Compiled models
  
  struct RelshipInfo {
    var attribute : ModelAttribute?
    var relship   : ModelRelationship
  }
  
  open func loadCompiledModel(from url: URL) throws -> Model {
    // TBD: I think this only makes limited sense and more of a workaround
    //      for Xcode's behaviour when building for iOS. The 'compiled' model
    //      also ends up being bigger ...
    //      Presumably we should rather find ways to ship the source xcdatamodel
    //      on iOS w/o triggering the 'compiler'.
    //
    // Instead finish up the little XMLDocument parser for iOS.
    //
    // This decodes the NSKeyedArchiver variant of the model. We could just
    // unarchive, but that would imply we need to link to CoreData.
    // So rather just load the property list, it ain't that hard.
    // The only real 'hack' being the CFKeyedArchiverUID description that is
    // used (as this doesn't seem to be a public class).
    toManyRelationshipFixups.removeAll()
    
    let data  = try Data(contentsOf: url)
    let plist = try? PropertyListSerialization
                       .propertyList(from: data, options: [], format: nil)
    
    var idToObject = [ Int : Any ]()
    
    func textDecodeObjectID(_ key: Any?) -> Int? {
      guard let o = key else {
        return nil
      }
      
      // and here comes the hack which can break any time ;-)
      let s = String(describing: o)
      assert(s.hasPrefix("<CFKeyedArchiverUID"))
        // this class is not public? we are not accessing the class by name,
        // we just decode its name
      
      guard let range = s.range(of: "value = ") else {
        assert(s.range(of: "value = ") != nil, "did not find value in UID")
        return nil
      }
      
      let startIdx = range.upperBound
      var idx = startIdx
      while idx < s.endIndex {
        #if swift(>=3.2)
          let c = s[idx]
        #else
          let c = s.characters[idx]
        #endif
        switch c {
          case "0"..."9":
            idx = s.index(after: idx)
          default:
            #if swift(>=4.0)
              let num = String(s[startIdx..<idx])
            #else
              let num = s[startIdx..<idx]
            #endif
            guard let i = Int(num) else {
              return nil
            }
            return i
        }
      }
      assert(false, "expected number")
      return nil
    }
    func textDecodeObjectIDs(_ key: Any?) -> [ Int ]? {
      guard let o     = key else { return nil }
      guard let array = o as? [ Any ] else {
        assert(false, "expected array!, got: \(o)")
        return nil
      }
      
      return array.flatMap(textDecodeObjectID)
    }
    
    guard let plistDict = plist as? Dictionary<String, Any>,
          plistDict["$archiver"] as? String ?? "" == "NSKeyedArchiver",
          plistDict["$version"]  as? Int    ?? 0  ==  100000,
          let topDict = plistDict["$top"] as? Dictionary<String, Any>
     else { throw Error.CouldNotLoadFile(url:url, error: nil) }

    guard let eRootID = textDecodeObjectID(topDict["root"]) else {
      assert(false, "did not find root")
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    guard let objects = plistDict["$objects"] as? [ Any ] else {
      assert(false, "did not find objects array")
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }

    
    func decodeObject(index: Int, class clazz: String, values: [ String : Any ],
                      depth: Int = 0) -> Any?
    {
      switch clazz {
        case "NSManagedObjectModel":
          // NSVersionIdentifiers
          let model = Model(entities: [])
          idToObject[index] = model
          if let id = textDecodeObjectID(values["NSEntities"]) {
            if let nameToInfo = decodeObject(index: id, depth: depth + 1)
                                  as? Dictionary<String, Entity>
            {
              for entity in nameToInfo.values {
                model.entities.append(entity)
              }
            }
          }
          if let id = textDecodeObjectID(values["NSFetchRequestTemplates"]) {
            if let fetchRequests = decodeObject(index: id, depth: depth + 1)
                                     as? Dictionary<String, FetchSpecification>
            {
              for ( name, fs ) in fetchRequests {
                if let entity = fs.entity as? ModelEntity {
                  entity.fetchSpecifications[name] = fs
                }
                else if let entityName = fs.entityName {
                  if let entity = model[entity: entityName] as? ModelEntity {
                    entity.fetchSpecifications[name] = fs
                  }
                  else {
                    assert(false, "did nit find entity: \(entityName)")
                  }
                }
                // else: fetch spec has no entity ...
              }
            }
          }
          return model
        
        case "NSEntityDescription":
          guard let id   = textDecodeObjectID(values["NSEntityName"]),
                let name = decodeObject(index: id, depth: depth + 1) as? String
           else {
            assert(false, "entity has no name? \(values)")
            return nil
           }
          
          let entity = ModelEntity(name: name)
          idToObject[index] = entity
          
          if let i = textDecodeObjectID(values["NSClassNameForEntity"]),
             let v = decodeObject(index: i, depth: depth + 1) as? String
          {
            entity.className = v
          }
          if let i = textDecodeObjectID(values["NSRenamingIdentifier"]),
             let v = decodeObject(index: i, depth: depth + 1) as? String
          {
            entity.elementID = v
          }

          if let i = textDecodeObjectID(values["NSProperties"]),
             let props = decodeObject(index: i, depth: depth + 1)
                          as? Dictionary<String, Any>
          {
            for prop in props.values {
              if let attribute = prop as? Attribute {
                entity.attributes.append(attribute)
              }
              else if let relship = prop as? Relationship {
                entity.relationships.append(relship)
              }
              else if let relship = prop as? RelshipInfo {
                if let attribute = relship.attribute {
                  entity.attributes.append(attribute)
                }
                entity.relationships.append(relship.relship)
              }
            }
          }
          
          // TODO: scan for 'id' attribute
          addPrimaryKeyIfNecessary(to: entity, idAttribute: nil)
          
          // TODO: NSUserInfo, NSSubentities, NSSuperentity
          return entity
        
        case "NSAttributeDescription":
          guard let id   = textDecodeObjectID(values["NSPropertyName"]),
                let name = decodeObject(index: id, depth: depth + 1) as? String
           else {
            assert(false, "attribute has no name? \(values)")
            return nil
           }
          
          let attribute = ModelAttribute(name: name)
          idToObject[index] = attribute

          // TODO: NSValueTransformerName, _P
          // TODO: Ints: NSAttributeType(700 for NSString), NSFlagsKey
          
          if let opt = values["NSIsOptional"] as? Int {
            attribute.allowsNull = opt != 0
          }
          
          if let i = textDecodeObjectID(values["NSRenamingIdentifier"]),
             let v = decodeObject(index: i, depth: depth + 1) as? String
          {
            attribute.elementID = v
          }
          
          if let i = textDecodeObjectID(values["NSAttributeValueClassName"]),
             let v = decodeObject(index: i, depth: depth + 1) as? String
          {
            switch v {
              case "NSString": attribute.valueType = String.self
              default: log.error("add value type: \(v)")
            }
          }
          
          if let i = textDecodeObjectID(values["NSDefaultValue"]),
             let v = decodeObject(index: i, depth: depth + 1)
          {
            attribute.defaultValue = v
          }
          
          return attribute
        
        case "NSRelationshipDescription":
          // this is both, the attribute, the join and the relationship
          
          guard let id   = textDecodeObjectID(values["NSPropertyName"]),
                let name = decodeObject(index: id, depth: depth + 1) as? String
           else {
            assert(false, "relationship has no name? \(values)")
            return nil
           }
          
          guard let e      = textDecodeObjectID(values["NSEntity"]),
                let entity = decodeObject(index: e, depth: depth + 1) as? Entity
           else {
             assert(false, "relationship has no entity? \(values)")
             return nil
           }
          
          let relship   = ModelRelationship(name: name, source: entity)
          var info      = RelshipInfo(attribute: nil, relship: relship)
          idToObject[index] = info
          
          if values["NSIsOrdered"] != nil {
            // =1. doesn't matter, the pure existence says it is toMany?
            relship.isToMany = true
          }
          
          if let i = textDecodeObjectID(values["_NSDestinationEntityName"]),
             let v = decodeObject(index: i, depth: depth + 1) as? String
          {
            relship.destinationEntityName = v
          }
          else if let i = textDecodeObjectID(values["NSDestinationEntity"]),
                  let v = decodeObject(index: i, depth: depth + 1) as? Entity
          {
            relship.destinationEntityName = v.name
              // let connect do the actual lookup of the unique model object
          }
          
          if let i = values["NSDeleteRule"] as? Int {
            switch i {
              case 0: relship.deleteRule = .noAction
              case 1: relship.deleteRule = .nullify
              case 2: relship.deleteRule = .cascade
              case 3: relship.deleteRule = .deny
              default:
                log.error("unsupported delete-rule value in:", relship)
            }
          }
          if let i = values["NSMinCount"] as? Int, i > 0 {
            relship.minCount = i
          }
          if let i = values["NSMaxCount"] as? Int, i > 0 {
            relship.maxCount = i
          }

          if !relship.isToMany { // toOne
            // 'person' => 'personId'
            let attributeName = name + foreignKeyRelationshipSuffix
            
            let attribute = ModelAttribute(name: attributeName)
            
            if let i = textDecodeObjectID(values["NSRenamingIdentifier"]),
               let v = decodeObject(index: i, depth: depth + 1) as? String
            {
              attribute.elementID = v
            }
            
            if let opt = values["NSIsOptional"] as? Int {
              attribute.allowsNull = opt != 0
            }
            
            relship.joins = [ Join(source      : attributeName,
                                   destination : primaryKeyAttributeName) ]
            info.attribute = attribute
          }
          else {
            if let i = textDecodeObjectID(values["_NSInverseRelationshipName"]),
               let iname = decodeObject(index: i, depth: depth + 1) as? String
            {
              let ient  = relship.destinationEntityName
              let entry = ToManyEntry(entity: entity, relationship: relship,
                                      inverseName: iname,
                                      inverseEntity: ient ?? "ERROR")
              toManyRelationshipFixups.append(entry)
            }
            else {
              log.warn("Consistency Error:", relship.name,
                       "relationship does not",
                       "have an inverse, this is an advanced setting")
            }
          }
          
          return info

        case "NSFetchRequest":
          var fs = ModelFetchSpecification()
          idToObject[index] = fs
          
          // FIXME: those are not properly reflected in the compiled model?
          if let i = values["NSFetchOffset"] as? Int {
            if i > 0 { fs.fetchOffset = i }
          }
          if let i = values["NSFetchLimit"]  as? Int {
            if i > 0 { fs.fetchLimit  = i }
          }
          
          guard let e      = textDecodeObjectID(values["NSEntity"]),
                let entity = decodeObject(index: e, depth: depth + 1) as? Entity
           else {
             assert(false, "fetch-request has no entity? \(values)")
             return nil
           }
          
          fs.entity = entity
          
          log.warn("not decoding fetch request properly yet ...")
          /* TODO:
           ints: NSBatchSize, NSFetchRequestFlags, NSHasFetchRequestFlags,
                 NSResultType(0 = objects, pkeys, records)
           objects:
             - NSPredicate       // most important
             - NSSortDescriptors // that too ;-)
             - NSHavingPredicate // ??
             - NSRelationshipKeyPathsForPrefetching
             - NSValuesToFetch
             - NSValuesToGroupBy
           */
          idToObject[index] = fs // this is a value object
          return fs
        
        case "NSMutableDictionary", "NSDictionary":
          guard let keyIDs   = textDecodeObjectIDs(values["NS.keys"]),
                let valueIDs = textDecodeObjectIDs(values["NS.objects"])
           else {
            // or rather error?
            return Dictionary<String, Any>()
           }
        
          let keys    = decodeObjects(indices: keyIDs,   depth: depth + 1)
          let objects = decodeObjects(indices: valueIDs, depth: depth + 1)
          assert(keys.count == objects.count)
          guard keys.count == objects.count else { return nil }
          
          var dict = [ String : Any ]()
          for i in 0..<keys.count {
            let key = keys[i] as? String ?? String(describing: keys[i])
            dict[key] = objects[i]
          }
          return dict
        
        default:
          log.error("mdm: unsupported class:", clazz)
      }
      
      return nil
    }
    
    func decodeObjects(indices: [Int], depth: Int = 0) -> [Any?] {
      return indices.map { decodeObject(index: $0, depth: depth + 1) }
    }
    
    func decodeObject(index: Int?, depth: Int = 0) -> Any? {
      guard let index = index else { return nil }
      let object = objects[index]
      
      if let alreadyParsed = idToObject[index] {
        return alreadyParsed
      }
      
      if let s = object as? String {
        if s == "$null" { return nil }
        assert(!s.hasPrefix("$"), "unexpected string: \(s)")
        return s
      }
      
      if let s = object as? Dictionary<String, Any> {
        if let classId = textDecodeObjectID(s["$class"]) {
          guard let clazz =
                      decodeObject(index: classId, depth: depth + 1) as? String
           else {
            log.error("mom: could not decode class ID \(classId): \(s)")
            assert(false, "could not decode class ID: \(s)")
            return nil
           }
          return decodeObject(index: index, class: clazz, values: s,
                              depth: depth)
        }
        else if let className = s["$classname"] {
          idToObject[index] = className
          return className
        }
        else {
          log.error("mom: got neither class ID nor name?: \(s)")
          assert(false, "got neither class ID nor name?: \(s)")
          return nil
        }
      }
      
      return object
    }
    
    guard let rootObject = decodeObject(index: eRootID) else {
      assert(false, "to no root object")
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    guard let model = rootObject as? Model else {
      throw Error.CompiledModelsNotYetSupported
    }
    
    fixupToMany(in: model)
    model.connectRelationships()
    return model
  }

  open func loadDataModelContents(from url: URL) throws -> Model {
    if url.pathExtension == "mom" {
      return try loadCompiledModel(from: url)
    }
    
    #if swift(>=4.0)
      let options = XMLNode.Options(rawValue: 0)
    #else
      #if os(Linux) // TBD: is this rather Swift 3.1+?
        let options = XMLNode.Options(rawValue: 0)
      #else // Swift 3.0.2 on 10.11
        let options = 0
      #endif
    #endif

    let xml : XMLDocument
    do {
      xml = try XMLDocument(contentsOf: url, options: options)
    }
    catch {
      throw Error.CouldNotLoadFile(url:url, error: error) // wrap
    }
    
    let model = try loadDataModelContents(from: xml)
    model.connectRelationships()
    return model
  }
}

#if os(macOS) || os(Linux)
#else
  // iOS has no XMLDocument, tiny replacement
  class XMLNode {
  }
  class XMLElement  : XMLNode {
    var name        : String?           = nil
    var attributes  : [ XMLAttribute ]? = nil
    var children    : [ XMLNode      ]? = nil
  }
  class XMLAttribute : XMLNode {
    var name        : String?      = nil
    var localName   : String?      = nil
    var stringValue : String?      = nil
  }
  
  public class XMLDocument : NSObject, XMLParserDelegate {
    
    enum Error : Swift.Error {
      case ParsingFailed
      case CouldNotCreateParser
      case TODO
    }
    
    var root : XMLElement? = nil
    
    init(contentsOf url: URL, options: Int) throws {
      super.init()
      
      guard let parser = XMLParser(contentsOf: url)
       else { throw Error.CouldNotCreateParser }
      
      parser.delegate = self
      guard parser.parse() else { throw Error.ParsingFailed }
      
      // FIXME: IMPLEMENT DELEGATE
      throw Error.TODO
    }
    
    func rootElement() -> XMLElement? {
      return root
    }
    
  }
#endif

fileprivate extension XMLElement {

  func firstChildElementWithName(_ name: String) -> XMLElement? {
    guard let children = children else { return nil }
    
    for child in children {
      guard let element = child as? XMLElement, let tag = element.name
       else { continue }
      
      if tag == name { return element }
    }
    return nil
  }
  
  func childElementsWithName(_ name: String) -> [ XMLElement ] {
    guard let children = children else { return [] }
    
    var matches = [ XMLElement ]()
    for child in children {
      guard let element = child as? XMLElement, let tag = element.name
        else { continue }
      
      if tag == name {
        matches.append(element)
      }
    }
    return matches
  }
  
  var attributesAsDict : [ String : String ] {
    guard let attributes = attributes else { return [:] }
    
    var map = [ String : String ]()
    for attr in attributes {
      guard let name = attr.localName ?? attr.name else { continue }
      guard let v = attr.stringValue else { continue }
      map[name] = v
    }
    return map
  }
  
}

fileprivate extension Bool { // Linux compat
  var boolValue : Bool { return self }
}
