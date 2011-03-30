CREATE TABLE client_dbase_loci_fields (
client_dbase_id int NOT NULL,
locus text NOT NULL,
isolate_field text NOT NULL,
allele_query bool NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(client_dbase_id,locus,isolate_field),
CONSTRAINT lcdf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT lcdf_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lcdf_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_loci_fields TO apache;
