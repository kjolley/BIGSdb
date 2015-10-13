ALTER TABLE clients ADD default_submission bool;
ALTER TABLE clients ADD default_curation bool;
UPDATE clients SET (default_submission,default_curation) = (false,false);
ALTER TABLE clients ALTER COLUMN default_submission SET NOT NULL;
ALTER TABLE clients ALTER COLUMN default_curation SET NOT NULL;

ALTER TABLE client_permissions ADD submission bool;
ALTER TABLE client_permissions ADD curation bool;
UPDATE client_permissions SET submission = CASE WHEN access='RW' THEN true ELSE false END;
UPDATE client_permissions SET curation = CASE WHEN access='RW' THEN true ELSE false END;
ALTER TABLE client_permissions ALTER COLUMN submission SET NOT NULL;
ALTER TABLE client_permissions ALTER COLUMN curation SET NOT NULL;
ALTER TABLE client_permissions DROP COLUMN access;
