ALTER TABLE schemes ADD use_view boolean;
UPDATE schemes SET use_view=TRUE WHERE id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key);
