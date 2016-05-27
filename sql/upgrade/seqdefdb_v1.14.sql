CREATE INDEX i_s2 ON sequences(exemplar) WHERE exemplar;

--Change owner of profile_members to apache (needed so that triggers can be disabled for batch upload).
ALTER TABLE profile_members OWNER TO apache;

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

CREATE OR REPLACE FUNCTION md5(text_array text []) RETURNS text AS $$
	SELECT md5(array_to_string(text_array,','));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION create_scheme_warehouse(i_id int) RETURNS VOID AS $$
	DECLARE
		scheme_table text;
		create_command text;
		pk text;
		x RECORD;
	BEGIN
		scheme_table := 'mv_scheme_' || i_id;
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
		EXECUTE FORMAT('%ssender int NOT NULL,curator int NOT NULL,date_entered date NOT NULL,'
		|| 'datestamp date NOT NULL,profile text[], PRIMARY KEY (%s))', 
		create_command, pk);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			IF x.index THEN
				EXECUTE FORMAT('CREATE INDEX ON %I(%s)',scheme_table,x.field);
			END IF;
		END LOOP;
		EXECUTE FORMAT('CREATE UNIQUE INDEX ON %I(md5(profile))',scheme_table);
		EXECUTE FORMAT('CREATE INDEX ON %I ((profile[1]))',scheme_table);
		--We need to be able to drop and recreate as apache user.
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', scheme_table);
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
		scheme_table := 'mv_scheme_' || i_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=i_id AND primary_key;
		EXECUTE FORMAT(
		'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) '
		|| 'SELECT profile_id,sender,curator,date_entered,datestamp FROM '
		|| 'profiles WHERE scheme_id=%s',scheme_table,pk,i_id);
		FOR x IN SELECT * FROM profile_fields WHERE scheme_id=i_id AND scheme_field NOT IN 
		(SELECT field FROM scheme_fields WHERE scheme_id=i_id AND primary_key) LOOP
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',
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
				scheme_table := 'mv_scheme_' || i_scheme_id;
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
		scheme_table := 'mv_scheme_' || NEW.scheme_id;
		SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=NEW.scheme_id AND locus=NEW.locus;
		EXECUTE FORMAT('UPDATE %I SET profile[$1]=$2 WHERE %s=$3',scheme_table,pk) USING 
		locus_index,NEW.allele_id,NEW.profile_id;
		RETURN NEW;
	END;
$modify_profile_member$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile_member AFTER INSERT OR UPDATE ON profile_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile_member();
	
--Remove old materialized view functions and triggers
DROP FUNCTION create_matview(name,name);
DROP FUNCTION drop_matview(name);
DROP FUNCTION refresh_matview(name);
DROP TABLE matviews;
	
--Set up scheme warehouses
SELECT initiate_scheme_warehouse(scheme_id) FROM scheme_fields WHERE PRIMARY_KEY AND 
scheme_id IN (SELECT scheme_id FROM scheme_members);

--Functions for profile comparison
CREATE OR REPLACE FUNCTION profile_diff(i_scheme_id int, profile_id1 text, profile_id2 text) RETURNS bigint AS $$
	SELECT COUNT(*) FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND 
		p1.scheme_id=p2.scheme_id AND p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND 
		p2.profile_id=profile_id2 AND p1.allele_id!=p2.allele_id AND p1.allele_id!='N' AND p2.allele_id!='N';
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION matching_profiles(i_scheme_id int, profile_id1 text, threshold int) RETURNS setof text AS $$
	SELECT p2.profile_id FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND 
	p1.scheme_id=p2.scheme_id AND p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND
	(p1.allele_id=p2.allele_id OR p1.allele_id='N' OR p2.allele_id='N') 
	GROUP BY p2.profile_id HAVING COUNT(*) >= ((SELECT COUNT(*) FROM scheme_members WHERE scheme_id=i_scheme_id)-threshold) 
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION matching_profiles_with_relative_threshold(i_scheme_id int, profile_id1 text, i_threshold int) 
RETURNS setof text AS $$
	DECLARE
		total int;
	BEGIN
		SELECT COUNT(*) INTO total FROM scheme_members WHERE scheme_id=i_scheme_id;
		CREATE TEMP TABLE loci_in_common AS SELECT p2.profile_id AS profile_id,COUNT(*) AS loci,
		COUNT(CASE WHEN p1.allele_id=p2.allele_id THEN 1 ELSE NULL END) AS matched,
		ROUND((CAST(COUNT(*) AS float)*(total-i_threshold))/total) AS threshold 
		FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND p1.scheme_id=p2.scheme_id AND 
		p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND p1.allele_id!='N' 
		AND p2.allele_id!='N' GROUP BY p2.profile_id;

		RETURN QUERY SELECT profile_id FROM loci_in_common WHERE matched>=threshold;
		DROP TABLE loci_in_common;	
	END;
$$ LANGUAGE plpgsql;

--classification_schemes
CREATE TABLE classification_schemes (
id int NOT NULL,
scheme_id int NOT NULL,
name text NOT NULL,
description text,
inclusion_threshold int NOT NULL,
use_relative_threshold boolean NOT NULL,
status text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT cgs_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgs_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

--Unique constraint necessary to set up foreign key on classification_group_profiles
CREATE UNIQUE INDEX ON classification_schemes(id,scheme_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON classification_schemes TO apache;

--classification_groups
CREATE TABLE classification_groups (
cg_scheme_id int NOT NULL,
group_id int NOT NULL,
active boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,group_id),
CONSTRAINT cg_cg_scheme_id FOREIGN KEY (cg_scheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cg_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_groups TO apache;

--classification_group_fields
CREATE TABLE classification_group_fields (
cg_scheme_id int NOT NULL,
field text NOT NULL,
type text NOT NULL,
value_regex text,
description text,
field_order int,
dropdown boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,field),
CONSTRAINT cgf_cg_scheme_id FOREIGN KEY (cg_scheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_fields TO apache;

--classification_group_profiles
CREATE TABLE classification_group_profiles (
cg_scheme_id int NOT NULL,
group_id int NOT NULL,
profile_id text NOT NULL,
scheme_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,group_id,profile_id),
CONSTRAINT cgp_cg_scheme_id_group_id FOREIGN KEY (cg_scheme_id,group_id) REFERENCES classification_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_cg_scheme_id_scheme_id FOREIGN KEY (cg_scheme_id,scheme_id) REFERENCES classification_schemes(id,scheme_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profiles TO apache;

--classification_group_profile_fields
CREATE TABLE classification_group_profile_fields (
cg_scheme_id int NOT NULL,
field text NOT NULL,
group_id int NOT NULL,
profile_id text NOT NULL,
value text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,field,group_id,profile_id),
CONSTRAINT cgpf_cg_scheme_id_field FOREIGN KEY (cg_scheme_id,field) REFERENCES classification_group_fields
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgpf_cg_scheme_id_group_profile_id FOREIGN KEY (cg_scheme_id,group_id,profile_id) REFERENCES classification_group_profiles
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgpf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profile_fields TO apache;

--classification_group_profile_history
CREATE TABLE classification_group_profile_history (
timestamp timestamp NOT NULL,
scheme_id int NOT NULL,
profile_id text NOT NULL,
cg_scheme_id int NOT NULL,
previous_group int NOT NULL,
comment text,
PRIMARY KEY(timestamp,scheme_id,profile_id),
CONSTRAINT cgph_cg_scheme_id_previous_group FOREIGN KEY (cg_scheme_id,previous_group) REFERENCES classification_groups(cg_scheme_id,group_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgph_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profile_history TO apache;
