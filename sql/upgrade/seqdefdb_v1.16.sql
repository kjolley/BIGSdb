CREATE TABLE user_dbases (
id int NOT NULL,
name text NOT NULL,
dbase_name text NOT NULL,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
list_order int,
auto_registration boolean,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ud_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_dbases TO apache;

ALTER TABLE users ADD user_db int;
ALTER TABLE users ADD CONSTRAINT u_user_db FOREIGN KEY (user_db) REFERENCES user_dbases(id) 
ON DELETE NO ACTION ON UPDATE CASCADE; 
ALTER TABLE users ALTER COLUMN surname DROP NOT NULL;
ALTER TABLE users ALTER COLUMN first_name DROP NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN affiliation DROP NOT NULL;
ALTER TABLE users ADD account_request_emails boolean;
UPDATE users SET account_request_emails=FALSE;
UPDATE users SET submission_emails=FALSE WHERE submission_emails IS NULL;

ALTER TABLE curator_permissions RENAME TO permissions;

UPDATE scheme_flags SET flag='please cite' where flag='citation required';

ALTER TABLE profiles DROP CONSTRAINT p_sender;
ALTER TABLE profiles ADD CONSTRAINT p_sender FOREIGN KEY (sender) REFERENCES users(id)
ON DELETE NO ACTION ON UPDATE CASCADE;
ALTER TABLE profiles DROP CONSTRAINT p_curator;
ALTER TABLE profiles ADD CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users(id)
ON DELETE NO ACTION ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION modify_profile() RETURNS TRIGGER AS $modify_profile$
	DECLARE 
		pk text;
		scheme_table text;
	BEGIN
		IF (TG_OP = 'INSERT') THEN
			SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
			scheme_table := 'mv_scheme_' || NEW.scheme_id;		
			EXECUTE FORMAT(
			'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) VALUES ($1,$2,$3,$4,$5)',
			scheme_table,pk) USING 
			NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp;
			RETURN NEW;
		END IF;
		scheme_table := 'mv_scheme_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN
			--If PK scheme field is deleted, this function is still triggered.
			IF (pk IS NOT NULL) THEN
				EXECUTE FORMAT('DELETE FROM %I WHERE %s=$1',scheme_table,pk) USING OLD.profile_id;
			END IF;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET (%s,sender,curator,date_entered,datestamp)=($1,$2,$3,$4,$5) WHERE %s=$6',
			scheme_table,pk,pk) USING NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION modify_profile_field() RETURNS TRIGGER AS $modify_profile_field$
	DECLARE 
		pk text;
		scheme_table text;
	BEGIN
		IF (TG_OP = 'INSERT') THEN
			SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
			IF (pk = NEW.scheme_field) THEN
				RETURN NEW;
			END IF;
			scheme_table := 'mv_scheme_' || NEW.scheme_id;		
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,NEW.profile_id;
			RETURN NEW;
		END IF;
		IF (pk = OLD.scheme_field) THEN
			RETURN OLD;
		END IF;
		scheme_table := 'mv_scheme_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN	
			--If PK scheme field is deleted, this function is still triggered.
			IF (pk IS NOT NULL) THEN
				EXECUTE FORMAT('UPDATE %I SET %s=null WHERE %s=$1',scheme_table,OLD.scheme_field,pk) USING OLD.profile_id;
			END IF;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile_field$ LANGUAGE plpgsql;
