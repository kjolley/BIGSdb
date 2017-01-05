ALTER TABLE projects ADD private boolean;
UPDATE projects SET private=false;
ALTER TABLE projects ALTER COLUMN private SET NOT NULL;
UPDATE projects SET isolate_display=false WHERE isolate_display IS NULL;
ALTER TABLE projects ALTER COLUMN isolate_display SET NOT NULL;
UPDATE projects SET list=false WHERE list IS NULL;
ALTER TABLE projects ALTER COLUMN list SET NOT NULL;
