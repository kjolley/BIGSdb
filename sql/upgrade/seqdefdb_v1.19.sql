DROP TRIGGER modify_scheme ON scheme_fields;
CREATE TRIGGER modify_scheme AFTER INSERT OR DELETE ON scheme_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();

ALTER TABLE locus_curators ADD curator int;
ALTER TABLE locus_curators ADD datestamp date;
UPDATE locus_curators SET (curator,datestamp)=(0,'now');
ALTER TABLE locus_curators ADD CONSTRAINT lc_curator FOREIGN KEY(curator) REFERENCES users
 ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE locus_curators ALTER COLUMN curator SET NOT NULL;
ALTER TABLE locus_curators ALTER COLUMN datestamp SET NOT NULL;

ALTER TABLE scheme_curators ADD curator int;
ALTER TABLE scheme_curators ADD datestamp date;
UPDATE scheme_curators SET (curator,datestamp)=(0,'now');
ALTER TABLE scheme_curators ADD CONSTRAINT sc_curator FOREIGN KEY(curator) REFERENCES users
 ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE scheme_curators ALTER COLUMN curator SET NOT NULL;
ALTER TABLE scheme_curators ALTER COLUMN datestamp SET NOT NULL;
ALTER TABLE scheme_curators RENAME CONSTRAINT pc_scheme_id TO sc_scheme_id;
ALTER TABLE scheme_curators RENAME CONSTRAINT pc_curator_id TO sc_curator_id;
