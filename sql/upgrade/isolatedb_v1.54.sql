ALTER TABLE private_isolates ALTER COLUMN embargo DROP NOT NULL;

GRANT REFERENCES ON isolates TO apache,bigsdb;
