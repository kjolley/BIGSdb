UPDATE db_attributes SET value='50' WHERE field='version';

CREATE TABLE analysis_fields (
analysis_name text NOT NULL,
field_name text NOT NULL,
description text,
json_path text NOT NULL,
data_type text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (analysis_name,field_name),
CONSTRAINT af_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON analysis_fields TO apache;
