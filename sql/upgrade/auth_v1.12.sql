ALTER TABLE clients ADD default_access text;
UPDATE clients SET default_access = 'RW';
ALTER TABLE clients ADD CONSTRAINT c_default_access CHECK (default_access IN ('R', 'RW'));
ALTER TABLE clients ALTER COLUMN default_access SET NOT NULL;
