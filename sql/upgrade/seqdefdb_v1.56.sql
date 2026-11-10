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


CREATE OR REPLACE FUNCTION allele_profiles_match_relative_cg(
    profile1 text[],
    profile2 text[],
    threshold int
)
RETURNS boolean AS $$
DECLARE
    i int;
    comparable int := 0;
    matched int := 0;
    total int;
    required_matches double precision;
BEGIN
    total := cardinality(profile1);

    IF total != cardinality(profile2) THEN
        RAISE EXCEPTION 'Profiles have different lengths';
    END IF;

    IF total = 0 THEN
        RETURN false;
    END IF;

    FOR i IN 1..total LOOP
        -- Exclude loci missing from either profile.
        IF profile1[i] = 'N' OR profile2[i] = 'N' THEN
            CONTINUE;
        END IF;

        comparable := comparable + 1;

        IF profile1[i] = profile2[i] THEN
            matched := matched + 1;
        END IF;
    END LOOP;

    -- The original join returns no row when there are
    -- no comparable loci.
    IF comparable = 0 THEN
        RETURN false;
    END IF;

    -- Preserve the original floating-point calculation
    -- and PostgreSQL ROUND() behaviour.
    required_matches :=
        ROUND(
            (comparable::double precision *
             (total - threshold)) / total
        );

    RETURN matched >= required_matches;
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
        || 'AND allele_profiles_match_relative_cg($3,p.profile,$4)',
        pk_field, warehouse_table
    )
    USING i_cg_scheme_id, profile_id1, query_profile, i_threshold;
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

