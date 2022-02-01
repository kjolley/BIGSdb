CREATE TABLE lincode_schemes (
scheme_id int NOT NULL,
thresholds text NOT NULL,
max_missing int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id),
CONSTRAINT ls_scheme_id FOREIGN KEY(scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ls_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON lincode_schemes TO apache;

CREATE TABLE lincodes (
scheme_id int NOT NULL,
profile_id text NOT NULL,
lincode int[] NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,profile_id),
CONSTRAINT l_scheme_id FOREIGN KEY(scheme_id) REFERENCES lincode_schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT l_scheme_id_profile_id FOREIGN KEY(scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON lincodes TO apache;
