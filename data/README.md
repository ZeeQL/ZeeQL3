# Test Database

The `OGo.sqlite3` database is an old OpenGroupware.org database created using:

```sh
sqlite3 OGo.sqlite3 < OGo-5.5/Database/SQLite/build-schema.sqlite
```

OpenGroupware create scripts can be found in the 
[OGoCore project on GitHub](https://github.com/AlwaysRightInstitute/OGoCore/tree/master/database).

NOTE: Although generally sound, the OGo database schema contains a LOT of legacy
stuff and workarounds. That sometimes leads to weird naming and other awkward
stuff. Back in 2000 SQL databases have not been as advanced as they are now :-)
