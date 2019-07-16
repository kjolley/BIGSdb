ALTER TABLE eav_fields ADD category text;
ALTER TABLE eav_fields ADD no_submissions boolean;
UPDATE eav_fields SET no_submissions=no_curate;
ALTER TABLE eav_fields ALTER COLUMN no_submissions SET NOT NULL;

CREATE TABLE validation_conditions (
id int NOT NULL,
field text NOT NULL,
operator text NOT NULL,
value text NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT vc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON validation_conditions TO apache;

CREATE TABLE validation_rules (
id int NOT NULL,
message text NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT vr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON validation_rules TO apache;

CREATE TABLE validation_rule_conditions (
rule_id int NOT NULL,
condition_id int NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (rule_id,condition_id),
CONSTRAINT vrc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT vrc_rule_id FOREIGN KEY (rule_id) REFERENCES validation_rules
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT vrc_condition_id FOREIGN KEY (condition_id) REFERENCES validation_conditions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON validation_rule_conditions TO apache;

ALTER TABLE eav_int DROP CONSTRAINT eavi_field;
ALTER TABLE eav_int ADD CONSTRAINT eavi_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE CASCADE
ON UPDATE CASCADE;
ALTER TABLE eav_float DROP CONSTRAINT eavf_field;
ALTER TABLE eav_float ADD CONSTRAINT eavf_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE CASCADE
ON UPDATE CASCADE;
ALTER TABLE eav_text DROP CONSTRAINT eavt_field;
ALTER TABLE eav_text ADD CONSTRAINT eavt_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE CASCADE
ON UPDATE CASCADE;
ALTER TABLE eav_date DROP CONSTRAINT eavd_field;
ALTER TABLE eav_date ADD CONSTRAINT eavd_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE CASCADE
ON UPDATE CASCADE;
ALTER TABLE eav_boolean DROP CONSTRAINT eavb_field;
ALTER TABLE eav_boolean ADD CONSTRAINT eavb_field FOREIGN KEY (field) REFERENCES eav_fields
ON DELETE CASCADE
ON UPDATE CASCADE;

