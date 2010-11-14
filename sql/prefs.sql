CREATE TABLE guid (
guid text NOT NULL,
last_accessed date NOT NULL,
PRIMARY KEY (guid)
);

CREATE TABLE general (
guid text NOT NULL,
dbase text NOT NULL,
attribute text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,attribute),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE locus (
guid text NOT NULL,
dbase text NOT NULL,
locus text NOT NULL,
action text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,locus,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE scheme (
guid text NOT NULL,
dbase text NOT NULL,
scheme_id int NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,scheme_id,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE scheme_field (
guid text NOT NULL,
dbase text NOT NULL,
scheme_id int NOT NULL,
field text NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,scheme_id,field,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE field (
guid text NOT NULL,
dbase text NOT NULL,
field text NOT NULL,
action text NOT NULL,
value boolean NOT NULL,
PRIMARY KEY (guid,dbase,field,action),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE TABLE plugin (
guid text NOT NULL,
dbase text NOT NULL,
plugin text NOT NULL,
attribute text NOT NULL,
value text NOT NULL,
PRIMARY KEY (guid,dbase,plugin,attribute),
CONSTRAINT conguid FOREIGN KEY (guid) REFERENCES guid
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON guid,general,locus,scheme,scheme_field,field,plugin TO apache;