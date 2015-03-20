DELETE FROM sessions;
ALTER TABLE sessions ADD state text NOT NULL;
ALTER TABLE sessions ADD username text;
ALTER TABLE sessions ADD reset_password boolean;

ALTER TABLE users ADD algorithm text;
UPDATE users SET algorithm = 'md5';
ALTER TABLE users ALTER COLUMN algorithm SET NOT NULL;
ALTER TABLE users ADD cost int;
ALTER TABLE users ADD salt text;
ALTER TABLE users ADD reset_password boolean;

CREATE TABLE clients (
application text NOT NULL,
version text NOT NULL,
client_id text NOT NULL UNIQUE,
client_secret text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (application,version)
);

GRANT SELECT ON clients TO apache;

CREATE TABLE request_tokens (
token text NOT NULL,
secret text NOT NULL,
client_id text NOT NULL,
nonce text NOT NULL,
timestamp int NOT NULL,
start_time int NOT NULL,
name text,
dbase text,
verifier text,
PRIMARY KEY (token),
UNIQUE (nonce, timestamp),
CONSTRAINT rt_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rt_name_dbase FOREIGN KEY (name,dbase) REFERENCES users(name,dbase)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,DELETE,INSERT ON request_tokens TO apache;
