/**
 * ZeeQL test schema
 *
 * Copyright © 2017 ZeeZide GmbH. All rights reserved.
 *
 * Create database sample:
 *   createdb contacts --owner=OGo
 *   psql -h localhost contacts OGo OGo
 */
 
CREATE TABLE person (
  person_id SERIAL PRIMARY KEY NOT NULL,
  
  firstname VARCHAR NULL,
  lastname  VARCHAR NOT NULL
);

CREATE TABLE address (
  address_id SERIAL PRIMARY KEY NOT NULL,
  
  street  VARCHAR NULL,
  city    VARCHAR NULL,
  state   VARCHAR NULL,
  country VARCHAR NULL,
  
  person_id INTEGER,
  FOREIGN KEY(person_id) REFERENCES person(person_id) 
       ON DELETE CASCADE
       DEFERRABLE
);
