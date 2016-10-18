CREATE TABLE users (
user_name text NOT NULL UNIQUE,
surname text NOT NULL,
first_name text NOT NULL,
email text NOT NULL,
affiliation text NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_name)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

CREATE TABLE permissions (
user_name text NOT NULL,
permission text NOT NULL,
curator text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_name,permission),
CONSTRAINT p_user_name FOREIGN KEY (user_name) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON permissions TO apache;
