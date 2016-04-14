CREATE TABLE scheme_warehouse_indices (
scheme_id int NOT NULL,
locus text NOT NULL,
index int NOT NULL,
PRIMARY KEY (scheme_id,locus),
CONSTRAINT swi_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT swi_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_warehouse_indices TO apache;

CREATE OR REPLACE FUNCTION set_scheme_warehouse_indices(i_id int) RETURNS VOID AS $$
	DECLARE
		i int;
		x record;
	BEGIN
		DELETE FROM scheme_warehouse_indices WHERE scheme_id=i_id;
		i:=1;
		FOR x IN SELECT * FROM scheme_members WHERE scheme_id=i_id ORDER BY locus LOOP
			INSERT INTO scheme_warehouse_indices (scheme_id,locus,index) VALUES (i_id,x.locus,i);
			i:=i+1;
		END LOOP;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_scheme_warehouse(i_id int) RETURNS VOID AS $$
	DECLARE
		scheme_table text;
		create_command text;
		pk text;
		x RECORD;
	BEGIN
		scheme_table := 'scheme_warehouse_' || i_id;
		PERFORM id FROM schemes WHERE id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not exist', i_id;
		END IF;
		PERFORM scheme_id FROM scheme_fields WHERE primary_key AND scheme_id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not have a primary key', i_id;
		END IF;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=scheme_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', scheme_table);
		END IF;
		PERFORM set_scheme_warehouse_indices(i_id);
		create_command := FORMAT('CREATE TABLE %s (',scheme_table);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			create_command := FORMAT('%s %s text',create_command, x.field);
			IF x.primary_key THEN
				pk := x.field;
				create_command := create_command || ' NOT NULL';
			END IF;
			create_command := create_command || ',';
		END LOOP;
		EXECUTE FORMAT(
		'%ssender int,curator int,date_entered date,datestamp date,profile text[] UNIQUE, PRIMARY KEY (%s))', 
		create_command, pk);
		EXECUTE FORMAT('GRANT ALL ON %I TO apache',scheme_table);
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION initiate_scheme_warehouse(i_id int) RETURNS VOID AS $$
	DECLARE
		scheme_table text;
		pk text;
		fields text[];
		locus_index int;
		array_length int;
		update_command text;
		x RECORD;
	BEGIN
		PERFORM create_scheme_warehouse(i_id);
		scheme_table := 'scheme_warehouse_' || i_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=i_id AND primary_key;
		EXECUTE FORMAT(
		'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) '
		|| 'SELECT profile_id,sender,curator,date_entered,datestamp FROM '
		|| 'profiles WHERE scheme_id=%s',scheme_table,pk,i_id);
		FOR x IN SELECT * FROM profile_fields WHERE scheme_id=i_id AND scheme_field NOT IN 
		(SELECT field FROM scheme_fields WHERE scheme_id=i_id AND primary_key) LOOP
			EXECUTE FORMAT('UPDATE %I SET %I=$1 WHERE %s=$2',
			scheme_table,x.scheme_field,pk) USING x.value,x.profile_id;
		END LOOP;
		
		update_command := format(
		'UPDATE %I SET profile=array_append(profile,$1) WHERE '
		|| '%s=$2 RETURNING array_length(profile,1)',scheme_table,pk);
		FOR x IN SELECT * FROM profile_members WHERE scheme_id=i_id ORDER BY profile_id,locus LOOP
			EXECUTE update_command USING x.allele_id,x.profile_id INTO array_length;
			SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=i_id AND locus=x.locus;
			IF (locus_index != array_length) THEN
				RAISE EXCEPTION 'Profile % is incomplete.', x.profile_id;
			END IF;			
		END LOOP;		
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION modify_scheme() RETURNS TRIGGER AS $modify_scheme$
	DECLARE
		scheme_table text;
		i_scheme_id int;
	BEGIN		
		if (TG_OP = 'INSERT') THEN
			i_scheme_id = NEW.scheme_id;
		ELSE
			i_scheme_id = OLD.scheme_id;
		END IF;
		--Make sure scheme has a primary key and member loci	
		IF NOT EXISTS(SELECT * FROM scheme_fields WHERE scheme_id=i_scheme_id AND primary_key) 
		OR NOT EXISTS(SELECT * FROM scheme_members WHERE scheme_id=i_scheme_id) THEN	
			IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
				scheme_table := 'scheme_warehouse_' || i_scheme_id;
				EXECUTE FORMAT('DROP TABLE IF EXISTS %I',scheme_table); 
				DELETE FROM scheme_warehouse_indices WHERE scheme_id=i_scheme_id;
			END IF;
			RETURN NEW;
		END IF;
		PERFORM create_scheme_warehouse(i_scheme_id);
		RETURN NEW;
	END;
$modify_scheme$ LANGUAGE plpgsql;

CREATE TRIGGER modify_scheme AFTER INSERT OR UPDATE OR DELETE ON scheme_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
	
CREATE TRIGGER modify_scheme AFTER INSERT OR DELETE ON scheme_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
	
CREATE OR REPLACE FUNCTION modify_profile() RETURNS TRIGGER AS $modify_profile$
	DECLARE 
		pk text;
		scheme_table text;
	BEGIN
		IF (TG_OP = 'INSERT') THEN
			SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
			scheme_table := 'scheme_warehouse_' || NEW.scheme_id;		
			EXECUTE FORMAT(
			'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) VALUES ($1,$2,$3,$4,$5)',
			scheme_table,pk) USING 
			NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp;
			RETURN NEW;
		END IF;
		scheme_table := 'scheme_warehouse_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN			
			EXECUTE FORMAT('DELETE FROM %I WHERE %s=$1',scheme_table,pk) USING OLD.profile_id;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET (%s,sender,curator,date_entered,datestamp)=($1,$2,$3,$4,$5) WHERE %s=$6',
			scheme_table,pk,pk) USING NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile AFTER INSERT OR DELETE OR UPDATE ON profiles
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile();

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
			scheme_table := 'scheme_warehouse_' || NEW.scheme_id;		
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,NEW.profile_id;
			RETURN NEW;
		END IF;
		IF (pk = OLD.scheme_field) THEN
			RETURN OLD;
		END IF;
		scheme_table := 'scheme_warehouse_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN			
			EXECUTE FORMAT('UPDATE %I SET %s=null WHERE %s=$1',scheme_table,OLD.scheme_field,pk) USING OLD.profile_id;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile_field$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile_field AFTER INSERT OR DELETE OR UPDATE ON profile_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile_field();
	
CREATE OR REPLACE FUNCTION modify_profile_member() RETURNS TRIGGER AS $modify_profile_member$
	DECLARE 
		pk text;
		scheme_table text;
		locus_index int;
	BEGIN
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
		scheme_table := 'scheme_warehouse_' || NEW.scheme_id;
		SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=NEW.scheme_id AND locus=NEW.locus;
		EXECUTE FORMAT('UPDATE %I SET profile[$1]=$2 WHERE %s=$3',scheme_table,pk) USING 
		locus_index,NEW.allele_id,NEW.profile_id;
		RETURN NEW;
	END;
$modify_profile_member$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile_member AFTER INSERT OR UPDATE ON profile_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile_member();