#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::CurateBatchAddPage;
use strict;
use List::MoreUtils qw(any none);
use base qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $table         = $q->param('table');
	my $cleaned_table = $table;
	my $loci          = $self->{'datastore'}->get_loci();
	my $locus         = $q->param('locus');
	$cleaned_table =~ tr/_/ /;
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	}
	if ( $table eq 'sequences' && $locus ) {
		if ( !$self->{'datastore'}->is_locus($locus) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Locus $locus does not exist!</p></div>\n";
			return;
		}
		my $cleaned_locus = $locus;
		$cleaned_locus =~ tr/_/ /;
		print "<h1>Batch insert $cleaned_locus sequences</h1>\n";
	} else {
		print "<h1>Batch insert $cleaned_table</h1>\n";
	}
	if ( !$self->can_modify_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the $table table.</p></div>\n";
		return;
	}
	if ( $table eq 'pending_allele_designations' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You can not use this interface to add pending allele designations.</p></div>\n";
		return;
	} elsif ( $table eq 'sequence_bin' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You can not use this interface to add sequences to the bin.</p></div>\n";
		return;
	} elsif ( $table eq 'allele_sequences' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Tag allele sequences using the scan interface.</p></div>\n";
		return;
	}
	if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('data')
		&& !$q->param('checked_buffer') )
	{
		print "<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of a scheme will result in the
		removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, but any profiles
		will have to be reloaded.</p></div>\n";
	}
	my $script_name = $q->script_name;
	my $integer_id;
	my $sender_field;
	if ( $table eq $self->{'system'}->{'view'} ) {
		$integer_id   = 1;
		$sender_field = 1;
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			if ( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) {
				$integer_id = 1;
			} elsif ( $_->{'name'} eq 'sender' ) {
				$sender_field = 1;
			}
		}
	}
	if ( $q->param('checked_buffer') ) {
		my $dir      = $self->{'config'}->{'secure_tmp_dir'};
		my $tmp_file = $dir . '/' . $q->param('checked_buffer');
		my %schemes;
		open( my $tmp_fh, '<', $tmp_file );
		my @records = <$tmp_fh>;
		close $tmp_fh;
		if ( $tmp_file =~ /^(.*\/BIGSdb_\d*_\d*_\d*\.txt)$/ ) {
			$logger->info("Deleting temp file $tmp_file");
			unlink $1;
		} else {
			$logger->error("Can't delete temp file $tmp_file");
		}
		my $headerline = shift @records;
		$headerline =~ s/[\r\n]//g;
		my @fieldorder = split /\t/, $headerline;
		my %fieldorder;
		my $extended_attributes;
		for ( my $i = 0 ; $i < scalar @fieldorder ; $i++ ) {
			$fieldorder{ $fieldorder[$i] } = $i;
		}
		my @fields_to_include;
		if ( $table eq $self->{'system'}->{'view'} ) {
			foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				push @fields_to_include, $_;
			}
		} else {
			my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
			foreach (@$attributes) {
				push @fields_to_include, $_->{'name'};
			}
			if ( $table eq 'sequences' && $locus ) {
				$extended_attributes =
				  $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=?", $locus );
			}
		}
		my @history;
		foreach my $record (@records) {
			$record =~ s/\r//g;
			my @profile;
			if ($record) {
				my @data = split /\t/, $record;
				@data = $self->_process_fields( \@data );
				my @value_list;
				my ( @extras, @ref_extras );
				my ( $id,     $sender );
				foreach (@fields_to_include) {
					$id = $data[ $fieldorder{$_} ] if $_ eq 'id';
					if ( $_ eq 'date_entered' || $_ eq 'datestamp' ) {
						push @value_list, "'today'";
					} elsif ( $_ eq 'curator' ) {
						push @value_list, $self->get_curator_id();
					} elsif ( defined $fieldorder{$_}
						&& $data[ $fieldorder{$_} ] ne 'null'
						&& $data[ $fieldorder{$_} ] ne '' )
					{
						push @value_list, "'$data[$fieldorder{$_}]'";
						if ( $_ eq 'sender' ) {
							$sender = $data[ $fieldorder{$_} ];
						}
					} elsif ( $_ eq 'sender' ) {
						if ( $q->param('sender') ) {
							$sender = $q->param('sender');
							push @value_list, $q->param('sender');
						} else {
							push @value_list, 'null';
							$logger->error("No sender!");
						}
					} elsif ( $table eq 'sequences' && !defined $fieldorder{$_} && $locus ) {
						( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
						push @value_list, "'$cleaned_locus'";
					} else {
						push @value_list, 'null';
					}
					if ( $_ eq 'scheme_id' ) {
						$schemes{ $data[ $fieldorder{'scheme_id'} ] } = 1;
					}
				}
				if ( ( $table eq 'loci' || $table eq $self->{'system'}->{'view'} ) && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					@extras     = split /;/, $data[ $fieldorder{'aliases'} ];
					@ref_extras = split /;/, $data[ $fieldorder{'references'} ];
				}
				my @inserts;
				my $qry;
				$"   = ',';
				$qry = "INSERT INTO $table (@fields_to_include) VALUES (@value_list)";
				push @inserts, $qry;
				if ( $table eq 'allele_designations' ) {
					push @history,
					  "$data[$fieldorder{'id'}]|$data[$fieldorder{'locus'}]: new designation '$data[$fieldorder{'allele_id'}]'";
				}
				$logger->debug("INSERT: $qry");
				my $curator = $self->get_curator_id();
				if ( $table eq $self->{'system'}->{'view'} ) {

					#Set read ACL for 'All users' group
					push @inserts, "INSERT INTO isolate_usergroup_acl (isolate_id,user_group_id,read,write) VALUES ($id,0,true,false)";

					#Set read/write ACL for curator
					push @inserts, "INSERT INTO isolate_user_acl (isolate_id,user_id,read,write) VALUES ($id,$curator,true,true)";

					#Remove duplicate loci which may occur if they belong to more than one scheme.
					my %templist = ();
					my @locus_list = grep ( $templist{$_}++ == 0, @$loci );
					%templist = ();
					foreach (@locus_list) {
						next if !$fieldorder{$_};
						$data[ $fieldorder{$_} ] =~ s/^\s*//g;
						$data[ $fieldorder{$_} ] =~ s/\s*$//g;
						if (   defined $fieldorder{$_}
							&& $data[ $fieldorder{$_} ] ne 'null'
							&& $data[ $fieldorder{$_} ] ne '' )
						{
							( my $cleaned_locus = $_ ) =~ s/'/\\'/g;
							$qry =
"INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) VALUES ('$id','$cleaned_locus','$data[$fieldorder{$_}]','$sender','confirmed','manual','$curator','today','today')";
							push @inserts, $qry;
							$logger->debug("INSERT: $qry");
						}
					}
					foreach (@extras) {
						next if $_ eq 'null';
						$_ =~ s/^\s*//g;
						$_ =~ s/\s*$//g;
						if ( $_ && $_ ne $id && $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ne 'null' ) {
							$qry = "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES ($id,'$_',$curator,'today')";
							push @inserts, $qry;
							$logger->debug("INSERT: $qry");
						}
					}
					foreach (@ref_extras) {
						next if $_ eq 'null';
						$_ =~ s/^\s*//g;
						$_ =~ s/\s*$//g;
						if ( $_ && $_ ne $id && $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ne 'null' ) {
							if ( BIGSdb::Utils::is_int($_) ) {
								$qry = "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($id,$_,$curator,'today')";
								push @inserts, $qry;
								$logger->debug("INSERT: $qry");
							}
						}
					}
				} elsif ( $table eq 'loci' ) {
					foreach (@extras) {
						$_ =~ s/^\s*//g;
						$_ =~ s/\s*$//g;
						if ( $_ && $_ ne $id && $_ ne 'null' ) {
							$qry =
"INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) VALUES ('$id','$_','TRUE',$curator,'today')";
							push @inserts, $qry;
							$logger->debug("INSERT: $qry");
						}
					}
				} elsif ( $table eq 'users' ) {
					$qry = "INSERT INTO user_group_members (user_id,user_group,curator,datestamp) VALUES ($id,0,$curator,'today')";
					push @inserts, $qry;
					$logger->debug("INSERT: $qry");
				} elsif ( $table eq 'sequences' && $locus ) {
					if ( ref $extended_attributes eq 'ARRAY' ) {
						my @values;
						foreach (@$extended_attributes) {
							if ( defined $fieldorder{$_} && $data[ $fieldorder{$_} ] ne '' && $data[ $fieldorder{$_} ] ne 'null' ) {
								( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
								( my $cleaned_field = $_ )     =~ s/'/\\'/g;
								push @inserts,
"INSERT INTO sequence_extended_attributes (locus,field,allele_id,value,datestamp,curator) VALUES ('$cleaned_locus','$cleaned_field','$data[$fieldorder{'allele_id'}]','$data[$fieldorder{$_}]','today',$curator)";
							}
						}
					}
				}
				$" = ';';
				eval {
					$self->{'db'}->do("@inserts");
					if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
						foreach ( keys %schemes ) {
							$self->remove_profile_data($_);
							$self->drop_scheme_view($_);
							$self->create_scheme_view($_);
						}
					}
				};
				if ($@) {
					print
"<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>\n";
					if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
						print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
					} else {
						print "<p>Error message: $@</p>\n";
					}
					print "</div>\n";
					$self->{'db'}->rollback();
					$logger->error("Can't insert: $@");
					return;
				}
			}
		}
		$self->{'db'}->commit()
		  && print "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok</p>";
		foreach (@history) {
			my ( $isolate_id, $action ) = split /\|/, $_;
			$self->update_history( $isolate_id, $action );
		}
		print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
	} elsif ( $q->param('data') ) {
		my @checked_buffer;
		my @fieldorder = $self->_get_fields_in_order($table);
		my $extended_attributes;
		my $required_extended_exist;
		my %last_id;
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' ) {
			if ($locus){
				my $sql =
				  $self->{'db'}->prepare(
	"SELECT field,value_format,value_regex,required,option_list FROM locus_extended_attributes WHERE locus=? ORDER BY field_order"
				  );
				eval { $sql->execute($locus); };
				if ($@) {
					$logger->error("Can't execute $@");
				}
				while ( my ( $field, $format, $regex, $required, $optlist ) = $sql->fetchrow_array ) {
					push @fieldorder, $field;
					$extended_attributes->{$field}->{'format'}      = $format;
					$extended_attributes->{$field}->{'regex'}       = $regex;
					$extended_attributes->{$field}->{'required'}    = $required;
					$extended_attributes->{$field}->{'option_list'} = $optlist;
				}
			} else {
				$required_extended_exist = $self->{'datastore'}->run_list_query("SELECT DISTINCT locus FROM locus_extended_attributes WHERE required");
			}
		}
		my ( $firstname, $surname, $userid );
		my $sender_message;
		if ($sender_field) {
			my $sender = $q->param('sender');
			if ( !$sender ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Please go back and select the sender for this submission.</p></div>\n";
				return;
			} elsif ( $sender == -1 ) {
				$sender_message = "<p>Using sender field in pasted data.</p>\n";
			} else {
				my $sender_ref = $self->{'datastore'}->get_user_info($sender);
				$sender_message = "<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n";
			}
		}
		my %problems;
		my $tablebuffer;
		$tablebuffer .= "<div class=\"scrollable\"><table class=\"resultstable\"><tr>";
		$" = "</th><th>";
		$tablebuffer .= $self->_get_field_table_header($table);
		$tablebuffer .= "</tr>";
		my @records   = split /\n/, $q->param('data');
		my $td        = 1;
		my $headerRow = shift @records;
		$headerRow =~ s/\r//g;
		my @fileheaderFields = split /\t/, $headerRow;
		my %fileheaderPos;
		my $i = 0;

		foreach (@fileheaderFields) {
			$fileheaderPos{$_} = $i;
			$i++;
		}
		my $id;
		my $id_is_int;
		my %unique_field;
		my %unique_values;
		if ( $table eq $self->{'system'}->{'view'} ) {
			$id        = $self->next_id($table);
			$id_is_int = 1;
		} else {
			my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
			foreach (@$attributes) {
				if ( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) {
					$id        = $self->next_id($table);
					$id_is_int = 1;
				}
				if ( $_->{'unique'} eq 'yes' ) {
					$unique_field{ $_->{'name'} } = 1;
				}
			}
		}
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		my %primary_key_combination;
		$" = '=? AND ';
		my $qry                   = "SELECT COUNT(*) FROM $table WHERE @primary_keys=?";
		my $primary_key_check_sql = $self->{'db'}->prepare($qry);
		my %locus_format;
		my %locus_regex;
		my $first_record = 1;
		my $header_row;
		my $record_count;
		my ( $sql_sequence_exists, $sql_allele_id_exists );

		if ( $table eq 'sequences' ) {
			$sql_sequence_exists  = $self->{'db'}->prepare("SELECT allele_id FROM sequences WHERE locus=? AND sequence=?");
			$sql_allele_id_exists = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=? AND allele_id=?");
		}
		foreach my $record (@records) {
			$record =~ s/\r//g;
			next if $record =~ /^\s*$/;
			my @pk_values;
			my @profile;
			my $checked_record;
			if ($record) {
				my @data = split /\t/, $record;
				my $pk_combination;
				$i = 0;
				if ( $id_is_int && !$first_record ) {
					do {
						$id++;
					} while ( $self->_is_id_used( $table, $id ) );
				}
				foreach (@primary_keys) {
					if ( $fileheaderPos{$_} eq '' ) {
						if ( $_ eq 'id' && $id ) {
							$pk_combination .= "id: " . BIGSdb::Utils::pad_length( $id, 10 );
						} else {
							if ( $table eq 'sequences' && $locus && $_ eq 'locus' ) {
								push @pk_values, $locus;
								$pk_combination .= "$_: " . BIGSdb::Utils::pad_length( $locus, 10 );
							} else {
								$pk_combination .= 'undef';
							}
						}
					} else {
						$pk_combination .= '; ' if $i;
						$pk_combination .= "$_: " . BIGSdb::Utils::pad_length( $data[ $fileheaderPos{$_} ], 10 );
						push @pk_values, $data[ $fileheaderPos{$_} ];
					}
					$i++;
					$record_count++;
				}
				$i = 0;
				my $rowbuffer;
				my $continue = 1;
				foreach my $field (@fieldorder) {
					my $value;
					if ( $field eq 'id' ) {
						$header_row .= "id\t"
						  if $first_record && !defined $fileheaderPos{'id'};
						$value = $id;
					}
					if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
						$value = $self->get_datestamp();
						$header_row .= "$field\t" if $first_record && defined $fileheaderPos{$field};
					} elsif ( $field eq 'sender' ) {
						if ( defined $fileheaderPos{$field} ) {
							$value = $data[ $fileheaderPos{$field} ];
							$header_row .= "$field\t" if $first_record;
						} else {
							$value = $q->param('sender')
							  if $q->param('sender') != -1;
						}
					} elsif ( $field eq 'curator' ) {
						if ( defined $fileheaderPos{$field} ) {
							$header_row .= "$field\t" if $first_record;
						}
						$value = $self->get_curator_id();
					} elsif ( $extended_attributes->{$field}->{'format'} eq 'boolean' ) {
						if ( defined $fileheaderPos{$field} ) {
							$header_row .= "$field\t" if $first_record;
							$value = $data[ $fileheaderPos{$field} ];
							$value = lc($value);
						}
					} else {
						if ( defined $fileheaderPos{$field} ) {
							$header_row .= "$field\t" if $first_record;
							$value = $data[ $fileheaderPos{$field} ];
						}
					}

					#check if unique value exists twice in submission
					my $special_problem;
					if ( $unique_field{ $fieldorder[$i] } ) {
						if ( $unique_values{$field}{$value} ) {
							my $display_value = $value;
							if ( $field eq 'sequence' ) {
								$display_value =
								  "<span class=\"seq\">" . ( BIGSdb::Utils::truncate_seq( \$display_value, 40 ) ) . "</span>";
							}
							my $problem_text =
							  "unique field '$field' already has a value of '$display_value' set within this submission<br />";
							$problems{$pk_combination} .= $problem_text
							  if $problems{$pk_combination} !~ /$problem_text/;
							$special_problem = 1;
						}
						$unique_values{ $fieldorder[$i] }{$value}++;
					}
					if ( $table eq 'sequences' && $field eq 'locus' && $q->param('locus') ) {
						$value = $q->param('locus');
					}
					if ( $table eq 'sequences' && $field eq 'allele_id' ) {
						$locus = $q->param('locus') ? $q->param('locus') : $data[ $fileheaderPos{'locus'} ];
						if ($data[ $fileheaderPos{'locus'}] && any {$_ eq $data[ $fileheaderPos{'locus'}]} @$required_extended_exist){
							$problems{$pk_combination} .= "Locus $locus has required extended attributes - please use specific batch upload form for this locus.<br />";
							$special_problem = 1;
						}
						$locus = $q->param('locus') ? $q->param('locus') : $data[ $fileheaderPos{'locus'} ];
						my $locus_info = $self->{'datastore'}->get_locus_info($locus);
						if ( $locus_info->{'allele_id_format'} eq 'integer' && $data[ $fileheaderPos{'allele_id'} ] eq '' ) {
							if ( $last_id{$locus} ) {
								$value = $last_id{$locus};
							} else {
								$value = $self->{'datastore'}->get_next_allele_id($locus) - 1;
							}
							my $exists;
							do {
								$value++;
								eval { $sql_allele_id_exists->execute( $locus, $value ); };
								if ($@) {
									$logger->error("Can't execute allele id exists check. values $locus,$value $@");
									last;
								}
								($exists) = $sql_allele_id_exists->fetchrow_array;
							} while $exists;
							$last_id{$locus} = $value;
						} elsif ( !BIGSdb::Utils::is_int( $data[ $fileheaderPos{'allele_id'} ] )
							&& $locus_info->{'allele_id_format'} eq 'integer' )
						{
							$problems{$pk_combination} .= "Allele id must be an integer.<br />";
							$special_problem = 1;
						}
						my $regex = $locus_info->{'allele_id_regex'};
						if ( $regex && $data[ $fileheaderPos{'allele_id'} ] !~ /$regex/ ) {
							$problems{$pk_combination} .=
							  "Allele id value is invalid - it must match the regular expression /$regex/<br />";
							$special_problem = 1;
						}
					}

		   #special case to check for sequence length in sequences table, and that sequence doesn't already exist and is similar to existing
					if ( $table eq 'sequences' && $field eq 'sequence' ) {
						$locus = $q->param('locus') ? $q->param('locus') : $data[ $fileheaderPos{'locus'} ];
						my $locus_info = $self->{'datastore'}->get_locus_info($locus);
						my $length     = length($value);
						my $units      = $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'residues';
						if ( !$locus_info->{'length_varies'} && $locus_info->{'length'} != $length ) {
							my $problem_text =
"Sequence is $length $units long but this locus is set as a standard length of $locus_info->{'length'} $units.<br />";
							$problems{$pk_combination} .= $problem_text
							  if $problems{$pk_combination} !~ /$problem_text/;
							$special_problem = 1;
						} elsif ( $locus_info->{'min_length'} && $length < $locus_info->{'min_length'} ) {
							my $problem_text =
"Sequence is $length $units long but this locus is set with a minimum length of $locus_info->{'min_length'} $units.<br />";
							$problems{$pk_combination} .= $problem_text;
							$special_problem = 1;
						} elsif ( $locus_info->{'max_length'} && $length > $locus_info->{'max_length'} ) {
							my $problem_text =
"Sequence is $length $units long but this locus is set with a maximum length of $locus_info->{'max_length'} $units.<br />";
							$problems{$pk_combination} .= $problem_text;
							$special_problem = 1;
						} elsif ( $data[ $fileheaderPos{'allele_id'} ] =~ /\s/ ) {
							$problems{$pk_combination} .=
							  "Allele id must not contain spaces - try substituting with underscores (_).<br />";
							$special_problem = 1;
						} else {
							$value = uc($value);
							$value =~ s/[\W]//g;
							eval { $sql_sequence_exists->execute( $locus, $value ); };
							if ($@) {
								$logger->error("Can't execute sequence exists check. values $locus,$value $@");
							}
							my ($exists) = $sql_sequence_exists->fetchrow_array;
							if ($exists) {
								if ( $q->param('complete_CDS') || $q->param('ignore_existing')) {
									$continue = 0;
								} else {
									$problems{$pk_combination} .= "Sequence already exists in the database ($locus: $exists).<br />";
								}
							}
							if ( $q->param('complete_CDS') ) {
								my $first_codon = substr( $value, 0, 3 );
								$continue = 0 if $first_codon ne 'ATG' && $first_codon ne 'GTG' && $first_codon ne 'TTG';
								my $end_codon = substr( $value, -3 );
								$continue = 0 if $end_codon ne 'TAA' && $end_codon ne 'TGA' && $end_codon ne 'TAG';
								my $multiple_of_3 = ( length($value) / 3 ) == int( length($value) / 3 ) ? 1 : 0;
								$continue = 0 if !$multiple_of_3;
								my $internal_stop;
								for ( my $pos = 0 ; $pos < length($value) - 3 ; $pos += 3 ) {
									my $codon = substr( $value, $pos, 3 );
									if ( $codon eq 'TAA' || $codon eq 'TGA' || $codon eq 'TAG' ) {
										$internal_stop = 1;
									}
								}
								$continue = 0 if $internal_stop;
							}
						}
						if ($continue) {
							if ( $locus_info->{'data_type'} eq 'DNA' && !BIGSdb::Utils::is_valid_DNA($value) ) {
								if ($q->param('complete_CDS') || $q->param('ignore_non_DNA')){
									$continue = 0
								} else {
									$problems{$pk_combination} .= "Sequence contains non nucleotide (G|A|T|C) characters.<br />";
								}
							} elsif ( $locus_info->{'data_type'} eq 'DNA'
								&& $self->{'datastore'}->sequences_exist($locus)
								&& !$q->param('ignore_similarity')
								&& !$self->sequence_similar_to_others( $locus, \$value ) )
							{
								$problems{$pk_combination} .=
"Sequence is too dissimilar to existing alleles (less than 70% identical or an alignment of less than 90% its length). Similarity is determined
	by the output of the best match from the BLAST algorithm - this may be conservative.  If you're sure that this sequence should be entered, please
	 select the 'Override sequence similarity check' box.<br />";
							}
						}
					}

					#special case to check for allele id format and regex which is defined in loci table
					if ( ( $table eq 'allele_designations' )
						&& $field eq 'allele_id' )
					{
						my $format;
						eval {
							$format =
							  $self->{'datastore'}->run_simple_query( "SELECT allele_id_format,allele_id_regex FROM loci WHERE id=?",
								$data[ $fileheaderPos{'locus'} ] );
						};
						if ($@) {
							$logger->error($@);
						}
						if ( $format->[0] eq 'integer'
							&& !BIGSdb::Utils::is_int($value) )
						{
							my $problem_text = "$field must be an integer<br />";
							$problems{$pk_combination} .= $problem_text
							  if $problems{$pk_combination} !~ /$problem_text/;
							$special_problem = 1;
						} elsif ( $format->[1] && $value !~ /$format->[1]/ ) {
							$problems{$pk_combination} .=
							  "$_->{'name'} value is invalid - it must match the regular expression /$format->[1]/";
							$special_problem = 1;
						}
					}
					if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' ) {

						#check extended attributes if they exist
						if ( $extended_attributes->{$field} ) {
							my @optlist;
							my %options;
							if ( $extended_attributes->{$field}->{'option_list'} ) {
								@optlist = split /\|/, $extended_attributes->{$field}->{'option_list'};
								foreach (@optlist) {
									$options{$_} = 1;
								}
							}
							if ( $extended_attributes->{$field}->{'required'} && $data[ $fileheaderPos{$field} ] eq '' ) {
								$problems{$pk_combination} .= "'$field' is a required field and cannot be left blank.<br />";
							} elsif ( $extended_attributes->{$field}->{'option_list'}
								&& defined $fileheaderPos{$field}
								&& $data[ $fileheaderPos{$field} ] ne ''
								&& !$options{ $data[ $fileheaderPos{$field} ] } )
							{
								$" = ', ';
								$problems{$pk_combination} .= "Field '$field' value is not on the allowed list (@optlist).<br />";
								$special_problem = 1;
							} elsif ( $extended_attributes->{$field}->{'format'} eq 'integer'
								&& ( defined $fileheaderPos{$field} && $data[ $fileheaderPos{$field} ] ne '' )
								&& !BIGSdb::Utils::is_int( $data[ $fileheaderPos{$field} ] ) )
							{
								$problems{$pk_combination} .= "Field '$field' must be an integer.<br />";
								$special_problem = 1;
							} elsif (
								$extended_attributes->{$field}->{'format'} eq 'boolean'
								&& (   defined $fileheaderPos{$field}
									&& lc( $data[ $fileheaderPos{$field} ] ) ne 'false'
									&& lc( $data[ $fileheaderPos{$field} ] ) ne 'true' )
							  )
							{
								$problems{$pk_combination} .= "Field '$field' must be boolean (either true or false).<br />";
								$special_problem = 1;
							} elsif ( $data[ $fileheaderPos{$field} ] ne ''
								&& $extended_attributes->{$field}->{'regex'}
								&& $data[ $fileheaderPos{$field} ] !~ /$extended_attributes->{$field}->{'regex'}/ )
							{
								$problems{$pk_combination} .= "Field '$field' does not conform to specified format.<br />\n";
								$special_problem = 1;
							}
						}
					}

					#special case to prevent a new user with curator or admin status unless user is admin themselves
					if ( $table eq 'users' && $field eq 'status' ) {
						if ( $value ne 'user' && !$self->is_admin() ) {
							my $problem_text = "only a user with admin status can add a user with a status other than 'user'<br />";
							$problems{$pk_combination} .= $problem_text
							  if $problems{$pk_combination} !~ /$problem_text/;
							$special_problem = 1;
						}
					} elsif ($table eq 'scheme_group_group_members' &&$field eq 'group_id' && $data[ $fileheaderPos{'parent_group_id'} ] == $data[ $fileheaderPos{'group_id'} ]){
						$problems{$pk_combination} .=
"A scheme group can't be a member of itself.";
						$special_problem = 1;
					}
					my $display_value = $value;
					if ( !( ( my $problem .= $self->is_field_bad( $table, $fieldorder[$i], $value, 'insert' ) ) || $special_problem ) ) {
						if ( $field =~ /sequence/ && $field ne 'coding_sequence' ) {
							$display_value = "<span class=\"seq\">" . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . "</span>";
						}
						$rowbuffer .= "<td>$display_value</td>";
					} else {
						if ( $field =~ /sequence/ && $field ne 'coding_sequence' ) {
							$display_value = "<span class=\"seq\">" . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . "</span>";
						}
						$rowbuffer .= "<td><font color='red'>$display_value</font></td>";
						if ($problem) {
							my $problem_text = "$fieldorder[$i] $problem<br />";
							$problems{$pk_combination} .= $problem_text
							  if $problems{$pk_combination} !~ /$problem_text/;
						}
					}
					$i++;
					$checked_record .= "$value\t"
					  if defined $fileheaderPos{$field}
						  or ( $field eq 'id' );
				}
				if (!$continue){
					undef $header_row if $first_record;
					next;
				};
				$tablebuffer .= "<tr class=\"td$td\">$rowbuffer";
				if ( $table eq $self->{'system'}->{'view'} ) {
					my %is_locus;
					foreach ( @{ $self->{'datastore'}->get_loci() } ) {
						$is_locus{$_} = 1;
					}
					my $locusbuffer;
					foreach (@fileheaderFields) {
						if ( $is_locus{$_} ) {
							$header_row .= "$_\t" if $first_record;
							my $value = $data[ $fileheaderPos{$_} ]
							  if defined $fileheaderPos{$_};
							if ( !$locus_format{$_} ) {
								my $locus_info = $self->{'datastore'}->get_locus_info($_);
								$locus_format{$_} = $locus_info->{'allele_id_format'};
								$locus_regex{$_} = $locus_info->{'allele_id_regex'};
							}
							if ($value) {
								if ( $locus_format{$_} eq 'integer'
									&& !BIGSdb::Utils::is_int($value) )
								{
									$locusbuffer .= "<span><font color='red'>$_:&nbsp;$value</font></span><br />";
									$problems{$pk_combination} .= "'$_' must be an integer<br />";
								} elsif ($locus_regex{$_} && $value !~ /$locus_regex{$_}/){
									$locusbuffer .= "<span><font color='red'>$_:&nbsp;$value</font></span><br />";
									$problems{$pk_combination} .= "'$_' does not conform to specified format.<br />";
								} else {
									$locusbuffer .= "$_:&nbsp;$value<br />";
								}
								$checked_record .= "$value\t";
							} else {
								$checked_record .= "\t";
							}
							$i++;
						}
					}
					$tablebuffer .= "<td>$locusbuffer</td>";
				}
				$tablebuffer .= "</tr>\n";
				if ( $primary_key_combination{$pk_combination} && $pk_combination !~ /\:\s*$/ ) {
					my $problem_text = "primary key submitted more than once in this batch<br />";
					$problems{$pk_combination} .= $problem_text
					  if $problems{$pk_combination} !~ /$problem_text/;
				}
				$primary_key_combination{$pk_combination}++;

				#Check if primary key already in database
				if (@pk_values) {
					eval { $primary_key_check_sql->execute(@pk_values); };
					if ($@) {
						my $message = $@;
						$" = ', ';
						$logger->debug(
"Can't execute primary key check (incorrect data pasted): primary keys: @primary_keys values: @pk_values $message"
						);
						my $plural = scalar @primary_keys > 1 ? 's' : '';
						if ( $message =~ /invalid input/ ) {
							print
"<div class=\"box\" id=\"statusbad\"><p>Your pasted data has invalid primary key field$plural (@primary_keys) data.</p></div>\n";
							return;
						}
						print
"<div class=\"box\" id=\"statusbad\"><p>Your pasted data does not appear to contain the primary key field$plural (@primary_keys) required for this table.</p></div>\n";
						return;
					}
					my ($exists) = $primary_key_check_sql->fetchrow_array();
					if ($exists) {
						my $problem_text = "primary key already exists in the database<br />";
						$problems{$pk_combination} .= $problem_text
						  if $problems{$pk_combination} !~ /$problem_text/;
					}
				}

				#special case to check that sequence exists when adding accession or PubMed number
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'accession' || $table eq 'sequence_refs' ) ) {
					if ( !$self->{'datastore'}->sequence_exists(@pk_values) ) {
						$problems{$pk_combination} .= "Sequence $pk_values[0]-$pk_values[1] does not exist.";
					}

					#special case to ensure that a locus length is set is it is not marked as variable length
				} elsif ( $table eq 'loci' ) {
					if ( (none {$data[ $fileheaderPos{'length_varies'} ] eq $_} qw (true TRUE 1)) && !$data[ $fileheaderPos{'length'} ] ) {
						$problems{$pk_combination} .= "Locus set as non variable length but no length is set.";
					}
					if ( $data[ $fileheaderPos{'id'} ] =~ /^\d/ ) {
						$problems{$pk_combination} .=
"Locus names can not start with a digit.  Try prepending an underscore (_) which will get hidden in the query interface.";
					}
					if ( $data[ $fileheaderPos{'id'} ] =~ /\./ ) {
						$problems{$pk_combination} .=
"Locus names can not contain a period (.).  Try replacing with an underscore (_) - this will get hidden in the query interface.";
					}
					if ( $data[ $fileheaderPos{'id'} ] =~ /\s/ ) {
						$problems{$pk_combination} .=
"Locus names can not contain spaces.  Try replacing with an underscore (_) - this will get hidden in the query interface.";
					}
					#check that user is allowed to access this sequence bin record (controlled by isolate ACL)
				} elsif ( ( $self->{'system'}->{'read_access'} eq 'acl' || $self->{'system'}->{'write_access'} eq 'acl' )
					&& $self->{'username'}
					&& !$self->is_admin
					&& $table eq 'accession'
					&& $self->{'system'}->{'dbtype'} eq 'isolates' )
				{
					my $isolate_id_ref =
					  $self->{'datastore'}
					  ->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $data[ $fileheaderPos{'seqbin_id'} ] );
					if ( ref $isolate_id_ref eq 'ARRAY' && !$self->is_allowed_to_view_isolate( $isolate_id_ref->[0] ) ) {
						$problems{$pk_combination} .=
"The sequence you are trying to add an accession to belongs to an isolate to which your user account is not allowed to access.";
					}

					#check that user is allowed to access this isolate record
				} elsif ( ( $self->{'system'}->{'read_access'} eq 'acl' || $self->{'system'}->{'write_access'} eq 'acl' )
					&& $self->{'username'}
					&& !$self->is_admin
					&& ( $table eq 'allele_designations' || $table eq 'sequence_bin' || $table eq 'isolate_aliases' )
					&& !$self->is_allowed_to_view_isolate( $data[ $fileheaderPos{'isolate_id'} ] ) )
				{
					$problems{$pk_combination} .= "Your user account is not allowed to modify data for this isolate.";

					#check that user is allowed to add sequences for this locus
				}
				if (   ( $table eq 'sequences' || $table eq 'sequence_refs' || $table eq 'accession' )
					&& $self->{'system'}->{'dbtype'} eq 'sequences'
					&& !$self->is_admin )
				{
					if (
						!$self->{'datastore'}->is_allowed_to_modify_locus_sequences(
							( $locus ? $locus : $data[ $fileheaderPos{'locus'} ] ),
							$self->get_curator_id
						)
					  )
					{
						$problems{$pk_combination} .= "Your user account is not allowed to add or modify sequences for locus "
						  . ( $locus || $data[ $fileheaderPos{'locus'} ] ) . ".";
					}
				}
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
			push @checked_buffer, $header_row if $first_record;
			$checked_record =~ s/\t$//;
			push @checked_buffer, $checked_record;
			$first_record = 0;
		}
		$tablebuffer .= "</table></div>\n";
		if ( !$record_count ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No valid data entered. Make sure you've included the header line.</p></div>\n";
			return;
		}
		if (%problems) {
			print "<div class=\"box\" id=\"statusbad\"><h2>Import status</h2>\n";
			print "<table class=\"resultstable\">";
			print "<tr><th>Primary key</th><th>Problem(s)</th></tr>\n";
			my $td = 1;
			foreach my $id ( sort keys %problems ) {
				print "<tr class=\"td$td\"><td>$id</td><td style=\"text-align:left\">$problems{$id}</td></tr>";
				$td = $td == 1 ? 2 : 1;    #row stripes
			}
			print "</table></div>\n";
		} else {
			print
"<div class=\"box\" id=\"resultsheader\"><h2>Import status</h2>$sender_message<p>No obvious problems identified so far.</p>\n";
			my $filename = $self->make_temp_file(@checked_buffer);
			print $q->start_form;
			foreach (qw (page table db sender locus)) {
				print $q->hidden($_);
			}
			print $q->hidden( 'checked_buffer', $filename );
			print $q->submit( -name => 'Import data', -class => 'submit' );
			print $q->endform;
			print "</div>\n";
		}
		print "<div class=\"box\" id=\"resultstable\"><h2>Data to be imported</h2>\n";
		print "<p>The following table shows your data.  Any field coloured red has a problem and needs to be checked.</p>\n";
		print $tablebuffer;
		print "</div><p />";
	} else {
		my $record_name = $self->get_record_name($table);
		print << "HTML";
<div class="box" id="queryform">
<p>This page allows you to upload $record_name data as tab-delimited text or 
copied from a spreadsheet.</p>
<ul>
<li>Field header names must be included and fields
can be in any order. Optional fields can be omitted if you wish.</li>
HTML
		if ( $table eq $self->{'system'}->{'view'} ) {
			print << "HTML";
<li>Enter aliases (alternative names) for your isolates as a semi-colon (;) separated list.</li>	
<li>Enter references for your isolates as a semi-colon (;) separated list of PubMed ids (non integer ids will be ignored).</li>				  
<li>You can also upload allele fields along with the other isolate data - simply create a new column with the locus name. These will be
added with a confirmed status and method set as 'manual'.</li>	
HTML
		}
		if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			print << "HTML";
<li>Enter aliases (alternative names) for your locus as a semi-colon (;) separated list.</li>			
HTML
		}
		if ($integer_id) {
			print << "HTML";
<li>You can choose whether or not to include an id number 
field - if it is omitted, the next available id will be used automatically.</li>
HTML
		}
		my $locus_attribute;
		if ( $table eq 'sequences') {
			$locus_attribute = "&amp;locus=$locus" if $locus;
			print << "HTML";
			<li>If the locus uses integer allele ids you can leave the allele_id field blank and the next available number will be used.</li>
HTML
		}
		print << "HTML";
</ul>
<ul>
<li><a href="$script_name?db=$self->{'instance'}&amp;page=tableHeader&amp;table=$table$locus_attribute">Download tab-delimited 
header for your spreadsheet</a> - use Paste special &rarr; text to paste the data.
HTML
		if ( $table eq 'sequences' && !$q->param('locus') ) {
			my $loci_with_extended =
			  $self->{'datastore'}->run_list_query("SELECT DISTINCT locus FROM locus_extended_attributes ORDER BY locus");
			if ( ref $loci_with_extended eq 'ARRAY' ) {
				print
				  " Please note, some loci have extended attributes which may be required.  For affected loci please use the batch insert
				page specific to that locus: ";
				if (@$loci_with_extended > 10){
					print $q->start_form;
					foreach (qw (page db table)){
						print $q->hidden($_);
					}
					print "Reload page specific for locus: ";
					my @values = @$loci_with_extended;
					my %labels;
					unshift @values, '';
					$labels{''} = 'Select ...';
					print $q->popup_menu(-name => 'locus', -values => \@values, -labels => \%labels);
					print $q->submit (-name => 'Reload', -class => 'submit');
					print $q->end_form;
				} else {
					my $first = 1;
					foreach (@$loci_with_extended) {
						print ' | ' if !$first;
						print
	"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences&amp;locus=$_\">$_</a>";
						$first = 0;
					}
				}
			}
		}
		print "</li>\n</ul>\n";
		print $q->start_form;
		if ($sender_field) {
			my $qry = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute(); };
			if ($@) {
				$logger->error("Can't execute: $qry");
			} else {
				$logger->debug("Query: $qry");
			}
			my @users;
			my %usernames;
			$usernames{''} = 'Select sender ...';
			while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
				push @users, $userid;
				$usernames{$userid} = "$surname, $firstname ($username)";
			}
			print "<p>Please select the sender from the list below:</p>\n";
			$usernames{-1} = 'Override with sender field';
			print "<table><tr><td>\n";
			print $q->popup_menu( -name => 'sender', -values => [ '', -1, @users ], -labels => \%usernames );
			print
			  "</td><td class=\"comment\">Value will be overridden if you include a sender field in your pasted data.</td></tr></table>\n";
		}
		if ( $table eq 'sequences' ) {
			print "<ul style=\"list-style-type:none\"><li>\n";
			print $q->checkbox( -name => 'ignore_existing', -label => 'Ignore existing sequences',  -checked => 'checked' );
			print "</li><li>\n";
			print $q->checkbox( -name => 'ignore_non_DNA', -label => 'Ignore sequences containing non-nucleotide characters' );
			print "</li><li>\n";
			print $q->checkbox(
				-name => 'complete_CDS',
				-label =>
'Silently reject all sequences that are not complete reading frames - these must have a start and in-frame stop codon at the ends and no internal stop codons.  Existing sequences are also ignored.'
			);
			print "</li><li>\n";
			print $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
			print "</li></ul>\n";
		}
		print "<p>Please paste in tab-delimited text (<strong>include a field header line</strong>).</p>\n";
		foreach (qw (page db table locus)) {
			print $q->hidden($_);
		}
		print $q->textarea( -name => 'data', -rows => 20, -columns => 120 );
		print "<table style=\"width:95%\"><tr><td>";
		print $q->reset( -class => 'reset' );
		print "</td><td style=\"text-align:right\">";
		print $q->submit( -class => 'submit' );
		print "</td></tr></table><p />\n";
		print $q->end_form;
		print "<p><a href=\"" . $q->script_name . "/?db=$self->{'instance'}\">Back</a></p>\n";
		print "</div>\n";
	}
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return "Batch add new $type records - $desc";
}

sub _get_fields_in_order {

	#Return list of fields in order
	my ( $self, $table ) = @_;
	my @fieldnums;
	if ( $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			push @fieldnums, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @fieldnums, 'aliases';
				push @fieldnums, 'references';
			}
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @fieldnums, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @fieldnums, 'aliases';
			}
		}
	}
	return @fieldnums;
}

sub _get_field_table_header {
	my ( $self, $table ) = @_;
	my @headers;
	if ( $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @headers, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @headers, 'aliases';
				push @headers, 'references';
			}
		}
		push @headers, 'loci';
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @headers, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @headers, 'aliases';
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' && $self->{'cgi'}->param('locus') ) {
			my $extended_attributes_ref =
			  $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order",
				$self->{'cgi'}->param('locus') );
			if ( ref $extended_attributes_ref eq 'ARRAY' ) {
				push @headers, @$extended_attributes_ref;
			}
		}
	}
	$" = "</th><th>";
	return "<th>@headers</th>";
}

sub _is_id_used {
	my ( $self, $table, $id ) = @_;
	my $qry = "SELECT count(id) FROM $table WHERE id=?";
	if ( !$self->{'sql'}->{'id_used'} ) {
		$self->{'sql'}->{'id_used'} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'id_used'}->execute($id); };
	if ($@) {
		$logger->error("Can't execute: $qry value:$id");
	} else {
		$logger->debug("Query: $qry value:$id");
	}
	my ($used) = $self->{'sql'}->{'id_used'}->fetchrow_array;
	return $used;
}

sub _process_fields {
	my ( $self, $data ) = @_;
	my @return_data;
	foreach my $value (@$data) {
		$value =~ s/^\s+//;
		$value =~ s/\s+$//;
		$value =~ s/'/\'\'/g;
		$value =~ s/\r//g;
		$value =~ s/\n/ /g;
		if ( $value eq '' ) {
			push @return_data, 'null';
		} else {
			push @return_data, $value;
		}
	}
	return @return_data;
}
1;
