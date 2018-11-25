CREATE TABLE client_dbase_cschemes (
client_dbase_id int NOT NULL,
cscheme_id int NOT NULL,
client_cscheme_id int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (client_dbase_id,cscheme_id),
CONSTRAINT cdc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT cdc_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cdc_cscheme_id FOREIGN KEY (cscheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_cschemes TO apache;

ALTER TABLE schemes ADD max_missing int;

CREATE OR REPLACE FUNCTION matching_profiles_cg(i_cg_scheme_id int, profile_id1 text, threshold int) 
	RETURNS setof text AS $$
	DECLARE
		i_scheme_id int;
		locus_count int;
	BEGIN
		SELECT cs.scheme_id INTO i_scheme_id FROM classification_schemes cs WHERE id=i_cg_scheme_id;	
		SELECT COUNT(*) INTO locus_count FROM scheme_members WHERE scheme_id=i_scheme_id;	
		RETURN QUERY SELECT p2.profile_id FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND 
		p1.scheme_id=p2.scheme_id AND p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND
		(p1.allele_id=p2.allele_id OR p1.allele_id='N' OR p2.allele_id='N') AND 
		p2.profile_id IN (SELECT profile_id FROM classification_group_profiles WHERE cg_scheme_id=i_cg_scheme_id) 
		GROUP BY p2.profile_id HAVING COUNT(*) >= (locus_count-threshold);
	END 
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION matching_profiles_with_relative_threshold_cg(i_cg_scheme_id int, profile_id1 text, i_threshold int) 
RETURNS setof text AS $$
	DECLARE
		i_scheme_id int;
		total int;
	BEGIN
		SELECT cs.scheme_id INTO i_scheme_id FROM classification_schemes cs WHERE id=i_cg_scheme_id;	
		SELECT COUNT(*) INTO total FROM scheme_members WHERE scheme_id=i_scheme_id;
		CREATE TEMP TABLE loci_in_common AS SELECT p2.profile_id AS profile_id,COUNT(*) AS loci,
		COUNT(CASE WHEN p1.allele_id=p2.allele_id THEN 1 ELSE NULL END) AS matched,
		ROUND((CAST(COUNT(*) AS float)*(total-i_threshold))/total) AS threshold 
		FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND p1.scheme_id=p2.scheme_id AND 
		p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND p1.allele_id!='N' 
		AND p2.allele_id!='N' AND p2.profile_id IN (SELECT profile_id FROM classification_group_profiles WHERE 
		cg_scheme_id=i_cg_scheme_id) GROUP BY p2.profile_id;

		RETURN QUERY SELECT profile_id FROM loci_in_common WHERE matched>=threshold;
		DROP TABLE loci_in_common;	
	END;
$$ LANGUAGE plpgsql;
