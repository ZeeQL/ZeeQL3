import ZeeQL

internal extension Model {
  
  func dump(prefix: String = "") {
    print("\(prefix)got model:", self)
    for entity in entities {
      entity.dump(prefix: prefix + "  ")
    }
  }
  
}

internal extension Entity {
  
  func dump(prefix: String = "  ") {
    print("\(prefix)entity: \(self)")
    if let props = classPropertyNames {
      print("\(prefix)  props: \(props.joined(separator: ","))")
    }
    for attr in attributes {
      print("\(prefix)  attr: \(attr)")
    }
    for rs in relationships {
      print("\(prefix)  rs:   \(rs)")
    }
  }
}
