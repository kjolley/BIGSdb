ALTER TABLE clients ADD dbase text;
ALTER TABLE clients ADD username text;
ALTER TABLE clients ADD CONSTRAINT c_dbase_user FOREIGN KEY(username,dbase) REFERENCES users(name,dbase) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE clients DROP CONSTRAINT clients_pkey;
ALTER TABLE clients ADD PRIMARY KEY(client_id);

GRANT SELECT,INSERT,UPDATE,DELETE ON clients TO apache;