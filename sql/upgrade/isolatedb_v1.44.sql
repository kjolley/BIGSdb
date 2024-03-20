--Never-used indexes.
DROP INDEX seqbin_stats_l50_idx;	--seqbin_stats(l50)
DROP INDEX i_eavi1;					--eav_int(field,value)
DROP INDEX i_eavt1;					--eav_text(field,value)
DROP INDEX i_eavb1;					--eav_boolean(field,value)
DROP INDEX i_eavd1;					--eav_date(field,value)
DROP INDEX i_eavf1;					--eav_float(field,value)

--Rarely used scans with high writes
DROP INDEX i_ad4;					--allele_designations(datestamp)
DROP INDEX i_ad_sender;				--allele_designations(sender)
DROP INDEX i_ad_curator;			--allele_designations(curator)
DROP INDEX i_as2;					--allele_sequences(datestamp)
DROP INDEX i_as_curator;			--allele_sequences(curator)
DROP INDEX i_sb_curator;			--sequence_bin(curator)
DROP INDEX i_sb_sender;				--sequence_bin(sender)
DROP INDEX seqbin_stats_n50_idx;	--seqbin_stats(n50)
