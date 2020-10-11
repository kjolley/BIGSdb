CREATE TABLE registered_curators (
dbase_config text NOT NULL,
user_name text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (dbase_config,user_name),
CONSTRAINT rc_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rc_dbase_config FOREIGN KEY (dbase_config) REFERENCES registered_resources
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON registered_curators TO apache;

CREATE TABLE submission_digests (
user_name text NOT NULL,
timestamp timestamp NOT NULL,
dbase_description text NOT NULL,
submission_id text NOT NULL,
submitter text NOT NULL,
summary text NOT NULL,
PRIMARY KEY (user_name,timestamp),
CONSTRAINT sd_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON submission_digests TO apache;

ALTER TABLE users ADD submission_digests boolean;
ALTER TABLE users ADD submission_email_cc boolean;
ALTER TABLE users ADD absent_until date;
