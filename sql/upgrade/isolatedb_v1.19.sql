CREATE TABLE eav_fields (
field text NOT NULL,
value_format text NOT NULL,
description text,
length int,
option_list text,
value_regex text,
min_value int,
max_value int,
field_order int,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (field),
CONSTRAINT eavf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON eav_fields TO apache;

CREATE TABLE eav_int (
isolate_id int NOT NULL,
field text NOT NULL,
value int NOT NULL,
PRIMARY KEY (isolate_id,field),
CONSTRAINT eavi_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT eavi_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON eav_int TO apache;

CREATE TABLE eav_float (
isolate_id int NOT NULL,
field text NOT NULL,
value float NOT NULL,
PRIMARY KEY (isolate_id,field),
CONSTRAINT eavf_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT eavf_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON eav_float TO apache;

CREATE TABLE eav_text (
isolate_id int NOT NULL,
field text NOT NULL,
value text NOT NULL,
PRIMARY KEY (isolate_id,field),
CONSTRAINT eavt_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT eavt_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON eav_text TO apache;

CREATE TABLE eav_date (
isolate_id int NOT NULL,
field text NOT NULL,
value date NOT NULL,
PRIMARY KEY (isolate_id,field),
CONSTRAINT eavd_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT eavd_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON eav_date TO apache;


