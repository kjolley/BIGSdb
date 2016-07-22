ALTER TABLE schemes DROP COLUMN IF EXISTS dbase_st_field;
ALTER TABLE schemes DROP COLUMN IF EXISTS dbase_st_descriptor;
ALTER TABLE schemes RENAME description TO name;
ALTER TABLE schemes ADD description text;

CREATE TABLE scheme_flags (
scheme_id int NOT NULL,
flag text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,flag),
CONSTRAINT sfl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT sfl_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_flags TO apache;
