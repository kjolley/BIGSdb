CREATE sequence allele_sequences_id_seq;
ALTER TABLE allele_sequences ADD id bigint;
ALTER TABLE allele_sequences ALTER COLUMN id SET DEFAULT NEXTVAL('allele_sequences_id_seq');

ALTER TABLE sequence_flags DROP CONSTRAINT sf_fkeys;

ALTER TABLE allele_sequences DROP CONSTRAINT allele_sequences_pkey;
ALTER TABLE allele_sequences ADD CONSTRAINT allele_sequences_seqbin_id_locus_start_pos_end_pos_key UNIQUE (seqbin_id, locus, start_pos, end_pos);
UPDATE allele_sequences SET id=NEXTVAL('allele_sequences_id_seq');
ALTER TABLE allele_sequences ADD PRIMARY KEY(id);

ALTER TABLE sequence_flags DROP CONSTRAINT sequence_flags_pkey;
ALTER TABLE sequence_flags ADD id bigint;
UPDATE sequence_flags SET id=allele_sequences.id FROM allele_sequences WHERE allele_sequences.seqbin_id=sequence_flags.seqbin_id 
	AND allele_sequences.locus=sequence_flags.locus AND allele_sequences.start_pos=sequence_flags.start_pos 
	AND allele_sequences.end_pos=sequence_flags.end_pos;

ALTER TABLE sequence_flags ADD PRIMARY KEY(id,flag);
ALTER TABLE sequence_flags ADD CONSTRAINT sf_fkeys FOREIGN KEY(id) REFERENCES allele_sequences ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE sequence_flags DROP COLUMN seqbin_id;
ALTER TABLE sequence_flags DROP COLUMN locus;
ALTER TABLE sequence_flags DROP COLUMN start_pos;
ALTER TABLE sequence_flags DROP COLUMN end_pos;
