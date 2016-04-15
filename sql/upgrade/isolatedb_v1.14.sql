--Standardize all scheme tables to use mv_ prefix.
UPDATE schemes SET dbase_table=REGEXP_REPLACE(dbase_table,'^scheme_','mv_scheme_') WHERE dbase_table IS NOT NULL;
