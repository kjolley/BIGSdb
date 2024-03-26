--Never-used indexes.
DROP INDEX i_pf3;	--profile_fields(value)
DROP INDEX i_p1;	--profiles(lpad(profile_id, 20, '0'::text))
DROP INDEX i_pr1;	--profile_refs(pubmed_id)
DROP INDEX i_a1;	--accession(databank, databank_id)
DROP INDEX i_sr1;	--sequence_refs(pubmed_id)

--Rarely used scans with high writes
DROP INDEX i_pm3;	--profile_members(allele_id)

CREATE INDEX i_s4 ON sequences(sender);
CREATE INDEX i_pm4 ON profile_members(locus,allele_id,scheme_id);

--Replace sequence exemplar index
DROP INDEX i_s2;	--sequences(exemplar)
CREATE INDEX i_s2 ON sequences(exemplar,locus);
