DROP TRIGGER modify_scheme ON scheme_fields;
CREATE TRIGGER modify_scheme AFTER INSERT OR DELETE ON scheme_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
