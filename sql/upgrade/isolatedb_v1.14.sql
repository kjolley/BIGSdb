--Standardize all scheme tables to use mv_ prefix.
UPDATE schemes SET dbase_table=REGEXP_REPLACE(dbase_table,'^scheme_','mv_scheme_') WHERE dbase_table IS NOT NULL;

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

CREATE OR REPLACE FUNCTION create_isolate_scheme_array(scheme_id int,view text) RETURNS VOID AS $$
	DECLARE
		cache_table text;
		isolate RECORD;
		locus RECORD;
		x RECORD;
		locus_index int;
		current_id int;
		current_profile text[];
	BEGIN
		cache_table:='temp_' || view || '_scheme_profiles_' || scheme_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		EXECUTE(FORMAT('CREATE TABLE %s (id int, profile text[])',cache_table));
		--Check isolates that have duplicate alleles.
		FOR isolate IN EXECUTE(FORMAT('SELECT id FROM %I',view)) LOOP
			FOR locus IN EXECUTE('SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index') USING scheme_id LOOP
--				RAISE NOTICE '% %', isolate.id, locus.locus;
			END LOOP;
		END LOOP;
		
		EXECUTE FORMAT('CREATE INDEX ON %I(id)', cache_table);
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table);
		
		--Create table of isolates with duplicate values???
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_isolate_scheme_allele_cache(i_id int,s_view text) RETURNS VOID AS $$
	DECLARE
		cache_table text;
		scheme_table text;
		allele_table text;
		sql text;
		x RECORD;
		loci RECORD;
		profile RECORD;
		pk text;
		pk_type text;
		locus_indices text[];
		i integer;
	BEGIN
		cache_table:='temp_' || s_view || '_scheme_fields_' || i_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		allele_table:='temp_scheme_alleles_' || i_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=allele_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', allele_table);
		END IF;
		sql:='CREATE TABLE %s (id int';
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			sql:=sql || ',' || x.field || ' ' || x.type;
		END LOOP;
		sql:=sql || ')';
		EXECUTE FORMAT(sql,cache_table);
		SELECT field,type INTO pk,pk_type FROM scheme_fields WHERE scheme_id=i_id AND primary_key;
		EXECUTE FORMAT('CREATE TABLE %s (%s %s NOT NULL,locus text NOT NULL,allele_id text NOT NULL)',allele_table,pk,pk_type,pk);
		scheme_table:='temp_scheme_' || i_id;
		FOR x IN EXECUTE('SELECT locus,index FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index') USING i_id LOOP
			locus_indices[x.index]=x.locus;
		END LOOP;
		
		--TODO Optimise using COPY from STDOUT.
		sql:=FORMAT('INSERT INTO %I VALUES ($1,$2,$3)',allele_table);
		FOR profile IN EXECUTE(FORMAT('SELECT %s AS pk,profile FROM %I',pk,scheme_table)) LOOP
			FOR i IN 1 .. array_upper(profile.profile, 1)
			LOOP
				EXECUTE(sql) USING profile.pk,locus_indices[i],profile.profile[i];
			END LOOP;
		END LOOP;
		EXECUTE FORMAT('ALTER TABLE %s ADD PRIMARY KEY(%s,locus)',allele_table,pk);
		EXECUTE FORMAT('CREATE INDEX ON %s(locus)',allele_table);
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table);
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', allele_table);		
	END; 
$$ LANGUAGE plpgsql;
