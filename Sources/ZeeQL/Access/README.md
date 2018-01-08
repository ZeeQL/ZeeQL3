## ZeeQL Access/Model

This contains the classes/protocols used to represent the so called "Model". The model
is an in-memory description of the mapping between managed objects and their
external representation (e.g. in a SQL information schema).

ZeeQL generally uses the terms from the
[Entity–relationship model](https://en.wikipedia.org/wiki/Entity–relationship_model).

Key objects/protocols are:

- `Model`
- `Entity`
- `Attribute`
- `Relationship`

Those are mostly protocols, which have distinct concrete implementations. They can be
typed or untyped.

A `Model` is just a collection of entities.
It can be defined in code,
can be loaded from a file (e.g. a CoreData modeller file),
or fetched from the database information schema (i.e. automatically derived from an
existing database).

An `Entity` usually corresponds to a Swift class (either a concrete one, or just a generic
value holder), and often maps to a SQL database table or view.
Though the latter is not required, e.g. it could also be a GraphQL entity.

Entities contain attributes and relationships. Plus some extra information.

## CodeXYZ Variants

Using `CodeEntity` or `CodeObjectEntity` you can define entities directly in
source code, check the class dox for how that works.

## CodableXYZ Variants

Models can also be created using Swift 4 `Codable` compliant objects.
This is even easier to write in Swift code, but has fewer features than a `CodeEntity`.
