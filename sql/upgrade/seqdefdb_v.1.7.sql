DROP INDEX i_a2;
DROP INDEX i_pf2;
DROP INDEX i_ph1;
DROP INDEX i_pm2;
DROP INDEX i_pr2;
DROP INDEX i_sr2;

DROP INDEX i_pf3;
CREATE INDEX i_pf3 ON profile_fields(value);
DROP INDEX i_pm3;
CREATE INDEX i_pm3 ON profile_members(allele_id);

ALTER TABLE scheme_groups ADD seq_query boolean;

ALTER TABLE scheme_fields ADD index boolean;

UPDATE sequences SET status='unchecked' WHERE status='trace not checked';
UPDATE sequences SET status='Sanger trace checked' WHERE status='trace checked';

ALTER TABLE client_dbases ADD dbase_view text;
