DROP TABLE IF EXISTS set_metadata;

CREATE TABLE introns (
id bigint NOT NULL,
start_pos bigint NOT NULL,
end_pos bigint NOT NULL,
PRIMARY KEY (id,start_pos),
CONSTRAINT i_fkeys FOREIGN KEY(id) REFERENCES allele_sequences
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON introns TO apache;

ALTER TABLE loci ADD introns bool;
