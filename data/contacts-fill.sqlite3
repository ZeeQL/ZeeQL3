/**
 * ZeeQL test schema
 *
 * Copyright © 2017 ZeeZide GmbH. All rights reserved.
 *
 * sqlite3 contacts.sqlite3 < contacts-fill.sqlite3
 */
 
INSERT INTO person ( firstname, lastname ) 
     SELECT 'Donald',   'Duck';
INSERT INTO person ( firstname, lastname ) 
     SELECT 'Dagobert', 'Duck';
INSERT INTO person ( firstname, lastname ) 
     SELECT 'Mickey',   'Mouse';

-- SELECT * FROM person LEFT JOIN address USING ( person_id );
INSERT INTO address ( street, city, person_id )
     SELECT 'Am Geldspeicher 1', 'Entenhausen',
            ( SELECT person_id FROM person WHERE firstname = 'Dagobert' )
;
