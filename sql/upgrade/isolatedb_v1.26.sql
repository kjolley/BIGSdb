CREATE TABLE bookmarks (
id bigserial NOT NULL UNIQUE,
name text NOT NULL,
dbase_config text NOT NULL,
set_id int,
page TEXT NOT NULL,
params jsonb NOT NULL,
user_id integer NOT NULL,
date_entered date NOT NULL,
last_accessed date NOT NULL,
public boolean NOT NULL,
PRIMARY KEY (id),
CONSTRAINT b_user FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON bookmarks TO apache;
GRANT USAGE,SELECT ON SEQUENCE bookmarks_id_seq TO apache;

CREATE TABLE log (
id bigserial NOT NULL UNIQUE,
timestamp timestamp NOT NULL,
user_id integer NOT NULL,
user_name text NOT NULL,
"table" text NOT NULL,
record jsonb NOT NULL,
action text NOT NULL,
PRIMARY KEY (id)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON log TO apache;
GRANT USAGE,SELECT ON SEQUENCE log_id_seq TO apache;
