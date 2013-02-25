ALTER TABLE client_dbase_schemes ADD client_scheme_id int;

ALTER TABLE loci ADD match_longest boolean;

ALTER TABLE schemes ADD allow_missing_loci boolean;

ALTER TABLE sequences ADD comments text;
