CREATE TABLE curator_permissions (
user_id integer NOT NULL,
permission text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,permission),
CONSTRAINT cp_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cp_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON curator_permissions TO apache;

INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'disable_access',0,'now' FROM user_permissions WHERE 
 disable_access;
INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'modify_users',0,'now' FROM user_permissions WHERE 
 modify_users;
INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'modify_usergroups',0,'now' FROM user_permissions WHERE 
 modify_usergroups;
INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'set_user_passwords',0,'now' FROM user_permissions WHERE 
 set_user_passwords;
INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'modify_loci',0,'now' FROM user_permissions WHERE 
 modify_loci;
INSERT INTO curator_permissions (user_id,permission,curator,datestamp)
 SELECT user_id,'modify_schemes',0,'now' FROM user_permissions WHERE 
 modify_schemes;

DROP TABLE user_permissions;
DELETE FROM user_group_members WHERE user_group=0;
DELETE FROM user_groups WHERE id=0;
