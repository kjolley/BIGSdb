CREATE TABLE db_attributes (
field text NOT NULL,
value text NOT NULL,
PRIMARY KEY(field)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON db_attributes TO apache;

INSERT INTO db_attributes (field,value) VALUES ('version','45');
INSERT INTO db_attributes (field,value) VALUES ('type','isolates');
