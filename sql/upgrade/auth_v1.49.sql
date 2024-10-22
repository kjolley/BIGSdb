ALTER TABLE clients ADD dbase text;
ALTER TABLE clients ADD username text;
ALTER TABLE clients ADD CONSTRAINT c_dbase_user FOREIGN KEY(username,dbase) REFERENCES users(name,dbase) ON UPDATE CASCADE ON DELETE CASCADE;

