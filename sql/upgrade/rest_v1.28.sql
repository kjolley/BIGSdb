ALTER TABLE resources ADD hide boolean DEFAULT FALSE;
UPDATE resources SET hide = FALSE;
ALTER TABLE resources ALTER COLUMN hide SET NOT NULL;
