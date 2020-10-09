CREATE INDEX i_sb_sender ON sequence_bin(sender);
CREATE INDEX i_sb_curator ON sequence_bin(curator);
CREATE INDEX i_ad_sender ON allele_designations(sender);
CREATE INDEX i_ad_curator ON allele_designations(curator);
CREATE INDEX i_as_curator ON allele_sequences(curator);
