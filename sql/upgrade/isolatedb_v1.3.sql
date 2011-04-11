ALTER TABLE sequence_flags DROP CONSTRAINT sequence_flags_pkey;
ALTER TABLE sequence_flags ADD end_pos int;
UPDATE sequence_flags SET end_pos = (SELECT end_pos FROM allele_sequences WHERE allele_sequences.seqbin_id=sequence_flags.seqbin_id AND allele_sequences.locus=sequence_flags.locus AND allele_sequences.start_pos=sequence_flags.start_pos);
ALTER TABLE sequence_flags ALTER COLUMN end_pos SET NOT NULL;
ALTER TABLE sequence_flags DROP CONSTRAINT sf_fkeys;
ALTER TABLE allele_sequences DROP CONSTRAINT allele_sequences_pkey;
ALTER TABLE sequence_flags ADD PRIMARY KEY (seqbin_id,locus,start_pos,end_pos,flag);
ALTER TABLE allele_sequences ADD PRIMARY KEY (seqbin_id,locus,start_pos,end_pos);
ALTER TABLE sequence_flags ADD CONSTRAINT sf_fkeys FOREIGN KEY (seqbin_id,locus,start_pos,end_pos) REFERENCES allele_sequences ON DELETE CASCADE ON UPDATE CASCADE;

