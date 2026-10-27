UPDATE db_attributes SET value='56' WHERE field='version';

CREATE OR REPLACE FUNCTION get_isolate_scheme_fields(_isolate_id int, _scheme_id int)
RETURNS SETOF record AS $$
DECLARE
    scheme_table text;
    fields text[];
    scheme_fields text;
    max_missing int;
    missing int;
    locus_count int;
    allowed jsonb;
    predicates text := '';
    qry text;
    r record;
    i int := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schemes WHERE id = _scheme_id) THEN
        RAISE EXCEPTION 'Scheme % does not exist.', _scheme_id;
    END IF;

    scheme_table := 'temp_scheme_' || _scheme_id;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = scheme_table) THEN
        RAISE EXCEPTION 'Scheme cache table % does not exist.', scheme_table;
    END IF;

    SELECT array_agg(field ORDER BY field_order, field)
    INTO fields
    FROM scheme_fields
    WHERE scheme_id = _scheme_id;
    IF fields IS NULL THEN
        RAISE EXCEPTION 'Scheme has no fields.';
    END IF;
    -- Match the existing function's field-selection behaviour.
    scheme_fields := array_to_string(fields, ',');

    EXECUTE format('SELECT max(missing_loci) FROM %I', scheme_table)
    INTO max_missing;

    -- Each element of allowed is an array of permitted allele IDs for one locus.
    -- JSONB permits differing numbers of designations per locus.
    -- The warehouse index determines profile[] order, not the locus name.
    SELECT jsonb_agg(to_jsonb(array_prepend('N'::text,
                         coalesce(x.alleles, ARRAY[]::text[]))) ORDER BY x.locus_index),
           count(*),
           count(*) FILTER (WHERE x.designation_count = 0)
    INTO allowed, locus_count, missing
    FROM (
        SELECT swi.index AS locus_index,
               array_agg(ad.allele_id::text) FILTER (WHERE ad.allele_id IS NOT NULL) AS alleles,
               count(ad.locus) AS designation_count
        FROM scheme_warehouse_indices swi
        LEFT JOIN allele_designations ad
          ON ad.isolate_id = _isolate_id AND ad.locus = swi.locus
        WHERE swi.scheme_id = _scheme_id
        GROUP BY swi.index
    ) x;

    IF missing > max_missing THEN
        RETURN;
    END IF;
    IF locus_count = 0 THEN
        -- Original function cannot construct a valid WHERE clause in this case.
        RETURN;
    END IF;

    -- Restrict candidates with a few ordinary profile[] predicates, which can
    -- use existing expression indexes. The remaining loci are checked below.
    -- These are deliberately the first three positions, not necessarily the
    -- most selective: EXPLAIN will show whether the existing indexes help.
    FOR i IN 1..least(locus_count, 3) LOOP
        IF i > 1 THEN
            predicates := predicates || ' AND ';
        END IF;
        SELECT string_agg(quote_literal(v.value), ',' ORDER BY v.ordinality)
        INTO qry
        FROM jsonb_array_elements_text(allowed -> (i - 1)) WITH ORDINALITY v(value, ordinality);
        predicates := predicates || format('t.profile[%s] IN (%s)', i, qry);
    END LOOP;

    -- For every candidate, reject any locus with an incompatible allele.
    -- 'N' matches every isolate.
    qry := format($sql$
        SELECT %s FROM %I AS t
        WHERE %s
          AND array_length(t.profile, 1) >= $2
          AND NOT EXISTS (
              SELECT 1
              FROM unnest(t.profile) WITH ORDINALITY AS p(allele, pos)
              WHERE p.pos <= $2
                AND (p.allele IS NULL
                     OR NOT (($1 -> ((p.pos - 1)::int)) ? p.allele))
          )
    $sql$, scheme_fields, scheme_table, predicates);

    RETURN QUERY EXECUTE qry USING allowed, locus_count;
END;
$$ LANGUAGE plpgsql;

