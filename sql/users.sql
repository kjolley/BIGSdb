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
