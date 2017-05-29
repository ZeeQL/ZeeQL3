<h2>ZeeQL
  <img src="http://zeezide.com/img/ZeeQLIcon1024-QL.svg"
       align="right" width="128" height="128" />
</h2>

![Apache 2](https://img.shields.io/badge/apache-2-yellow.svg)
![Swift3](https://img.shields.io/badge/swift-3-blue.svg)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Travis](https://travis-ci.org/ZeeQL/ZeeQL3.svg?branch=develop)

ZeeQL is a Swift ORM / database access library primarily inspired by EOF,
and in consequence CoreData. Adding some ActiveRecord ideas.

Work in progress, stay tuned.

The basic setup is that Access has two levels of abstraction:
- adaptor  level (`Adaptor`,  `AdaptorChannel`)
- database level (`Database`, `DatabaseChannel`, `DatabaseDataSource`)

In general it is recommended to write a Model or a Model pattern, and then
use the DatabaseDataSource to fetch mapped objects.
However, for simple SQL you can also do that in rather convenient ways at the
adaptor level.

Important: to inject raw SQL you don't have to go down to adaptor level. You
have various ways to embed SQL in the model and thats the recommended way to
do it. See below (Raw SQL Injection Notes).


### Adaptor Level

The adaptor level is a relatively thin wrapper around the client libs, e.g.
Apache DBD, which provides some convenience methods, model reflection etc.

TBD: document


### Database Level

TBD: document


### Documentation

- [Raw SQL Injection Notes](Documentation/WaysToEmbedRawSQL.md)

### Compilation Errors

If you get: `Could not build Objective-C module 'APR'`:
If you want to use the APR database drivers, install APR, e.g. using HomeBrew:

    brew install apr-util --with-openldap --with-postgresql --with-sqlite

### Logging Level

You can configure the level of the global ZeeQL logger using the

    ZEEQL_LOGLEVEL

environment variable, for example in your run scheme. Valid values are:

- error
- warn
- info
- trace
- log
