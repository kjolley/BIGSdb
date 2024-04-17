CREATE TABLE db_attributes (
field text NOT NULL,
value text NOT NULL,
PRIMARY KEY(field)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON db_attributes TO apache;

INSERT INTO db_attributes (field,value) VALUES ('version','45');
INSERT INTO db_attributes (field,value) VALUES ('type','isolates');

CREATE TABLE query_interfaces (
id int NOT NULL,
name text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT qi_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON query_interfaces TO apache;

CREATE TABLE query_interface_fields (
id int NOT NULL,
field text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id,field),
CONSTRAINT qif_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON query_interface_fields TO apache;
