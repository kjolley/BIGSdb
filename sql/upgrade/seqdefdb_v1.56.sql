UPDATE db_attributes SET value='56' WHERE field='version';

CREATE OR REPLACE FUNCTION allele_profiles_match_cg(
    profile1 text[],
    profile2 text[],
    max_mismatches int
)
RETURNS boolean AS $$
DECLARE
    i int;
    mismatches int := 0;
BEGIN
    IF cardinality(profile1) != cardinality(profile2) THEN
        RAISE EXCEPTION 'Profiles have different lengths';
    END IF;

    FOR i IN 1..cardinality(profile1) LOOP
        IF profile1[i] != profile2[i]
           AND profile1[i] != 'N'
           AND profile2[i] != 'N'
        THEN
            mismatches := mismatches + 1;

            IF mismatches > max_mismatches THEN
                RETURN false;
            END IF;
        END IF;
    END LOOP;

    RETURN true;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION matching_profiles_with_relative_threshold_cg(
    i_cg_scheme_id int,
    profile_id1 text,
    i_threshold int
)
RETURNS SETOF text AS $$
DECLARE
    i_scheme_id int;
    total int;
BEGIN
    SELECT cs.scheme_id INTO i_scheme_id
    FROM classification_schemes cs
    WHERE id = i_cg_scheme_id;

    SELECT COUNT(*) INTO total
    FROM scheme_members
    WHERE scheme_id = i_scheme_id;

    RETURN QUERY
        WITH query_profile AS MATERIALIZED (
            SELECT locus, allele_id
            FROM profile_members
            WHERE scheme_id = i_scheme_id
              AND profile_id = profile_id1
              AND allele_id != 'N'
        )
        SELECT matches.profile_id
        FROM (
            SELECT
                p2.profile_id,
                COUNT(*) AS loci,
                COUNT(CASE WHEN p1.allele_id = p2.allele_id
                      THEN 1 ELSE NULL END) AS matched,
                ROUND(
                    (CAST(COUNT(*) AS float) *
                     (total - i_threshold)) / total
                ) AS threshold
            FROM query_profile AS p1
            JOIN profile_members AS p2
              ON p1.locus = p2.locus
             AND p2.scheme_id = i_scheme_id
            JOIN classification_group_profiles AS cgp
              ON p2.profile_id = cgp.profile_id
             AND cgp.cg_scheme_id = i_cg_scheme_id
            WHERE p2.profile_id != profile_id1
              AND p2.allele_id != 'N'
            GROUP BY p2.profile_id
        ) AS matches
        WHERE matches.matched >= matches.threshold;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION matching_profiles_cg(
    i_cg_scheme_id int,
    profile_id1 text,
    threshold int
)
RETURNS SETOF text AS $$
DECLARE
    i_scheme_id int;
    pk_field text;
    warehouse_table text;
    query_profile text[];
BEGIN
    SELECT cs.scheme_id INTO i_scheme_id
    FROM classification_schemes cs
    WHERE id = i_cg_scheme_id;

    SELECT lower(field) INTO pk_field
    FROM scheme_fields
    WHERE scheme_id = i_scheme_id
      AND primary_key;

    warehouse_table := 'mv_scheme_' || i_scheme_id;

    -- Retrieve the query profile once.
    EXECUTE format(
        'SELECT profile FROM %I WHERE %I=$1',
        warehouse_table, pk_field
    )
    INTO query_profile
    USING profile_id1;

    IF query_profile IS NULL THEN
        RETURN;
    END IF;

    -- Compare against previously grouped profiles.
    RETURN QUERY EXECUTE format(
        'SELECT p.%1$I '
        || 'FROM classification_group_profiles AS cgp '
        || 'JOIN %2$I AS p ON p.%1$I=cgp.profile_id '
        || 'WHERE cgp.cg_scheme_id=$1 '
        || 'AND cgp.profile_id!=$2 '
        || 'AND allele_profiles_match_cg($3,p.profile,$4)',
        pk_field, warehouse_table
    )
    USING i_cg_scheme_id, profile_id1, query_profile, threshold;
END;
$$ LANGUAGE plpgsql;

