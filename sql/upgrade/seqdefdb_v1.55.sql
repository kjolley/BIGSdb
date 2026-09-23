UPDATE db_attributes SET value='55' WHERE field='version';

CREATE OR REPLACE FUNCTION set_scheme_warehouse_indices(i_id int) RETURNS VOID AS $$
	DECLARE
		i int;
		x record;
	BEGIN
	    -- Serialize warehouse-index rebuilds for this scheme only.
        PERFORM pg_advisory_xact_lock(
            hashtext('BIGSdb.scheme_warehouse_indices'),
            i_id
        );

		DELETE FROM scheme_warehouse_indices WHERE scheme_id=i_id;
		i:=1;
		FOR x IN SELECT * FROM scheme_members WHERE scheme_id=i_id ORDER BY locus LOOP
			INSERT INTO scheme_warehouse_indices (scheme_id,locus,index) VALUES (i_id,x.locus,i);
			i:=i+1;
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
				PERFORM pg_advisory_xact_lock(
		            hashtext('BIGSdb.scheme_warehouse_indices'),
		            i_scheme_id
		        );
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