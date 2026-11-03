UPDATE db_attributes SET value='56' WHERE field='version';

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
    locus_count int;
BEGIN
    SELECT cs.scheme_id INTO i_scheme_id
    FROM classification_schemes cs
    WHERE id = i_cg_scheme_id;

    SELECT COUNT(*) INTO locus_count
    FROM scheme_members
    WHERE scheme_id = i_scheme_id;

    RETURN QUERY
        WITH query_profile AS MATERIALIZED (
            SELECT locus, allele_id
            FROM profile_members
            WHERE scheme_id = i_scheme_id
              AND profile_id = profile_id1
        )
        SELECT p2.profile_id
        FROM query_profile AS p1
        JOIN profile_members AS p2
          ON p1.locus = p2.locus
         AND p2.scheme_id = i_scheme_id
        JOIN classification_group_profiles AS cgp
          ON p2.profile_id = cgp.profile_id
         AND cgp.cg_scheme_id = i_cg_scheme_id
        WHERE p2.profile_id != profile_id1
          AND (
              p1.allele_id = p2.allele_id
              OR p1.allele_id = 'N'
              OR p2.allele_id = 'N'
          )
        GROUP BY p2.profile_id
        HAVING COUNT(*) >= (locus_count - threshold);
END;
$$ LANGUAGE plpgsql;
