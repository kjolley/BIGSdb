ALTER TABLE schemes ADD allow_presence boolean DEFAULT FALSE;
UPDATE schemes SET allow_presence = FALSE;
ALTER TABLE schemes ALTER COLUMN allow_presence SET NOT NULL;
