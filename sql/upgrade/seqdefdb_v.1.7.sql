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
