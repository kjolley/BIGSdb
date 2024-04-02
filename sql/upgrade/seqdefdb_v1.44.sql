--Never-used indexes.
DROP INDEX i_pf3;	--profile_fields(value)
DROP INDEX i_p1;	--profiles(lpad(profile_id, 20, '0'::text))
DROP INDEX i_pr1;	--profile_refs(pubmed_id)
DROP INDEX i_a1;	--accession(databank, databank_id)
DROP INDEX i_sr1;	--sequence_refs(pubmed_id)

--Rarely used scans with high writes
DROP INDEX i_pm3;	--profile_members(allele_id)

CREATE INDEX i_s4 ON sequences(sender);
CREATE INDEX i_pm4 ON profile_members(locus,allele_id,scheme_id);

--Replace sequence exemplar index
DROP INDEX i_s2;	--sequences(exemplar)
CREATE INDEX i_s2 ON sequences(exemplar,locus);

CREATE OR REPLACE FUNCTION find_nearest_profile(_scheme_id int,_profile text[]) 
RETURNS TABLE (profiles text[], mismatches int) AS $$
	DECLARE
		scheme_table text;
		pk text;
		pk_type text;
		x RECORD;
		allele text;
		query text;
		order_by text;
		mismatches int;
		least_mismatches int;
		i int;
		best_matches text[];
	
	BEGIN
--		RAISE NOTICE '%', _profile;
--		RAISE NOTICE '%', _profile[2];
		scheme_table := 'mv_scheme_' || _scheme_id;
		PERFORM id FROM schemes WHERE id=_scheme_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not exist', _scheme_id;
		END IF;
		SELECT field,type INTO pk,pk_type FROM scheme_fields WHERE primary_key AND scheme_id=_scheme_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not have a primary key', _scheme_id;
		END IF;
		SELECT COUNT(*) INTO least_mismatches FROM scheme_members WHERE scheme_id=_scheme_id;
		IF pk_type = 'integer' THEN
			order_by := FORMAT('CAST(%s AS int)',pk);
		ELSE
			order_by := pk;
		END IF;
		query := FORMAT('SELECT %s AS pk,profile FROM %s ORDER BY %s',pk,scheme_table,order_by);
		<<PROFILE>>
		FOR x IN EXECUTE query LOOP
			RAISE NOTICE 'Checking %', x.pk;
			mismatches := 0;
			i := 0;
			<<LOCUS>>
			FOREACH allele IN ARRAY x.profile LOOP
--				RAISE NOTICE '%', allele;
				i := i+1;
				IF x.profile[i] = 'N' THEN
					CONTINUE LOCUS;
				END IF;
				IF _profile[i] = x.profile[i] THEN
					CONTINUE LOCUS;
				END IF;
				mismatches = mismatches + 1;
				IF (mismatches > least_mismatches) THEN
					EXIT LOCUS;
				END IF;
			END LOOP;
			IF (mismatches < least_mismatches) THEN 
				least_mismatches = mismatches;
				best_matches := '{}';
				best_matches := array_append(best_matches, x.pk);
			ELSIF mismatches = least_mismatches THEN
				best_matches := array_append(best_matches, x.pk);
			END IF;
		END LOOP;
--		RAISE NOTICE '%', order_by;
		RAISE NOTICE '%', best_matches;
		RETURN QUERY SELECT best_matches, least_mismatches;
	END;
	
$$ LANGUAGE plpgsql;
