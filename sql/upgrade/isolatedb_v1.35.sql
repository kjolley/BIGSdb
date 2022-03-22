CREATE TABLE codon_tables (
isolate_id int NOT NULL,
codon_table int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(isolate_id),
CONSTRAINT ct_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ct_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON codon_tables TO apache;
