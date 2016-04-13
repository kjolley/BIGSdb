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
		
		EXECUTE FORMAT('GRANT SELECT,UPDATE,INSERT,DELETE ON %I TO apache',scheme_table);
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION modify_scheme() RETURNS TRIGGER AS $modify_scheme$
	BEGIN
		--Make sure scheme has a primary key and member loci
		IF NOT EXISTS(SELECT * FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key) THEN	
			RETURN NEW;
		END IF;
		IF NOT EXISTS(SELECT * FROM scheme_members WHERE scheme_id=NEW.scheme_id) THEN
			RETURN NEW;
		END IF;
		PERFORM create_scheme_warehouse(NEW.scheme_id);
	END;
$modify_scheme$ LANGUAGE plpgsql;

CREATE TRIGGER modify_scheme AFTER INSERT OR UPDATE OR DELETE ON scheme_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
	
CREATE TRIGGER modify_scheme AFTER INSERT OR UPDATE OR DELETE ON scheme_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();