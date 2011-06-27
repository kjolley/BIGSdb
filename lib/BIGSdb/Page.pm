#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::Page;
use strict;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);
use Time::HiRes qw(gettimeofday);
use List::MoreUtils qw(uniq any none);
use base 'Exporter';
use constant SEQ_METHODS => (
	'454',
	'Illumina',
	'Ion Torrent',
	'PacBio',
	'Sanger',
	'Solexa',    #deprecated
	'SOLiD',
	'other',
	'unknown'
);
use constant SEQ_FLAGS => (
	'ambiguous read',
	'apparent misassembly',
	'downstream fusion',
	'frameshift',
	'internal stop codon',
	'no start codon',
	'truncated',
	'upstream fusion'
);
use constant DATABANKS => qw(Genbank);
our @EXPORT = qw(SEQ_METHODS SEQ_FLAGS DATABANKS);

sub new {
	my $class = shift;
	my $self  = {@_};
	$self->{'prefs'} = {};
	$logger->logdie("No CGI object passed")     if !$self->{'cgi'};
	$logger->logdie("No system hashref passed") if !$self->{'system'};
	$self->{'type'} = 'xhtml' if !$self->{'type'};
	bless( $self, $class );
	$self->initiate;
	$self->set_pref_requirements;
	return $self;
}

sub set_cookie_attributes {
	my ( $self, $cookies ) = @_;
	$self->{'cookies'} = $cookies;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;    #Use JQuery javascript library
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 1, 'isolate_display' => 1, 'analysis' => 1, 'query_field' => 1 };
}

sub get_javascript {

	#Override by returning javascript code to include in header
	return "";
}

sub get_guid {

	#If this is a non-public database, use a combination of database and user names as the
	#GUID for preference storage, otherwise use a random GUID which is stored as a browser cookie.
	my ($self) = @_;
	if ( $self->{'system'}->{'read_access'} ne 'public' ) {
		return "$self->{'system'}->{'db'}\|$self->{'username'}";
	} elsif ( $self->{'cgi'}->cookie( -name => 'guid' ) ) {
		return $self->{'cgi'}->cookie( -name => 'guid' );
	} else {
		return 0;
	}
}

sub get_tree_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('a[rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
  			if (this.href.match(/javascript.loadContent/)){
  				return;
  			};
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1&no_header=1\'\)"));
    	});
  	});
	\$("#tree").jstree({ 
		"core" : {
			"animation" : 200,
			"initially_open" : ["all_loci"]
		},
		"themes" : {
			"theme" : "default"
		},
		"plugins" : [ "themes", "html_data"]
	});

});

function loadContent(url) {
	\$("#scheme_table").html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url,tooltip);
}

tooltip = function(e){
	\$('div.content a').tooltip({ 
	    track: true, 
	    delay: 0, 
	    showURL: false, 
	    showBody: " - ", 
	    fade: 250 
	});
};
END
	return $buffer;
}

sub print {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$" = ' ';
	if ( $q->param('page') eq 'plugin' ) {

		#need to determine if tooltips should be displayed since this is set in the <HEAD>;
		if ( $self->{'prefstore'} ) {
			my $guid = $self->get_guid;
			try {
				$self->{'prefs'}->{'tooltips'} =
				  $self->{'prefstore'}->get_tooltips_pref( $guid, $self->{'system'}->{'db'} ) eq 'on' ? 1 : 0;
			}
			catch BIGSdb::DatabaseNoRecordException with {
				$self->{'prefs'}->{'tooltips'} = 1;
			}
		}
	} else {
		$self->initiate_prefs;
	}
	if ( $self->{'type'} ne 'xhtml' ) {
		my %atts;
		if ( $self->{'type'} eq 'embl' ) {
			$atts{'type'} = 'chemical/x-embl-dl-nucleotide';
			$atts{'attachment'} = 'sequence' . ( $q->param('seqbin_id') ) . '.embl';
		} elsif ( $self->{'type'} eq 'no_header' ) {
			$atts{'type'} = 'text/html';
		} else {
			$atts{'type'} = 'text/plain';
		}
		$atts{'expires'} = '+1h' if !$self->{'noCache'};
		print $q->header( \%atts );
		$self->print_content();
	} else {
		my $stylesheet = $self->get_stylesheet();
		if ( !$q->cookie( -name => 'guid' ) && $self->{'prefstore'} ) {
			my $guid = $self->{'prefstore'}->get_new_guid();
			push @{ $self->{'cookies'} }, $q->cookie( -name => 'guid', -value => $guid, -expires => '+10y' );
			$self->{'setOptions'} = 1;
		}
		$q->charset('UTF-8');
		my %header_options = ( -cookie => $self->{'cookies'} );
		if ( !$self->{'noCache'} ) {
			$header_options{'expires'} = '+1h';
		}
		print $q->header(%header_options);
		my $title = $self->get_title();
		$" = ' ';    #needed to reset when running under mod_perl
		my $page_js = $self->get_javascript;
		my @javascript;
		if ( $self->{'jQuery'} ) {
			if ( $self->{'config'}->{'intranet'} eq 'yes' ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.js" } );
			} else {

				#Load jQuery library from Google CDN
				push @javascript,
				  ( { 'language' => 'Javascript', 'src' => "http://ajax.googleapis.com/ajax/libs/jquery/1.6.1/jquery.min.js" } );
			}
			foreach (qw (jquery.tooltip.js cornerz.js bigsdb.js)) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/$_" } );
			}
			if ( $self->{'jQuery.tablesort'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.tablesorter.js" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.metadata.js" } );
			}
			if ( $self->{'jQuery.jstree'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.jstree.js?v20110605" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.cookie.js" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.hotkeys.js" } );
			}
			push @javascript, { 'language' => 'Javascript', 'code' => $page_js } if $page_js;
		}

		#META tag inclusion code written by Andreas Tille.
		my $meta_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/meta.html";
		my %meta_content;
		my %shortcut_icon;
		if ( -e $meta_file ) {
			if ( open( my $fh, '<', $meta_file ) ) {
				while (<$fh>) {
					if ( $_ =~ /<meta\s+name="([^"]+)"\s+content="([^"]+)"\s*\/?>/ ) {
						$meta_content{$1} = $2;
					}
					if ( $_ =~ /<link\s+rel="shortcut icon"\s+href="([^"]+)"\s+type="([^"]+)"\s*\/?>/ ) {
						$shortcut_icon{'-rel'}  = 'shortcut icon';
						$shortcut_icon{'-href'} = $1;
						$shortcut_icon{'-type'} = $2;
					}
				}
				close $fh;
			}
		}
		my $http_equiv;
		if ( $self->{'refresh'} ) {
			$http_equiv = "<meta http-equiv=\"refresh\" content=\"$self->{'refresh'}\" />";
		}
		my $tooltip_display = $self->{'prefs'}->{'tooltips'} ? 'inline' : 'none';
		if (%shortcut_icon) {
			print $q->start_html(
				-title => $title,
				-meta  => {%meta_content},
				-style => { -src => $stylesheet, -code => ".tooltip{display:$tooltip_display}" },
				-head   => [ CGI->Link( {%shortcut_icon} ), $http_equiv ],
				-script => \@javascript
			);
		} else {
			print $q->start_html(
				-title  => $title,
				-meta   => {%meta_content},
				-style  => { -src => $stylesheet, -code => ".tooltip{display:$tooltip_display}" },
				-script => \@javascript,
				-head   => $http_equiv
			);
		}
		$self->_print_header();
		$self->_print_login_details if $self->{'system'}->{'read_access'} ne 'public' || $self->{'curate'};
		my $page = $q->param('page');
		$self->_print_help_panel;
		$self->print_content();
		$self->_print_footer();
		print $q->end_html;
	}
}

sub get_stylesheet {
	my ($self) = @_;
	my $stylesheet;
	my $system   = $self->{'system'};
	my $filename = 'bigsdb.css?v=20110616';
	if ( !$system->{'db'} ) {
		$stylesheet = "/$filename";
	} elsif ( -e "$ENV{'DOCUMENT_ROOT'}$system->{'webroot'}/$system->{'db'}/$filename" ) {
		$stylesheet = "$system->{'webroot'}/$system->{'db'}/$filename";
	} else {
		$stylesheet = "$system->{'webroot'}/$filename";
	}
	return $stylesheet;
}
sub get_title     { return 'BIGSdb' }
sub print_content { }

sub _print_header {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $filename = $self->{'curate'} ? 'curate_header.html' : 'header.html';
	my $header_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/$filename";
	$self->print_file($header_file) if ( -e $header_file );
}

sub _print_login_details {
	my ($self) = @_;
	return if !$self->{'datastore'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	print "<div id=\"logindetails\">";
	if ( !$user_info ) {
		if ( !$self->{'username'} ) {
			print "<i>Not logged in.</i>\n";
		} else {
			print "<i>Logged in: <b>Unregistered user.</b></i>\n";
		}
	} else {
		print "<i>Logged in: <b>$user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'}).</b></i>\n";
	}
	if ( $self->{'system'}->{'authentication'} eq 'builtin' ) {
		if ( $self->{'username'} ) {
			print " <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=logout\">Log out</a> | ";
			print " <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=changePassword\">Change password</a>";
		}
	}
	print "</div>\n";
}

sub _print_help_panel {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<div id=\"fieldvalueshelp\">";
	if ( $q->param('page') eq 'plugin' && defined $self->{'pluginManager'} ) {
		my $plugin_att = $self->{'pluginManager'}->get_plugin_attributes( $q->param('name') );
		if ( ref $plugin_att eq 'HASH' ) {
			foreach (qw (tooltips)) {
				if ( $plugin_att->{'help'} =~ /$_/ ) {
					$self->{$_} = 1;
				}
			}
		}
	}
	if ( any { $self->{$_} } qw (tooltips) ) {
		print "<span id=\"toggle\" style=\"display:none\">Toggle: </span>";
		if ( $self->{'tooltips'} ) {
			print
"<a id=\"toggle_tooltips\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=options&amp;toggle_tooltips=1\" style=\"display:none; margin-right:1em;\">&nbsp;<i>i</i>&nbsp;</a> ";
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $self->{'field_help'} ) {

		#open new page unless already on field values help page
		if ( $q->param('page') eq 'fieldValues' ) {
			print $q->start_form( -style => 'display:inline' );
		} else {
			print $q->start_form( -target => '_blank', -style => 'display:inline' );
		}
		print "<b>Field help: </b>";
		my ( $values, $labels ) = $self->get_field_selection_list( { 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1 } );
		print $q->popup_menu( -name => 'field', -values => $values, -labels => $labels );
		print $q->submit( -name => 'Go', -class => 'fieldvaluebutton' );
		my $refer_page = $q->param('page');
		$q->param( 'page', 'fieldValues' );
		foreach (qw (db page)) {
			print $q->hidden($_);
		}
		print $q->end_form;
		$q->param( 'page', $refer_page );
	}
	print "</div>\n";
}

sub get_extended_attributes {
	my ($self) = @_;
	my $extended;
	my $sql = $self->{'db'}->prepare("SELECT isolate_field,attribute FROM isolate_field_extended_attributes ORDER BY field_order");
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my ( $field, $attribute ) = $sql->fetchrow_array ) {
		push @{ $extended->{$field} }, $attribute;
	}
	return $extended;
}

sub get_field_selection_list {

	#options passed as hashref:
	#isolate_fields: include isolate fields, prefix with f_
	#extended_attributes: include isolate field extended attributes, named e_FIELDNAME||EXTENDED-FIELDNAME
	#loci: include loci, prefix with either l_ or cn_ (common name)
	#all_loci: include all loci, if not included or set to 0 the query flag in the locus table will be taken into account
	#scheme_fields: include scheme fields, prefix with s_SCHEME-ID_
	#sort_labels: dictionary sort labels
	my ( $self, $options ) = @_;
	if ( ref $options ne 'HASH' ) {
		$logger->error("Invalid option hashref");
		return;
	}
	my @values;
	my $extended = $self->get_extended_attributes if $options->{'extended_attributes'};
	if ( $options->{'isolate_fields'} ) {
		my @isolate_list;
		my $fields     = $self->{'xmlHandler'}->get_field_list;
		my $attributes = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach (@$fields) {
			if (   ( $options->{'sender_attributes'} )
				&& ( $_ eq 'sender' || $_ eq 'curator' || ( $attributes->{$_}->{'userfield'} eq 'yes' ) ) )
			{
				foreach my $user_attribute (qw (id surname first_name affiliation)) {
					push @isolate_list, "f_$_ ($user_attribute)";
					( $self->{'cache'}->{'labels'}->{"f_$_ ($user_attribute)"} = "$_ ($user_attribute)" ) =~ tr/_/ /;
				}
			} else {
				push @isolate_list, "f_$_";
				( $self->{'cache'}->{'labels'}->{"f_$_"} = $_ ) =~ tr/_/ /;
				if ( $options->{'extended_attributes'} ) {
					my $extatt = $extended->{$_};
					if ( ref $extatt eq 'ARRAY' ) {
						foreach my $extended_attribute (@$extatt) {
							push @isolate_list, "e_$_||$extended_attribute";
							$self->{'cache'}->{'labels'}->{"e_$_||$extended_attribute"} = "$_..$extended_attribute";
						}
					}
				}
			}
		}
		push @values, @isolate_list;
	}
	if ( $options->{'loci'} ) {
		if ( !$self->{'cache'}->{'loci'} ) {
			my @locus_list;
			my $qry    = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
			my $cn_sql = $self->{'db'}->prepare($qry);
			eval { $cn_sql->execute; };
			if ($@) {
				$logger->error("Can't execute $@");
			}
			my $common_names = $cn_sql->fetchall_hashref('id');
			my $loci =
			    $options->{'all_loci'}
			  ? $self->{'datastore'}->get_loci( { 'query_pref' => 0, 'seq_defined' => 0, 'do_not_order' => 1 } )
			  : $self->{'datastore'}->get_loci( { 'query_pref' => 1, 'seq_defined' => 0, 'do_not_order' => 1 } );
			foreach (@$loci) {
				push @locus_list, "l_$_";
				$self->{'cache'}->{'labels'}->{"l_$_"} = $_;
				if ( $common_names->{$_}->{'common_name'} ) {
					$self->{'cache'}->{'labels'}->{"l_$_"} .= " ($common_names->{$_}->{'common_name'})";
					push @locus_list, "cn_$_";
					$self->{'cache'}->{'labels'}->{"cn_$_"} = "$common_names->{$_}->{'common_name'} ($_)";
					$self->{'cache'}->{'labels'}->{"cn_$_"} =~ tr/_/ /;
				}
				$self->{'cache'}->{'labels'}->{"l_$_"} =~ tr/_/ /;
			}
			if ( $self->{'prefs'}->{'locus_alias'} ) {
				my $qry       = "SELECT locus,alias FROM locus_aliases";
				my $alias_sql = $self->{'db'}->prepare($qry);
				eval { $alias_sql->execute; };
				if ($@) {
					$logger->error("Can't execute $@");
				} else {
					my $array_ref = $alias_sql->fetchall_arrayref;
					foreach (@$array_ref) {
						my ( $locus, $alias ) = @$_;

						#if there is no label for the primary name it is because the locus
						#should not be displayed
						next if !$self->{'cache'}->{'labels'}->{"l_$locus"};
						$alias =~ tr/_/ /;
						push @locus_list, "la_$locus||$alias";
						$self->{'cache'}->{'labels'}->{"la_$locus||$alias"} =
						  "$alias [" . ( $self->{'cache'}->{'labels'}->{"l_$locus"} ) . ']';
					}
				}
			}
			@locus_list = sort { lc( $self->{'cache'}->{'labels'}->{$a} ) cmp lc( $self->{'cache'}->{'labels'}->{$b} ) } @locus_list;
			@locus_list = uniq @locus_list;
			$self->{'cache'}->{'loci'} = \@locus_list;
		}
		push @values, @{ $self->{'cache'}->{'loci'} };
	}
	if ( $options->{'scheme_fields'} ) {
		if ( !$self->{'cache'}->{'scheme_fields'} ) {
			my @scheme_field_list;
			my $qry = "SELECT id, description FROM schemes ORDER BY display_order,id";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute(); };
			if ($@) {
				$logger->error("Can't execute: $qry");
			}
			my $scheme_fields = $self->{'datastore'}->get_all_scheme_fields;
			my $scheme_info   = $self->{'datastore'}->get_all_scheme_info;
			while ( my ( $scheme_id, $desc ) = $sql->fetchrow_array() ) {
				my $scheme_db = $scheme_info->{$scheme_id}->{'dbase_name'};

				#No point using scheme fields if no scheme database is available.
				if (   $self->{'prefs'}->{'query_field_schemes'}->{$scheme_id}
					&& $scheme_db )
				{
					foreach my $field ( @{ $scheme_fields->{$scheme_id} } ) {
						if ( $self->{'prefs'}->{'query_field_scheme_fields'}->{$scheme_id}->{$field} ) {
							( $self->{'cache'}->{'labels'}->{"s_$scheme_id\_$field"} = "$field ($desc)" ) =~ tr/_/ /;
							push @scheme_field_list, "s_$scheme_id\_$field";
						}
					}
				}
			}
			$self->{'cache'}->{'scheme_fields'} = \@scheme_field_list;
		}
		push @values, @{ $self->{'cache'}->{'scheme_fields'} };
	}
	if ( $options->{'sort_labels'} ) {

		#dictionary sort
		@values = map { $_->[0] }
		  sort { $a->[1] cmp $b->[1] }
		  map {
			my $d = lc( $self->{'cache'}->{'labels'}->{$_} );
			$d =~ s/[\W_]+//g;
			[ $_, $d ]
		  } uniq @values;
	}
	return \@values, $self->{'cache'}->{'labels'};
}

sub _print_footer {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $filename = $self->{'curate'} ? 'curate_footer.html' : 'footer.html';
	my $footer_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/$filename";
	$self->print_file($footer_file) if ( -e $footer_file );
}

sub print_file {
	my ( $self, $file, $ignore_hashlines ) = @_;
	my $logger = get_logger('BIGSdb.Page');
	my $lociAdd;
	my $loci;
	if ( $self->{'curate'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		if ( $self->is_admin ) {
			$loci = $self->{'datastore'}->get_loci();
		} else {
			my $qry =
"SELECT locus_curators.locus from locus_curators LEFT JOIN loci ON locus=id LEFT JOIN scheme_members on loci.id = scheme_members.locus WHERE locus_curators.curator_id=? ORDER BY scheme_members.scheme_id,locus_curators.locus";
			$loci = $self->{'datastore'}->run_list_query( $qry, $self->get_curator_id );
		}
		my $first = 1;
		foreach (@$loci) {
			my $cleaned = $self->clean_locus($_);
			if ( !$first ) {
				$lociAdd .= ' | ';
			}
			$lociAdd .=
			    "<a href=\""
			  . $self->{'system'}->{'script_name'}
			  . "?db=$self->{'instance'}&amp;page=add&amp;table=sequences&amp;locus=$_\">$cleaned</a>";
			$first = 0;
		}
	}
	if ( -e $file ) {
		my $system = $self->{'system'};
		open( my $fh, '<', $file ) or return;
		while (<$fh>) {
			next if $_ =~ /^#/ && $ignore_hashlines;
			$_ =~ s/\$instance/$self->{'instance'}/;
			$_ =~ s/\$webroot/$system->{'webroot'}/;
			$_ =~ s/\$dbase/$system->{'db'}/;
			$_ =~ s/\$indexpage/$system->{'indexpage'}/;
			if ( $self->{'curate'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
				if ( @$loci && @$loci < 30 ) {
					$_ =~ s/\$lociAdd/$lociAdd/;
				} else {
					$_ =~
s/\$lociAdd/<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences">Add<\/a>/;
				}
			}
			print $_;
		}
		close $fh;
	} else {
		$logger->warn("File $file does not exist.");
	}
}

sub get_filter {
	my ( $self, $name, $values, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $filter = $options->{'class'} || 'filter';
	( my $text = $options->{'text'} || $name ) =~ tr/_/ /;
	my ($label, $title) = $self->_get_truncated_label("$text: ");	
	my $buffer = "<label for=\"$name\_list\" class=\"$filter\" title=\"$title\">$label</label>\n";
	$" = ' ';
	$buffer .= $self->{'cgi'}->popup_menu(
		-name   => "$name\_list",
		-id     => "$name\_list",
		-values => [ '', @$values ],
		-labels => $options->{'labels'},
		-class  => $filter
	);
	$options->{'tooltip'} =~ tr/_/ /;
	$buffer .= " <a class=\"tooltip\" title=\"$options->{'tooltip'}.\">&nbsp;<i>i</i>&nbsp;</a>" if $options->{'tooltip'};
	return $buffer;
}

sub get_user_filter {
	my ( $self, $field, $table ) = @_;
	my $qry = "SELECT DISTINCT($field) FROM $table WHERE $field > 0";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };
	$logger->error($@) if $@;
	my @userids;
	while ( my ($value) = $sql->fetchrow_array ) {
		push @userids, $value;
	}
	$qry = "SELECT id,first_name,surname FROM users where id=?";
	$sql = $self->{'db'}->prepare($qry);
	my ( @usernames, %labels );
	foreach (@userids) {
		eval { $sql->execute($_); };
		$logger->error($@) if $@;
		while ( my @data = $sql->fetchrow_array ) {
			push @usernames, $data[0];
			$labels{ $data[0] } = $data[2] eq 'applicable' ? 'not applicable' : "$data[2], $data[1]";
		}
	}
	@usernames =
	  sort { lc( $self->{'cache'}->{'username_labels'}->{$table}->{$a} ) cmp lc( $self->{'cache'}->{'username_labels'}->{$table}->{$b} ) }
	  @usernames;
	my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
	return $self->get_filter( $field, \@usernames, { 'labels' => \%labels, 'tooltip' => "$field filter - Select $a_or_an $field to filter your search to only those records that match the selected $field" } );
}

sub get_scheme_filter {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'schemes'} ) {
		my $qry = "SELECT id,description FROM schemes ORDER BY display_order,id";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(); };
		$logger->error($@) if $@;
		while ( my @data = $sql->fetchrow_array() ) {
			push @{ $self->{'cache'}->{'schemes'} }, $data[0];
			$self->{'cache'}->{'scheme_labels'}->{ $data[0] } = $data[1];
		}
		push @{ $self->{'cache'}->{'schemes'} }, 0;
		$self->{'cache'}->{'scheme_labels'}->{0} = 'No scheme';
	}
	my $buffer = $self->get_filter(
		'scheme',
		$self->{'cache'}->{'schemes'},
		{
			'labels'  => $self->{'cache'}->{'scheme_labels'},
			'tooltip' => 'scheme filter - Select a scheme to filter your search to only those belonging to the selected scheme.'
		}
	);
	return $buffer;
}

sub _get_truncated_label {
	my ($self, $label) = @_;
	my $title;
	if (length $label > 25){
		$title = $label;
		$title =~ tr/\"//;
		$label = "<a title=\"$title\" class=\"truncated\">" . substr ($label, 0, 20) . "&#133</a>";				
	}
	return ($label,$title);
}

sub paged_display {

	# $count is optional - if not provided it will be calculated, but this may not be the most
	# efficient algorithm, so if it has already been calculated prior to passing to this subroutine
	# it is better to not recalculate it.
	my ( $self, $table, $qry, $message, $hidden_attributes, $count, $passed_qry ) = @_;
	$passed_qry = $qry if !$passed_qry;    #query can get rewritten on route to this page - this enables the original query to be passed on
	if ( $table eq 'allele_sequences' && $passed_qry =~ /sequence_flags/ ) {
		$self->{'db'}->do("SET enable_nestloop = off");
	}
	my $schemes  = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my $continue = 1;
	try {
		foreach (@$schemes) {
			if ( $qry =~ /temp_scheme_$_\s/ || $qry =~ /ORDER BY s_$_\_/ ) {
				if ( $self->{'datastore'}->create_temp_scheme_table($_) == -1 ) {
					print
"<div class=\"box\" id=\"statusbad\"><p>Can't copy data into temporary table - please check scheme configuration (more details will be in the log file).</p></div>\n";
					$continue = 0;
				}
			}
		}
	}
	catch BIGSdb::DatabaseConnectionException with {
		print "<div class=\"box\" id=\"statusbad\"><p>Can not connect to remote database.  The query can not be performed.</p></div>\n";
		$continue = 0;
	};
	return if !$continue;
	my $q = $self->{'cgi'};
	$message = $q->param('message') if !$message;

	#sort allele_id integers numerically
	$qry =~
s/ORDER BY (.+),\s*\S+\.allele_id(.*)/ORDER BY $1,\(case when allele_id ~ '^[0-9]+\$' THEN lpad\(allele_id,10,'0'\) else allele_id end\)$2/;
	$qry =~
	  s/ORDER BY \S+\.allele_id(.*)/ORDER BY \(case when allele_id ~ '^[0-9]+\$' THEN lpad\(allele_id,10,'0'\) else allele_id end\)$1/;
	my $totalpages = 1;
	my $bar_buffer;
	if ( $q->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $q->param('displayrecs') eq 'all' ? 0 : $q->param('displayrecs');
	}
	my $currentpage = $q->param('currentpage') ? $q->param('currentpage') : 1;
	if    ( $q->param('>') )        { $currentpage++ }
	elsif ( $q->param('<') )        { $currentpage-- }
	elsif ( $q->param('pagejump') ) { $currentpage = $q->param('pagejump') }
	elsif ( $q->param('Last') )     { $currentpage = $q->param('lastpage') }
	elsif ( $q->param('First') )    { $currentpage = 1 }
	my $records;

	if ($count) {
		$records = $count;
	} else {
		my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');
		my $start            = gettimeofday();
		my $qrycount         = $qry;
		if ( $table eq 'allele_sequences' ) {
			$qrycount =~
s/SELECT \*/SELECT COUNT \(DISTINCT allele_sequences.seqbin_id||allele_sequences.locus||allele_sequences.start_pos||allele_sequences.end_pos\)/;
		}
		$qrycount =~ s/SELECT \*/SELECT COUNT \(\*\)/;
		$qrycount =~ s/ORDER BY.*//;
		$records = $self->{'datastore'}->run_simple_query($qrycount)->[0];
		my $end     = gettimeofday();
		my $elapsed = $end - $start;
		$elapsed =~ s/(^\d{1,}\.\d{4}).*$/$1/;
		$logger_benchmark->debug("Time to execute count query : $elapsed seconds");
	}
	$q->param( 'query',       $passed_qry );
	$q->param( 'currentpage', $currentpage );
	$q->param( 'displayrecs', $self->{'prefs'}->{'displayrecs'} );
	if ( $self->{'prefs'}->{'displayrecs'} > 0 ) {
		$totalpages = $records / $self->{'prefs'}->{'displayrecs'};
	} else {
		$totalpages = 1;
		$self->{'prefs'}->{'displayrecs'} = 0;
	}
	$bar_buffer .= $q->start_form;
	$q->param( 'table', $table );
	$bar_buffer .= $q->hidden($_) foreach qw (query currentpage page db displayrecs order table direction sent);
	$bar_buffer .= $q->hidden( 'message', $message ) if $message;

	#Make sure hidden_attributes don't duplicate the above
	foreach (@$hidden_attributes) {
		$bar_buffer .= $q->hidden($_) . "\n" if $q->param($_) ne '';
	}
	if ( $currentpage > 1 || $currentpage < $totalpages ) {
		$bar_buffer .= "<table>\n<tr><td>Page:</td>\n";
		if ( $currentpage > 1 ) {
			$bar_buffer .= "<td>";
			$bar_buffer .= $q->submit( -name => 'First', -class => 'pagebar' );
			$bar_buffer .= "</td><td>";
			$bar_buffer .= $q->submit( -name => $currentpage == 2 ? 'First' : '<', -label => ' < ', -class => 'pagebar' );
			$bar_buffer .= "</td>";
		}
		if ( $currentpage > 1 || $currentpage < $totalpages ) {
			my ( $first, $last );
			if   ( $currentpage < 9 ) { $first = 1 }
			else                      { $first = $currentpage - 8 }
			if ( $totalpages > ( $currentpage + 8 ) ) {
				$last = $currentpage + 8;
			} else {
				$last = $totalpages;
			}
			$bar_buffer .= "<td>";
			for ( my $i = $first ; $i < $last + 1 ; $i++ ) {
				if ( $i == $currentpage ) {
					$bar_buffer .=
					  "</td><th style=\"font-size: 84%; border: 1px solid black; padding-left: 5px; padding-right: 5px\">$i</th><td>";
				} else {
					$bar_buffer .=
					  $q->submit( -name => $i == 1 ? 'First' : 'pagejump', -value => $i, -label => " $i ", -class => 'pagebar' );
				}
			}
			$bar_buffer .= "</td>\n";
		}
		if ( $currentpage < $totalpages ) {
			$bar_buffer .= "<td>";
			$bar_buffer .= $q->submit( -name => '>', -label => ' > ', -class => 'pagebar' );
			$bar_buffer .= "</td><td>";
			my $lastpage;
			if ( BIGSdb::Utils::is_int($totalpages) ) {
				$lastpage = $totalpages;
			} else {
				$lastpage = int $totalpages + 1;
			}
			$q->param( 'lastpage', $lastpage );
			$bar_buffer .= $q->hidden('lastpage');
			$bar_buffer .= $q->submit( -name => 'Last', -class => 'pagebar' );
			$bar_buffer .= "</td>";
		}
		$bar_buffer .= "</tr></table>\n";
		$bar_buffer .= $q->endform();
	}
	print "<div class=\"box\" id=\"resultsheader\">\n";
	if ($records) {
		print "<p>$message</p>" if $message;
		my $plural = $records == 1 ? '' : 's';
		print "<p>$records record$plural returned";
		if ( $currentpage && $self->{'prefs'}->{'displayrecs'} ) {
			if ( $records > $self->{'prefs'}->{'displayrecs'} ) {
				my $first = ( ( $currentpage - 1 ) * $self->{'prefs'}->{'displayrecs'} ) + 1;
				my $last = $currentpage * $self->{'prefs'}->{'displayrecs'};
				if ( $last > $records ) {
					$last = $records;
				}
				print $first == $last ? " (record $first displayed)." : " ($first - $last displayed).";
			} else {
				print ".";
			}
		} else {
			print ".";
		}
		if ( !$self->{'curate'} || $table eq $self->{'system'}->{'view'} ) {
			print " Click the hyperlink$plural for detailed information.";
		}
		print "</p>\n";
		if ( $self->{'curate'} && $self->can_modify_table($table) ) {
			if ( !( $table eq 'allele_sequences' && $passed_qry =~ /sequence_flags/ ) ) {
				print "<fieldset><legend>Delete</legend>\n";
				print $q->start_form;
				$q->param( 'page', 'deleteAll' );
				print $q->hidden($_) foreach qw (db page table query);
				if ( $table eq 'allele_designations' ) {
					print "<ul><li>\n";
					if ( $self->can_modify_table('allele_sequences') ) {
						print $q->checkbox( -name => 'delete_tags', -label => 'Delete corresponding sequence tags' );
						print "</li>\n<li>\n";
					}
					print $q->checkbox( -name => 'delete_pending', -label => 'Delete corresponding pending designations' );
					print "</li></ul>\n";
				}
				print $q->submit( -name => 'Delete ALL', -class => 'submit' );
				print $q->end_form;
				print "</fieldset>";
			}
			if ( $table eq 'sequence_bin' ) {
				my $experiments = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM experiments")->[0];
				if ($experiments) {
					print "<fieldset><legend>Experiments</legend>\n";
					print $q->start_form;
					$q->param( 'page', 'linkToExperiment' );
					foreach (qw (db page query)) {
						print $q->hidden($_);
					}
					print $q->submit( -name => 'Link to experiment', -class => 'submit' );
					print $q->end_form;
					print "</fieldset>";
				}
			}
			if (   $self->{'system'}->{'read_access'} eq 'acl'
				&& $table eq $self->{'system'}->{'view'}
				&& $self->can_modify_table('isolate_user_acl') )
			{
				print "<fieldset><legend>Access control</legend>\n";
				print $q->start_form;
				$q->param( 'page', 'isolateACL' );
				print $q->hidden($_) foreach qw (db page table query);
				print $q->submit( -name => 'Modify access', -class => 'submit' );
				print $q->end_form;
				print "</fieldset>";
			}
			if (
				any { $table eq $_ }
				qw (schemes users user_groups user_group_members user_permissions projects project_members isolate_aliases
				accession experiments experiment_sequences allele_sequences samples loci locus_aliases pcr probes isolate_field_extended_attributes
				isolate_value_extended_attributes scheme_fields scheme_members scheme_groups scheme_group_scheme_members scheme_group_group_members
				locus_descriptions scheme_curators locus_curators sequences sequence_refs profile_refs locus_extended_attributes client_dbases
				client_dbase_loci client_dbase_schemes)
			  )
			{
				print "<fieldset><legend>Database configuration</legend>\n";
				print $q->start_form;
				$q->param( 'page', 'exportConfig' );
				print $q->hidden($_) foreach qw (db page table query);
				print $q->submit( -name => 'Export configuration/data', -class => 'submit' );
				print $q->end_form;
				print "</fieldset>\n";
			}
		}
	} else {
		$logger->debug("Query: $qry");
		print "<p>No records found!</p>\n";
	}
	my $filename = $self->make_temp_file($qry);
	$self->print_results_header_insert($filename);
	if ( $self->{'prefs'}->{'pagebar'} =~ /top/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		print $bar_buffer;
	}
	print "</div>\n";
	return if !$records;
	if ( $table eq $self->{'system'}->{'view'} ) {
		$self->_print_isolate_table( \$qry, $currentpage, $q->param('curate'), $records );
	} elsif ( $table eq 'profiles' ) {
		$self->_print_profile_table( \$qry, $currentpage, $q->param('curate'), $records );
	} elsif ( $table eq 'refs' ) {
		$self->_print_publication_table( \$qry, $currentpage );
	} else {
		$self->_print_record_table( $table, \$qry, $currentpage );
	}
	if (   $self->{'prefs'}->{'displayrecs'}
		&& $self->{'prefs'}->{'pagebar'} =~ /bottom/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		print "<div class=\"box\" id=\"resultsfooter\">$bar_buffer</div>\n";
	}
}

sub clean_locus {
	my ( $self, $locus ) = @_;
	if ( $self->{'system'}->{'locus_superscript_prefix'} eq 'yes' ) {
		$locus =~ s/^([A-Za-z])_/<sup>$1<\/sup>/;
	}
	$locus =~ tr/_/ /;
	return $locus;
}

sub _print_record_table {
	my ( $self, $table, $qryref, $page ) = @_;
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $q        = $self->{'cgi'};
	if ( $table eq $self->{'system'}->{'view'} ) {
		$logger->error("Record table should not be called for isolates");
		return;
	}
	my $qry = $$qryref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @qry_fields, @display,     @cleaned_headers );
	my ( %type,       %foreign_key, %labels );
	my $user_variable_fields = 0;
	if ( $table eq 'allele_sequences' ) {
		push @cleaned_headers, 'isolate id';
	}
	foreach (@$attributes) {
		next if $table eq 'sequence_bin' && $_->{'name'} eq 'sequence';
		next if $_->{'hide'} eq 'yes' || ( $_->{'public_hide'} eq 'yes' && !$self->{'curate'} ) || $_->{'main_display'} eq 'no';
		push @display,    $_->{'name'};
		push @qry_fields, "$table.$_->{'name'}";
		my $cleaned = $_->{'name'};
		$cleaned =~ tr/_/ /;
		if (   $_->{'name'} eq 'isolate_display'
			or $_->{'name'} eq 'main_display'
			or $_->{'name'} eq 'query_field'
			or $_->{'name'} eq 'query_status'
			or $_->{'name'} eq 'dropdown'
			or $_->{'name'} eq 'analysis' )
		{
			$cleaned .= '*';
			$user_variable_fields = 1;
		}
		push @cleaned_headers, $cleaned;
		if ( $table eq 'experiment_sequences' && $_->{'name'} eq 'experiment_id' ) {
			push @cleaned_headers, 'isolate id';
		}
		if ( $table eq 'allele_sequences' && $_->{'name'} eq 'complete' ) {
			push @cleaned_headers, 'flag';
		}
		$type{ $_->{'name'} }        = $_->{'type'};
		$foreign_key{ $_->{'name'} } = $_->{'foreign_key'};
		$labels{ $_->{'name'} }      = $_->{'labels'};
	}
	my $extended_attributes;
	if ( $q->param('page') eq 'alleleQuery' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $locus = $q->param('locus');
		if ( $self->{'datastore'}->is_locus($locus) ) {
			$extended_attributes =
			  $self->{'datastore'}
			  ->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order", $locus );
			if ( ref $extended_attributes eq 'ARRAY' ) {
				foreach (@$extended_attributes) {
					( my $cleaned = $_ ) =~ tr/_/ /;
					push @cleaned_headers, $cleaned;
				}
			}
		}
	}
	$" = ',';
	my $fields = "@qry_fields";
	if ( $table eq 'allele_sequences' && $qry =~ /sequence_flags/ ) {
		$qry =~ s/\*/DISTINCT $fields/;
	} else {
		$qry =~ s/\*/$fields/;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };
	if ($@) {
		$logger->error("Can't execute: $qry $@");
	} else {
		$logger->debug("Query: $qry");
	}
	my @retval = $sql->fetchrow_array;
	if ( !@retval ) {
		return;
	}
	$sql->finish();
	eval { $sql->execute(); };
	$logger->error($@) if $@;
	my %data = ();
	$sql->bind_columns( map { \$data{$_} } @display );    #quicker binding hash to arrayref than to use hashref
	$" = '</th><th>';
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n";
	print "<tr>";

	if ( $self->{'curate'} ) {
		print "<th>Delete</th><th>Update</th>";
	}
	print "<th>@cleaned_headers</th></tr>\n";
	my $td = 1;
	my ( %foreign_key_sql, $fields_to_query );
	while ( $sql->fetchrow_arrayref ) {
		my @query_values;
		my %primary_key;
		$" = "&amp;";
		foreach (@$attributes) {
			if ( $_->{'primary_key'} eq 'yes' ) {
				$primary_key{ $_->{'name'} } = 1;
				my $value = $data{ $_->{'name'} };
				$value =~ s/ /\%20/g;
				$value =~ s/\+/%2B/g;
				push @query_values, "$_->{'name'}=$value";
			}
		}
		print "<tr class=\"td$td\">";
		if ( $self->{'curate'} ) {
			print "<td><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}&amp;page=delete&amp;table=$table&amp;@query_values\">Delete</a></td>";
			if ( $table eq 'allele_sequences' ) {
				print "<td><a href=\"" . $q->script_name . "?db=$self->{'instance'}&amp;page=tagUpdate&amp;@query_values\">Update</a></td>";
			} else {
				print "<td><a href=\""
				  . $q->script_name
				  . "?db=$self->{'instance'}&amp;page=update&amp;table=$table&amp;@query_values\">Update</a></td>";
			}
		}
		foreach my $field (@display) {
			if ( $field eq 'url' ) {
				$data{'url'} =~ s/\&/\&amp;/g;
			}
			if ( $primary_key{$field} && !$self->{'curate'} ) {
				my $value;
				if ( $field eq 'isolate_id' ) {
					$value = $data{ lc($field) } . ') ' . $self->get_isolate_name_from_id( $data{ lc($field) } );
				} else {
					$value = $data{ lc($field) };
				}
				$value = $self->clean_locus($value);
				if ( $table eq 'sequences' ) {
					print
					  "<td><a href=\"$self->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;@query_values\">$value</a></td>";
				} else {
					print
"<td><a href=\"$self->{'script_name'}?db=$self->{'instance'}&amp;page=recordInfo&amp;table=$table&amp;@query_values\">$value</a></td>";
				}
			} elsif ( $type{$field} eq 'bool' ) {
				if ( $data{ lc($field) } eq '' ) {
					print "<td></td>";
				} else {
					my $value = $data{ lc($field) } ? 'true' : 'false';
					print "<td>$value</td>";
				}
				if ( $table eq 'allele_sequences' && $field eq 'complete' ) {
					my $flags =
					  $self->{'datastore'}->get_sequence_flag( $data{'seqbin_id'}, $data{'locus'}, $data{'start_pos'}, $data{'end_pos'} );
					$" = "</a> <a class=\"seqflag_tooltip\">";
					print @$flags ? "<td><a class=\"seqflag_tooltip\">@$flags</a></td>" : "<td />";
					$" = ' ';
				}
			} elsif ( $field =~ /sequence$/ && $field ne 'coding_sequence' ) {
				if ( length( $data{ lc($field) } ) > 60 ) {
					my $seq = BIGSdb::Utils::truncate_seq( \$data{ lc($field) }, 30 );
					print "<td class=\"seq\">$seq</td>";
				} else {
					print "<td class=\"seq\">$data{lc($field)}</td>";
				}
			} elsif ( $field eq 'curator' || $field eq 'sender' ) {
				my $user_info = $self->{'datastore'}->get_user_info( $data{ lc($field) } );
				print "<td>$user_info->{'first_name'} $user_info->{'surname'}</td>";
			} elsif ( $foreign_key{$field} && $labels{$field} ) {
				my @fields_to_query;
				if ( !$foreign_key_sql{$field} ) {
					my @values = split /\|/, $labels{$field};
					foreach (@values) {
						if ( $_ =~ /\$(.*)/ ) {
							push @fields_to_query, $1;
						}
					}
					$fields_to_query->{$field} = \@fields_to_query;
					$" = ',';
					my $qry = "select @fields_to_query from $foreign_key{$field} WHERE id=?";
					$foreign_key_sql{$field} = $self->{'db'}->prepare($qry) or die;
				}
				eval { $foreign_key_sql{$field}->execute( $data{ lc($field) } ); };
				if ($@) {
					$logger->error("Can't execute: $@ value:$data{lc($field)}");
				}
				while ( my @labels = $foreign_key_sql{$field}->fetchrow_array() ) {
					my $value = $labels{$field};
					my $i     = 0;
					foreach ( @{ $fields_to_query->{$field} } ) {
						$value =~ s/$_/$labels[$i]/;
						$i++;
					}
					$value =~ s/[\|\$]//g;
					$value =~ s/\&/\&amp;/g;
					print "<td>$value</td>";
				}
			} else {
				if ( ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) && $field eq 'seqbin_id' ) {
					my ( $isolate_id, $isolate ) = $self->get_isolate_id_and_name_from_seqbin_id( $data{'seqbin_id'} );
					print "<td>$isolate_id) $isolate</td>";
				}
				if ( $field eq 'isolate_id' ) {
					print "<td>$data{'isolate_id'}) " . $self->get_isolate_name_from_id( $data{'isolate_id'} ) . "</td>";
				} else {
					my $value = $data{ lc($field) };
					if ( $field eq 'locus' || ( $table eq 'loci' && $field eq 'id' ) ) {
						$value = $self->clean_locus($value);
					} else {
						$value =~ s/\&/\&amp;/g;
						$value =~ tr/_/ /;
					}
					print "<td>$value</td>";
				}
			}
		}
		if ( $q->param('page') eq 'alleleQuery' && ref $extended_attributes eq 'ARRAY' ) {
			my $ext_sql =
			  $self->{'db'}->prepare("SELECT value FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?");
			foreach (@$extended_attributes) {
				eval { $ext_sql->execute( $data{'locus'}, $_, $data{'allele_id'} ); };
				$logger->error($@) if $@;
				my ($value) = $ext_sql->fetchrow_array;
				print "<td>$value</td>";
			}
		}
		print "</tr>\n";
		$td = $td == 2 ? 1 : 2;
	}
	print "</table></div>";
	if ($user_variable_fields) {
		print "<p class=\"comment\">* Default values are displayed for this field.  These may be overridden by user preference.</p>\n";
	}
	print "</div>\n";
}

sub _print_publication_table {

	#This function requires that datastore->create_temp_ref_table has been
	#run by the calling code.
	my ( $self, $qryref, $page ) = @_;
	my $q        = $self->{'cgi'};
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $qry      = $$qryref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $qry $@");
		return;
	}
	my $buffer;
	my $td = 1;
	while ( my $refdata = $sql->fetchrow_hashref ) {
		my $author_filter = $q->param('author');
		next if ( $author_filter && $author_filter ne 'All authors' && $refdata->{'authors'} !~ /$author_filter/ );
		$buffer .=
"<tr class=\"td$td\"><td><a href='http://www.ncbi.nlm.nih.gov/pubmed/$refdata->{'pmid'}'>$refdata->{'pmid'}</a></td><td>$refdata->{'year'}</td><td style=\"text-align:left\">";
		if ( !$refdata->{'authors'} && !$refdata->{'title'} ) {
			$buffer .= "No details available.</td>\n";
		} else {
			$buffer .= "$refdata->{'authors'} ";
			$buffer .= "($refdata->{'year'}) " if $refdata->{'year'};
			$buffer .= "$refdata->{'journal'} ";
			$buffer .= "<b>$refdata->{'volume'}:</b> "
			  if $refdata->{'volume'};
			$buffer .= " $refdata->{'pages'}</td>\n";
		}
		$buffer .= "<td style=\"text-align:left\">$refdata->{'title'}</td>\n";
		if ( $q->param('calling_page') ne 'browse' && !$q->param('all_records') ) {
			$buffer .= "<td>$refdata->{'isolates'}</td>";
		}
		$buffer .= "<td>" . $self->get_link_button_to_ref( $refdata->{'pmid'} ) . "</td>\n";
		$buffer .= "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		print "<div class=\"box\" id=\"resultstable\">\n";
		print "<table class=\"resultstable\">\n<thead>\n";
		print "<tr><th>PubMed id</th><th>Year</th><th>Citation</th><th>Title</th>";
		print "<th>Isolates in query</th>" if $q->param('calling_page') ne 'browse' && !$q->param('all_records');
		print "<th>Isolates in database</th></tr>\n</thead>\n<tbody>\n";
		print "$buffer";
		print "</tbody></table>\n</div>\n";
	} else {
		print "<div class=\"box\" id=\"resultsheader\"><p>No PubMed records have been linked to isolates.</p></div>\n";
	}
}

sub get_link_button_to_ref {
	my ( $self, $ref ) = @_;
	my $buffer;
	if ( !$self->{'sql'}->{'link_ref'} ) {
		my $qry =
"SELECT COUNT(refs.isolate_id) FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id WHERE pubmed_id=?";
		$self->{'sql'}->{'link_ref'} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'link_ref'}->execute($ref); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my ($count) = $self->{'sql'}->{'link_ref'}->fetchrow_array;
	my $plural = $count == 1 ? '' : 's';
	$buffer .= "$count isolate$plural";
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form;
	$q->param( 'curate', 1 ) if $self->{'curate'};
	$q->param( 'query',
"SELECT * FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id WHERE pubmed_id='$ref' ORDER BY $self->{'system'}->{'view'}.id;"
	);
	$q->param( 'pmid', $ref );
	$q->param( 'page', 'pubquery' );

	foreach (qw (db page query curate pmid)) {
		$buffer .= $q->hidden($_);
	}
	$buffer .= $q->submit( -value => 'Display', -class => 'submit' );
	$buffer .= $q->end_form;
	$q->param( 'page', 'info' );
	return $buffer;
}

sub get_isolate_name_from_id {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'isolate_id'} ) {
		$self->{'sql'}->{'isolate_id'} =
		  $self->{'db'}
		  ->prepare("SELECT $self->{'system'}->{'view'}.$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	eval { $self->{'sql'}->{'isolate_id'}->execute($isolate_id); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my ($isolate) = $self->{'sql'}->{'isolate_id'}->fetchrow_array;
	return $isolate;
}

sub get_isolate_id_and_name_from_seqbin_id {
	my ( $self, $seqbin_id ) = @_;
	if ( !$self->{'sql'}->{'isolate_id_as'} ) {
		$self->{'sql'}->{'isolate_id_as'} =
		  $self->{'db'}->prepare(
"SELECT $self->{'system'}->{'view'}.id,$self->{'system'}->{'view'}.$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} LEFT JOIN sequence_bin ON $self->{'system'}->{'view'}.id = isolate_id WHERE sequence_bin.id=?"
		  );
	}
	eval { $self->{'sql'}->{'isolate_id_as'}->execute($seqbin_id); };
	$logger->error($@) if $@;
	my ( $isolate_id, $isolate ) = $self->{'sql'}->{'isolate_id_as'}->fetchrow_array;
	return ( $isolate_id, $isolate );
}

sub print_results_header_insert {

	#Override in subclass
}

sub get_record_name {
	my ( $self, $table ) = @_;
	my %names = (
		'users'                             => 'user',
		'user_groups'                       => 'user group',
		'user_group_members'                => 'user group member',
		'loci'                              => 'locus',
		'refs'                              => 'PubMed link',
		'allele_designations'               => 'allele designation',
		'pending_allele_designations'       => 'pending allele designation',
		'scheme_members'                    => 'scheme member',
		'schemes'                           => 'scheme',
		'scheme_fields'                     => 'scheme field',
		'composite_fields'                  => 'composite field',
		'composite_field_values'            => 'composite field value',
		'isolates'                          => 'isolate',
		'sequences'                         => 'allele sequence',
		'accession'                         => 'accession number',
		'sequence_refs'                     => 'PubMed link',
		'profiles'                          => 'profile',
		'sequence_bin'                      => 'sequence (contig)',
		'allele_sequences'                  => 'allele sequence tag',
		'isolate_aliases'                   => 'isolate alias',
		'locus_aliases'                     => 'locus alias',
		'user_permissions'                  => 'user permission record',
		'isolate_user_acl'                  => 'isolate access control record',
		'isolate_usergroup_acl'             => 'isolate group access control record',
		'client_dbases'                     => 'client database',
		'client_dbase_loci'                 => 'locus to client database definition',
		'client_dbase_schemes'              => 'scheme to client database definition',
		'locus_extended_attributes'         => 'locus extended attribute',
		'projects'                          => 'project description',
		'project_members'                   => 'project member',
		'profile_refs'                      => 'Pubmed link',
		'samples'                           => 'sample storage record',
		'scheme_curators'                   => 'scheme curator access record',
		'locus_curators'                    => 'locus curator access record',
		'experiments'                       => 'experiment',
		'experiment_sequences'              => 'experiment sequence link',
		'isolate_field_extended_attributes' => 'isolate field extended attribute',
		'isolate_value_extended_attributes' => 'isolate field extended attribute value',
		'locus_descriptions'                => 'locus description',
		'scheme_groups'                     => 'scheme group',
		'scheme_group_scheme_members'       => 'scheme group scheme member',
		'scheme_group_group_members'        => 'scheme group group member',
		'pcr'                               => 'PCR reaction',
		'pcr_locus'                         => 'PCR locus link',
		'probes'                            => 'nucleotide probe',
		'probe_locus'                       => 'probe locus link',
		'client_dbase_loci_fields'          => 'locus to client database isolate field definition'
	);
	return $names{$table};
}

sub rewrite_query_ref_order_by {
	my ( $self, $qry_ref ) = @_;
	my $view = $self->{'system'}->{'view'};
	if ( $$qry_ref =~ /ORDER BY (s_\d+_\S+)\s/ ) {
		my $scheme_id   = $1;
		my $scheme_join = $self->_create_join_sql_for_scheme($scheme_id);
		$$qry_ref =~ s/(SELECT \.* FROM $view)/$1 $scheme_join/;
		$$qry_ref =~ s/FROM $view/FROM $view $scheme_join/;
		$$qry_ref =~ s/ORDER BY s_(\d+)_/ORDER BY ordering\./;
	} elsif ( $$qry_ref =~ /ORDER BY l_(\S+)\s/ ) {
		my $locus      = $1;
		my $locus_join = $self->_create_join_sql_for_locus($locus);
		( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
		$$qry_ref =~ s/(SELECT .* FROM $view)/$1 $locus_join/;
		$$qry_ref =~
s/FROM $view/FROM $view LEFT JOIN allele_designations AS ordering ON ordering.isolate_id=$view.id AND ordering.locus='$cleaned_locus'/;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$$qry_ref =~ s/ORDER BY l_\S+\s/ORDER BY CAST(ordering.allele_id AS int) /;
		} else {
			$$qry_ref =~ s/ORDER BY l_\S+\s/ORDER BY ordering.allele_id /;
		}
	} elsif ( $$qry_ref =~ /ORDER BY f_/ ) {
		$$qry_ref =~ s/ORDER BY f_/ORDER BY $view\./;
	}
}

sub _print_profile_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize  = $self->{'prefs'}->{'displayrecs'};
	my $logger    = get_logger('BIGSdb.Page');
	my $q         = $self->{'cgi'};
	my $qry       = $$qryref;
	my $qry_limit = $qry;
	my $scheme_id;
	if ( $qry =~ /FROM scheme_(\d+)/ || $qry =~ /scheme_id='?(\d+)'?/ ) {
		$scheme_id = $1;
	}
	if ( !$scheme_id ) {
		$logger->error("No scheme id determined.");
		return;
	}
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$logger->debug("Passed query: $qry");
	my ( $sql, $limit_sql );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');
	my $start            = gettimeofday();
	eval { $limit_sql->execute(); };

	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid search performed</p></div>\n";
		$logger->warn("Can't execute query $qry_limit  $@");
		return;
	}
	my $end     = gettimeofday();
	my $elapsed = $end - $start;
	$elapsed =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Time to execute page query : $elapsed seconds");
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};

	if ( !$primary_key ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile browsing can not be done until this has been set.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n<tr>";
	print "<th>Delete</th><th>Update</th>" if $self->{'curate'};
	print "<th>$primary_key</th>";
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		my $cleaned    = $self->clean_locus($_);
		$cleaned .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		print "<th>$cleaned</th>";
	}
	foreach (@$scheme_fields) {
		next if $primary_key eq $_;
		my $cleaned = $_;
		$cleaned =~ tr/_/ /;
		print "<th>$cleaned</th>";
	}
	print "</tr>";
	my $td = 1;

	#Run limited page query for display
	while ( my $data = $limit_sql->fetchrow_hashref() ) {
		my $pk_value     = $data->{ lc($primary_key) };
		my $profcomplete = 1;
		print "<tr class=\"td$td\">";
		if ( $self->{'curate'} ) {
			print "<td><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}&amp;page=delete&amp;table=profiles&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value\">Delete</a></td><td><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}&amp;page=profileUpdate&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value\">Update</a></td>";
			print
"<td><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value&amp;curate=1\">$pk_value</a></td>";
		} else {
			print
"<td><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value\">$pk_value</a></td>";
		}
		foreach (@$loci) {
			( my $cleaned = $_ ) =~ s/'/_PRIME_/g;
			print "<td>$data->{lc($cleaned)}</td>";
		}
		foreach (@$scheme_fields) {
			next if $_ eq $primary_key;
			print "<td>$data->{lc($_)}</td>";
		}
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table></div>\n<p />\n";
	if ( !$self->{'curate'} ) {
		my $plugin_categories = $self->{'pluginManager'}->get_plugin_categories( 'postquery', 'sequences' );
		if (@$plugin_categories) {
			print "<h2>Analysis tools:</h2>\n<table>";
			my $query_temp_file_written = 0;
			my ( $filename, $full_file_path );
			do {
				$filename       = BIGSdb::Utils::get_random() . '.txt';
				$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
			} until ( !-e $full_file_path );
			foreach (@$plugin_categories) {
				my $cat_buffer;
				my $plugin_names = $self->{'pluginManager'}->get_appropriate_plugin_names( 'postquery', 'sequences', $_ || 'none' );
				if (@$plugin_names) {
					my $plugin_buffer;
					if ( !$query_temp_file_written ) {
						open( my $fh, '>', $full_file_path );
						$" = "\n";
						print $fh $$qryref;
						close $fh;
						$query_temp_file_written = 1;
					}
					$q->param( 'calling_page', $q->param('page') );
					foreach (@$plugin_names) {
						my $att = $self->{'pluginManager'}->get_plugin_attributes($_);
						next if $att->{'min'} && $att->{'min'} > $records;
						next if $att->{'max'} && $att->{'max'} < $records;
						$plugin_buffer .= '<td>';
						$plugin_buffer .= $q->start_form;
						$q->param( 'page', 'plugin' );
						$q->param( 'name', $att->{'module'} );
						$plugin_buffer .= $q->hidden($_) foreach qw (db page name calling_page scheme_id);
						$plugin_buffer .= $q->hidden( 'query_file', $filename )
						  if $att->{'input'} eq 'query';
						$plugin_buffer .= $q->submit( -label => ( $att->{'buttontext'} || $att->{'menutext'} ), -class => 'pagebar' );
						$plugin_buffer .= $q->end_form;
						$plugin_buffer .= '</td>';
					}
					if ($plugin_buffer) {
						$_ = 'Miscellaneous' if !$_;
						$cat_buffer .= "<tr><td style=\"text-align:right\">$_: </td><td><table><tr>\n";
						$cat_buffer .= $plugin_buffer;
						$cat_buffer .= "</tr>\n";
					}
				}
				print "$cat_buffer</table></td></tr>\n" if $cat_buffer;
			}
			print "</table>\n";
		}
	}
	print "</div>\n";
	$sql->finish if $sql;
}

sub is_allowed_to_view_isolate {
	my ( $self, $isolate_id ) = @_;
	my $allowed_to_view =
	  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id )->[0];
}

sub _print_isolate_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize  = $self->{'prefs'}->{'displayrecs'};
	my $logger    = get_logger('BIGSdb.Page');
	my $q         = $self->{'cgi'};
	my $qry       = $$qryref;
	my $qry_limit = $qry;
	my $fields    = $self->{'xmlHandler'}->get_field_list();
	my $view      = $self->{'system'}->{'view'};
	$" = ",$view.";
	my $field_string = "$view.@$fields";
	$qry_limit =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;

	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$logger->debug("Passed query: $qry");
	my ( $sql, $limit_sql );
	$self->rewrite_query_ref_order_by( \$qry_limit );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');
	my $start            = gettimeofday();
	eval { $limit_sql->execute(); };

	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid search performed</p></div>\n";
		$logger->warn("Can't execute query $qry_limit  $@");
		return;
	}
	my %data = ();
	$limit_sql->bind_columns( map { \$data{$_} } @$fields );    #quicker binding hash to arrayref than to use hashref
	my $end     = gettimeofday();
	my $elapsed = $end - $start;
	$elapsed =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Time to execute page query : $elapsed seconds");
	my ( %composites, %composite_display_pos );
	$qry = "SELECT id,position_after FROM composite_fields";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };

	if ($@) {
		$logger->error("Can't execute $qry $@");
	} else {
		while ( my @data = $sql->fetchrow_array() ) {
			$composite_display_pos{ $data[0] } = $data[1];
			$composites{ $data[1] }            = 1;
		}
	}
	my $scheme_ids        = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	my $scheme_fields     = $self->{'datastore'}->get_all_scheme_fields;
	my $scheme_field_info = $self->{'datastore'}->get_all_scheme_field_info;
	my $scheme_loci       = $self->{'datastore'}->get_all_scheme_loci;
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n";
	$self->_print_isolate_table_header( \%composites, \%composite_display_pos, $scheme_ids, $scheme_fields, $scheme_loci );
	my $td = 1;
	$" = "=? AND ";
	my %url;

	if ( $self->{'prefs'}->{'hyperlink_loci'} ) {
		my $locus_info_sql = $self->{'db'}->prepare("SELECT id,url FROM loci");
		eval { $locus_info_sql->execute; };
		$logger->error($@) if $@;
		while ( my ( $locus, $url ) = $locus_info_sql->fetchrow_array ) {
			if ( $self->{'prefs'}->{'main_display_loci'}->{$locus} ) {
				( $url{$locus} ) = $url;
				$url{$locus} =~ s/\&/\&amp;/g;
			}
		}
	}
	my $schemes;
	foreach (@$scheme_ids) {
		if (   ref $scheme_fields->{$_} eq 'ARRAY'
			&& @{ $scheme_fields->{$_} }
			&& ref $scheme_loci->{$_} eq 'ARRAY'
			&& @{ $scheme_loci->{$_} }
			&& $self->{'prefs'}->{"main_display_schemes"}->{$_} )
		{
			$schemes->{$_} = $self->{'datastore'}->get_scheme($_);
		}
	}
	$scheme_loci->{0} = $self->{'datastore'}->get_loci_in_no_scheme;
	my $field_attributes;
	$field_attributes->{$_} = $self->{'xmlHandler'}->get_field_attributes($_) foreach (@$fields);
	my $extended = $self->get_extended_attributes;
	my $attribute_sql =
	  $self->{'db'}->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");
	while ( $limit_sql->fetchrow_arrayref() ) {
		my ( $allele_sequences, $allele_sequence_flags );
		if ( $self->{'prefs'}->{'sequence_details_main'} ) {
			$allele_sequences      = $self->{'datastore'}->get_all_allele_sequences( $data{'id'} );
			$allele_sequence_flags = $self->{'datastore'}->get_all_sequence_flags( $data{'id'} );
		}
		my $profcomplete = 1;
		my $id;
		print "<tr class=\"td$td\">";
		foreach my $thisfieldname (@$fields) {
			$data{$thisfieldname} =~ s/\n/ /g;
			if (   $self->{'prefs'}->{'maindisplayfields'}->{$thisfieldname}
				|| $thisfieldname eq 'id' )
			{
				if ( $thisfieldname eq 'id' ) {
					$id = $data{$thisfieldname};
					$id =~ s/ /\%20/g;
					$id =~ s/\+/\%2B/g;
					if ( $self->{'curate'} ) {
						print "<td><a href=\""
						  . $q->script_name
						  . "?db=$self->{'instance'}&amp;page=isolateDelete&amp;id=$id\">Delete</a></td><td><a href=\""
						  . $q->script_name
						  . "?db=$self->{'instance'}&amp;page=isolateUpdate&amp;id=$id\">Update</a></td>";
						if ( $self->{'system'}->{'read_access'} eq 'acl' && $self->{'permissions'}->{'modify_isolates_acl'} ) {
							print "<td><a href=\""
							  . $q->script_name
							  . "?db=$self->{'instance'}&amp;page=isolateACL&amp;id=$id\">Modify</a></td>";
						}
					}
					print
"<td><a href=\"$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'}&amp;id=$id\">$data{$thisfieldname}</a></td>";
				} elsif ( $data{$thisfieldname} eq '-999'
					|| $data{$thisfieldname} eq '0001-01-01' )
				{
					print "<td>.</td>";
				} elsif (
					$thisfieldname eq 'sender'
					|| $thisfieldname eq 'curator'
					|| (   $field_attributes->{'thisfieldname'}{'userfield'}
						&& $field_attributes->{'thisfieldname'}{'userfield'} eq 'yes' )
				  )
				{
					my $user_info = $self->{'datastore'}->get_user_info( $data{$thisfieldname} );
					print "<td>$user_info->{'first_name'} $user_info->{'surname'}</td>";
				} else {
					print "<td>$data{$thisfieldname}</td>";
				}
			}
			my $extatt = $extended->{$thisfieldname};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					if ( $self->{'prefs'}->{'maindisplayfields'}->{"$thisfieldname\..$extended_attribute"} ) {
						eval { $attribute_sql->execute( $thisfieldname, $extended_attribute, $data{$thisfieldname} ); };
						$logger->error($@) if $@;
						my ($value) = $attribute_sql->fetchrow_array;
						print "<td>$value</td>";
					}
				}
			}
			if ( $composites{$thisfieldname} ) {
				foreach ( keys %composite_display_pos ) {
					next if $composite_display_pos{$_} ne $thisfieldname;
					if ( $self->{'prefs'}->{'maindisplayfields'}->{$_} ) {
						my $value = $self->{'datastore'}->get_composite_value( $id, $_, \%data );
						print "<td>$value</td>";
					}
				}
			}
			if ( $thisfieldname eq $self->{'system'}->{'labelfield'} && $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
				my $aliases =
				  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias", $id );
				$" = '; ';
				print "<td>@$aliases</td>";
			}
		}

		#Print loci and scheme fields
		my $alleles = $self->{'datastore'}->get_all_allele_designations($id);
		foreach my $scheme_id ( @$scheme_ids, 0 ) {
			next
			  if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id} && $scheme_id;
			my @profile;
			foreach ( @{ $scheme_loci->{$scheme_id} } ) {
				next if !$self->{'prefs'}->{'main_display_loci'}->{$_} && ( !$scheme_id || !@{ $scheme_fields->{$scheme_id} } );
				if ( $self->{'prefs'}->{'main_display_loci'}->{$_} ) {
					print "<td>";
					print "<span class=\"provisional\">"
					  if $alleles->{$_}->{'status'} eq 'provisional'
						  && $self->{'prefs'}->{'mark_provisional_main'};
					if ( $self->{'prefs'}->{'hyperlink_loci'} ) {
						my $url = $url{$_};
						$url =~ s/\[\?\]/$alleles->{$_}->{'allele_id'}/g;
						print $url ? "<a href=\"$url\">$alleles->{$_}->{'allele_id'}</a>" : "$alleles->{$_}->{'allele_id'}";
					} else {
						print "$alleles->{$_}->{'allele_id'}";
					}
					print "</span>"
					  if $alleles->{$_}->{'status'} eq 'provisional'
						  && $self->{'prefs'}->{'mark_provisional_main'};
					if ( $self->{'prefs'}->{'sequence_details_main'} && keys %{ $allele_sequences->{$_} } > 0 ) {
						my @seqs;
						my @flags;
						my %flags_used;
						my $complete;
						foreach my $seqbin_id ( keys %{ $allele_sequences->{$_} } ) {
							foreach my $start ( keys %{ $allele_sequences->{$_}->{$seqbin_id} } ) {
								foreach my $end ( keys %{ $allele_sequences->{$_}->{$seqbin_id}->{$start} } ) {
									push @seqs, $allele_sequences->{$_}->{$seqbin_id}->{$start}->{$end};
									$complete = 1 if $allele_sequences->{$_}->{$seqbin_id}->{$start}->{$end}->{'complete'};
									my @flag_list = keys %{ $allele_sequence_flags->{$_}->{$seqbin_id}->{$start}->{$end} };
									push @flags, \@flag_list;
									foreach (@flag_list) {
										$flags_used{$_} = 1;
									}
								}
							}
						}
						my $cleaned_locus    = $self->clean_locus($_);
						my $sequence_tooltip = $self->get_sequence_details_tooltip( $cleaned_locus, $alleles->{$_}, \@seqs, \@flags );
						my $sequence_class   = $complete ? 'sequence_tooltip' : 'sequence_tooltip_incomplete';
						print
"<span style=\"font-size:0.2em\"> </span><a class=\"$sequence_class\" title=\"$sequence_tooltip\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleSequence&amp;id=$data{'id'}&amp;locus=$_\">&nbsp;S&nbsp;</a>";
						if ( keys %flags_used ) {
							foreach my $flag ( sort keys %flags_used ) {
								print "<a class=\"seqflag_tooltip\">$flag</a>";
							}
						}
					}
					$self->_print_pending_tooltip( $id, $_ )
					  if $self->{'prefs'}->{'display_pending_main'} && defined $alleles->{$_}->{'allele_id'};
					my $action = exists $alleles->{$_}->{'allele_id'} ? 'update' : 'add';
					print
" <a href=\"$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;isolate_id=$id&amp;locus=$_\" class=\"update\">$action</a>"
					  if $self->{'curate'};
					print "</td>";
				}
				push @profile, $alleles->{$_}->{'allele_id'} if $scheme_id;
			}
			next
			  if !$scheme_id
				  || !( ref $scheme_fields->{$scheme_id} eq 'ARRAY' && @{ $scheme_fields->{$scheme_id} } )
				  || !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
			my $values;
			if (@profile) {
				try {
					$values = $schemes->{$scheme_id}->get_field_values_by_profile( \@profile, { 'return_hashref' => 1 } );
				}
				catch BIGSdb::DatabaseConfigurationException with {
					$logger->warn("Scheme database is not configured correctly");
				};
			}
			foreach ( @{ $scheme_fields->{$scheme_id} } ) {
				if ( $self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$_} ) {
					if ( ref $values eq 'HASH' ) {
						my $url;
						if (   $self->{'prefs'}->{'hyperlink_loci'}
							&& $scheme_field_info->{$scheme_id}->{$_}->{'url'} )
						{
							$url = $scheme_field_info->{$scheme_id}->{$_}->{'url'};
							$url =~ s/\[\?\]/$values->{lc($_)}/g;
							$url =~ s/\&/\&amp;/g;
						}
						if ( $values->{ lc($_) } eq '-999' ) {
							$values->{ lc($_) } = '';
						}
						if ($url) {
							print "<td><a href=\"$url\">$values->{lc($_)}</a></td>";
						} else {
							print "<td>$values->{lc($_)}</td>";
						}
					} else {
						print "<td />";
					}
				}
			}
		}
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table></div>\n";
	if ( !$self->{'curate'} ) {
		my $plugin_categories = $self->{'pluginManager'}->get_plugin_categories( 'postquery', 'isolates' );
		if (@$plugin_categories) {
			print "<p />\n<h2>Analysis tools:</h2>\n<table>";
			my $query_temp_file_written = 0;
			my ( $filename, $full_file_path );
			do {
				$filename       = BIGSdb::Utils::get_random() . '.txt';
				$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
			} until ( !-e $full_file_path );
			foreach (@$plugin_categories) {
				my $cat_buffer;
				my $plugin_names = $self->{'pluginManager'}->get_appropriate_plugin_names( 'postquery', 'isolates', $_ || 'none' );
				if (@$plugin_names) {
					my $plugin_buffer;
					if ( !$query_temp_file_written ) {
						open( my $fh, '>', $full_file_path );
						$" = "\n";
						print $fh $$qryref;
						close $fh;
						$query_temp_file_written = 1;
					}
					$q->param( 'calling_page', $q->param('page') );
					foreach (@$plugin_names) {
						my $att = $self->{'pluginManager'}->get_plugin_attributes($_);
						next if $att->{'min'} && $att->{'min'} > $records;
						next if $att->{'max'} && $att->{'max'} < $records;
						$plugin_buffer .= '<td>';
						$plugin_buffer .= $q->start_form;
						$q->param( 'page', 'plugin' );
						$q->param( 'name', $att->{'module'} );
						$plugin_buffer .= $q->hidden($_) foreach qw (db page name calling_page);
						$plugin_buffer .= $q->hidden( 'query_file', $filename )
						  if $att->{'input'} eq 'query';
						$plugin_buffer .= $q->submit( -label => ( $att->{'buttontext'} || $att->{'menutext'} ), -class => 'pagebar' );
						$plugin_buffer .= $q->end_form;
						$plugin_buffer .= '</td>';
					}
					if ($plugin_buffer) {
						$_ = 'Miscellaneous' if !$_;
						$cat_buffer .= "<tr><td style=\"text-align:right\">$_: </td><td><table><tr>\n";
						$cat_buffer .= $plugin_buffer;
						$cat_buffer .= "</tr>\n";
					}
				}
				print "$cat_buffer</table></td></tr>\n" if $cat_buffer;
			}
			print "</table>\n";
		}
	}
	print "</div>\n";
	$sql->finish if $sql;
}

sub _print_pending_tooltip {
	my ( $self, $id, $locus ) = @_;
	my $pending = $self->{'datastore'}->get_pending_allele_designations( $id, $locus );
	if (@$pending) {
		my $pending_buffer = 'pending designations - ';
		foreach (@$pending) {
			my $sender = $self->{'datastore'}->get_user_info( $_->{'sender'} );
			$pending_buffer .= "allele: $_->{'allele_id'} ";
			$pending_buffer .= "($_->{'comments'}) "
			  if $_->{'comments'};
			$pending_buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $_->{'method'}; $_->{'datestamp'}]<br />";
		}
		print " <a class=\"pending_tooltip\" title=\"$pending_buffer\">pending</a>";
	}
}

sub _create_join_sql_for_scheme {
	my ( $self, $field ) = @_;
	my $qry;
	if ( $field =~ /s_(\d+)_([^\s;]*)/ ) {
		my $scheme_id    = $1;
		my $scheme_field = $2;
		my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach (@$loci) {
			$qry .= " LEFT JOIN allele_designations AS l_$_ ON l_$_\.isolate_id=$self->{'system'}->{'view'}.id AND l_$_.locus='$_'";
		}
		$qry .= " LEFT JOIN temp_scheme_$scheme_id AS ordering ON";
		my $first = 1;
		foreach (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			$qry .= " AND" if !$first;
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				$qry .= " CAST(l_$_.allele_id AS integer)=ordering.$_";
			} else {
				$qry .= " l_$_.allele_id=ordering.$_";
			}
			$first = 0;
		}
	}
	return $qry;
}

sub _create_join_sql_for_locus {
	my ( $self, $locus ) = @_;
	( my $clean_locus_name = $locus ) =~ s/'/_PRIME_/g;
	$clean_locus_name =~ s/-/_/g;
	( my $escaped_locus = $locus ) =~ s/'/\\'/g;
	my $qry =
" LEFT JOIN allele_designations AS l_$clean_locus_name ON l_$clean_locus_name\.isolate_id=$self->{'system'}->{'view'}.id AND l_$clean_locus_name.locus='$escaped_locus'";
	return $qry;
}

sub _print_isolate_table_header {
	my ( $self, $composites, $composite_display_pos, $scheme_ids, $scheme_fields, $scheme_loci ) = @_;
	my @selectitems   = $self->{'xmlHandler'}->get_select_items('userFieldIdsOnly');
	my $header_buffer = "<tr>";
	my $col_count;
	my $extended = $self->get_extended_attributes;
	foreach my $col (@selectitems) {
		if (   $self->{'prefs'}->{'maindisplayfields'}->{$col}
			|| $col eq 'id' )
		{
			$col =~ tr/_/ /;
			$header_buffer .= "<th>$col</th>";
			$col_count++;
		}
		if ( $composites->{$col} ) {
			foreach ( keys %$composite_display_pos ) {
				next if $composite_display_pos->{$_} ne $col;
				if ( $self->{'prefs'}->{'maindisplayfields'}->{$_} ) {
					my $displayfield = $_;
					$displayfield =~ tr/_/ /;
					$header_buffer .= "<th>$displayfield</th>";
					$col_count++;
				}
			}
		}
		if ( $col eq $self->{'system'}->{'labelfield'} && $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
			$header_buffer .= "<th>aliases</th>";
			$col_count++;
		}
		my $extatt = $extended->{$col};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'maindisplayfields'}->{"$col\..$extended_attribute"} ) {
					$header_buffer .= "<th>$col\..$extended_attribute</th>";
					$col_count++;
				}
			}
		}
	}
	my $fieldtype_header = "<tr>";
	if ( $self->{'curate'} ) {
		$fieldtype_header .= "<th rowspan=\"2\">Delete</th><th rowspan=\"2\">Update</th>";
		if ( $self->{'system'}->{'read_access'} eq 'acl' && $self->{'permissions'}->{'modify_isolates_acl'} ) {
			$fieldtype_header .= "<th rowspan=\"2\">Access control</th>";
		}
	}
	$fieldtype_header .= "<th colspan=\"$col_count\">Isolate fields";
	$fieldtype_header .=
" <a class=\"tooltip\" title=\"Isolate fields - You can select the isolate fields that are displayed here by going to the options page.\">&nbsp;<i>i</i>&nbsp;</a>";
	$fieldtype_header .= "</th>";
	my $alias_sql = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=?");
	my $qry       = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
	my $cn_sql    = $self->{'db'}->prepare($qry);
	eval { $cn_sql->execute; };
	$logger->error($@) if $@;
	my $common_names = $cn_sql->fetchall_hashref('id');
	$" = '; ';
	my $scheme_info = $self->{'datastore'}->get_all_scheme_info;

	foreach my $scheme_id (@$scheme_ids) {
		next if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
		my @scheme_header;
		if ( ref $scheme_loci->{$scheme_id} eq 'ARRAY' ) {
			foreach ( @{ $scheme_loci->{$scheme_id} } ) {
				if ( $self->{'prefs'}->{'main_display_loci'}->{$_} ) {
					my $locus_header = $self->clean_locus($_);
					my @aliases;
					push @aliases, $common_names->{$_}->{'common_name'} if $common_names->{$_}->{'common_name'};
					if ( $self->{'prefs'}->{'locus_alias'} ) {
						eval { $alias_sql->execute($_); };
						if ($@) {
							$logger->error("Can't execute alias check $@");
						} else {
							while ( my ($alias) = $alias_sql->fetchrow_array ) {
								push @aliases, $alias;
							}
						}
						$" = ', ';
						$locus_header .= " <span class=\"comment\">(@aliases)</span>" if @aliases;
					}
					push @scheme_header, $locus_header;
				}
			}
		}
		if ( ref $scheme_fields->{$scheme_id} eq 'ARRAY' ) {
			foreach ( @{ $scheme_fields->{$scheme_id} } ) {
				if ( $self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$_} ) {
					my $field = $_;
					$field =~ tr/_/ /;
					push @scheme_header, $field;
				}
			}
		}
		if ( scalar @scheme_header ) {
			$fieldtype_header .= "<th colspan=\"" . scalar @scheme_header . "\">$scheme_info->{$scheme_id}->{'description'}</th>";
		}
		$" = '</th><th>';
		$header_buffer .= "<th>@scheme_header</th>" if @scheme_header;
	}
	my @locus_header;
	my $loci = $self->{'datastore'}->get_loci_in_no_scheme();
	foreach (@$loci) {
		if ( $self->{'prefs'}->{'main_display_loci'}->{$_} ) {
			my @aliases;
			if ( $self->{'prefs'}->{'locus_alias'} ) {
				eval { $alias_sql->execute($_); };
				if ($@) {
					$logger->error("Can't execute alias check $@");
				} else {
					while ( my ($alias) = $alias_sql->fetchrow_array ) {
						$alias = $self->clean_locus($alias);
						push @aliases, $alias;
					}
				}
			}
			my $cleaned_locus = $self->clean_locus($_);
			$" = ', ';
			push @locus_header, "$cleaned_locus" . ( @aliases ? " <span class=\"comment\">(@aliases)</span>" : '' );
		}
	}
	if ( scalar @locus_header ) {
		$fieldtype_header .= "<th colspan=\"" . scalar @locus_header . "\">Loci</th>";
	}
	$" = '</th><th>';
	$header_buffer .= "<th>@locus_header</th>" if @locus_header;
	$fieldtype_header .= "</tr>\n";
	$header_buffer    .= "</tr>\n";
	print $fieldtype_header;
	print $header_buffer;
}

sub get_update_details_tooltip {
	my ( $self, $locus, $allele_ref ) = @_;
	my $buffer;
	my $sender  = $self->{'datastore'}->get_user_info( $allele_ref->{'sender'} );
	my $curator = $self->{'datastore'}->get_user_info( $allele_ref->{'curator'} );
	$buffer = "$locus:$allele_ref->{'allele_id'} - ";
	$buffer .= "sender: $sender->{'first_name'} $sender->{'surname'}<br />";
	$buffer .= "status: $allele_ref->{'status'}<br />";
	$buffer .= "method: $allele_ref->{'method'}<br />";
	$buffer .= "curator: $curator->{'first_name'} $curator->{'surname'}<br />";
	$buffer .= "first entered: $allele_ref->{'date_entered'}<br />";
	$buffer .= "last updated: $allele_ref->{'datestamp'}<br />";
	$buffer .= "comments: $allele_ref->{'comments'}<br />"
	  if $allele_ref->{'comments'};
	return $buffer;
}

sub get_sequence_details_tooltip {
	my ( $self, $locus, $allele_ref, $alleleseq_ref, $flags_ref ) = @_;
	my $buffer = "$locus:$allele_ref->{'allele_id'} - ";
	my $i      = 0;
	$" = '; ';
	foreach (@$alleleseq_ref) {
		$buffer .= '<br />' if $i;
		$buffer .= "Seqbin id:$_->{'seqbin_id'}:  
	$_->{'start_pos'} &rarr; $_->{'end_pos'}";
		$buffer .= " (reverse)"  if $_->{'reverse'};
		$buffer .= " incomplete" if !$_->{'complete'};
		if ( ref $flags_ref->[$i] eq 'ARRAY' ) {
			my @flags = sort @{ $flags_ref->[$i] };
			$buffer .= "<br />@flags" if @flags;
		}
		$i++;
	}
	return $buffer;
}

sub make_temp_file {
	my ( $self, @list ) = @_;
	my ( $filename, $full_file_path );
	do {
		$filename       = BIGSdb::Utils::get_random() . '.txt';
		$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	} until ( !-e $full_file_path );
	open( my $fh, '>', $full_file_path );
	$" = "\n";
	print $fh "@list";
	close $fh;
	return $filename;
}

sub run_blast {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';

	#Options are locus, seq_ref, qry_type, num_results, alignment, cache, job
	#if parameter cache=1, the previously generated FASTA database will be used.
	#The calling function should clean up the temporary files.
	my $locus_info = $self->{'datastore'}->get_locus_info( $options->{'locus'} );
	my $already_generated = $options->{'job'} ? 1 : 0;
	$options->{'job'} = &BIGSdb::Utils::get_random if !$options->{'job'};
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}\_outfile.txt";
	my $outfile_url  = "$options->{'job'}\_outfile.txt";

	#create fasta index
	my @runs;
	if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_(\d+)/ ) {
		if ( $options->{'locus'} =~ /^((?:(?!\.\.).)*)$/ ) {    #untaint - check for directory traversal
			$options->{'locus'} = $1;
		}
		@runs = ( $options->{'locus'} );
	} else {
		@runs = qw (DNA peptide);
	}
	my @files_to_delete;
	foreach my $run (@runs) {
		my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}\_$run\_fastafile.txt";
		push @files_to_delete, $temp_fastafile;
		if ( !$already_generated ) {
			my ( $qry, $sql );
			if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_(\d+)/ ) {
				$qry = "SELECT locus,allele_id,sequence from sequences WHERE locus=?";
			} else {
				if ( $options->{'locus'} =~ /SCHEME_(\d+)/ ) {
					my $scheme_id = $1;
					$qry =
"SELECT locus,allele_id,sequence FROM sequences WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$scheme_id) AND locus IN (SELECT id FROM loci WHERE data_type=?)";
				} else {
					$qry = "SELECT locus,allele_id,sequence FROM sequences WHERE locus IN (SELECT id FROM loci WHERE data_type=?)";
				}
			}
			$sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute($run); };
			$logger->error($@) if $@;
			open( my $fasta_fh, '>', $temp_fastafile );
			my $seqs_ref = $sql->fetchall_arrayref;
			foreach (@$seqs_ref) {
				my ( $returned_locus, $id, $seq ) = @$_;
				next if !length $seq;
				print $fasta_fh ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_(\d+)/ )
				  ? ">$id\n$seq\n"
				  : ">$returned_locus:$id\n$seq\n";
			}
			close $fasta_fh;
			if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_(\d+)/ ) {
				if ( $locus_info->{'data_type'} eq 'DNA' ) {
					system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
				} else {
					system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p T -o T");
				}
			} else {
				if ( $run eq 'DNA' ) {
					system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
				} else {
					system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p T -o T");
				}
			}
		}

		#create query fasta file
		open( my $infile_fh, '>', $temp_infile );
		print $infile_fh ">Query\n";
		print $infile_fh "${$options->{'seq_ref'}}\n";
		close $infile_fh;
		my $program;
		if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_(\d+)/ ) {
			if ( $options->{'qry_type'} eq 'DNA' ) {
				$program = $locus_info->{'data_type'} eq 'DNA' ? 'blastn' : 'blastx';
			} else {
				$program = $locus_info->{'data_type'} eq 'DNA' ? 'tblastn' : 'blastp';
			}
		} else {
			if ( $run eq 'DNA' ) {
				$program = $options->{'qry_type'} eq 'DNA' ? 'blastn' : 'tblastn';
			} else {
				$program = $options->{'qry_type'} eq 'DNA' ? 'blastx' : 'blastp';
			}
		}
		if ( $options->{'alignment'} ) {
			system(
"$self->{'config'}->{'blast_path'}/blastall -v $options->{'num_results'} -b $options->{'num_results'} -p $program -d $temp_fastafile -i $temp_infile -o $temp_outfile -F F 2> /dev/null"
			);
		} else {
			system(
"$self->{'config'}->{'blast_path'}/blastall -v $options->{'num_results'} -b $options->{'num_results'} -p $program -d $temp_fastafile -i $temp_infile -o $temp_outfile -m9 -F F 2> /dev/null"
			);
		}
		if ( $run eq 'DNA' ) {
			system "mv $temp_outfile $temp_outfile\.1";
		}
	}
	if ( !$options->{'locus'} || $options->{'locus'} =~ /SCHEME_(\d+)/ ) {
		system "cat $temp_outfile\.1 >> $temp_outfile";
		system "rm $temp_outfile\.1";
	}

	#delete all working files
	$" = ' ';
	system "rm -f $temp_infile @files_to_delete" if !$options->{'cache'};
	return ( $outfile_url, $options->{'job'} );
}

sub is_admin {
	my ($self) = @_;
	if ( $self->{'username'} ) {
		my $qry = "SELECT status FROM users WHERE user_name=?";
		my $status = $self->{'datastore'}->run_simple_query( $qry, $self->{'username'} );
		return 0 if ref $status ne 'ARRAY';
		return 1 if $status->[0] eq 'admin';
	}
	$logger->debug("User $self->{'username'} is not an admin");
	return 0;
}

sub can_modify_table {
	my ( $self, $table ) = @_;
	my $scheme_id = $self->{'cgi'}->param('scheme_id');
	my $locus     = $self->{'cgi'}->param('locus');
	return 1 if $self->is_admin;
	if ( $table eq 'users' && $self->{'permissions'}->{'modify_users'} ) {
		return 1;
	} elsif ( ( $table eq 'user_groups' || $table eq 'user_group_members' ) && $self->{'permissions'}->{'modify_usergroups'} ) {
		return 1;
	} elsif ( ( $table eq 'isolates' || $table eq $self->{'system'}->{'view'} || $table eq 'isolate_aliases' || $table eq 'refs' )
		&& $self->{'permissions'}->{'modify_isolates'} )
	{
		return 1;
	} elsif ( ( $table eq 'isolate_user_acl' || $table eq 'isolate_usergroup_acl' ) && $self->{'permissions'}->{'modify_isolates_acl'} ) {
		return 1;
	} elsif ( ( $table eq 'allele_designations' || $table eq 'pending_allele_designations' )
		&& $self->{'permissions'}->{'designate_alleles'} )
	{
		return 1;
	} elsif (
		(
			$self->{'system'}->{'dbtype'} eq 'isolates' && (
				any {
					$table eq $_;
				}
				qw (sequence_bin accession experiments experiment_sequences )
			)
		)
		&& $self->{'permissions'}->{'modify_sequences'}
	  )
	{
		return 1;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'sequences' || $table eq 'locus_descriptions' ) ) {
		if ( !$locus ) {
			return 1;
		} else {
			my $allowed =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT COUNT(*) FROM locus_curators WHERE locus=? AND curator_id=?", $locus, $self->get_curator_id )
			  ->[0];
			return $allowed;
		}
	} elsif ( $table eq 'allele_sequences' && $self->{'permissions'}->{'tag_sequences'} ) {
		return 1;
	} elsif ( $table eq 'profile_refs' ) {
		my $allowed =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM scheme_curators WHERE curator_id=?", $self->get_curator_id )->[0];
		return $allowed;
	} elsif ( ( $table eq 'profiles' || $table eq 'profile_fields' || $table eq 'profile_members' ) ) {
		return 0 if !$scheme_id;
		my $allowed =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT COUNT(*) FROM scheme_curators WHERE scheme_id=? AND curator_id=?", $scheme_id, $self->get_curator_id )
		  ->[0];
		return $allowed;
	} elsif (
		(
			any {
				$table eq $_;
			}
			qw (loci locus_aliases client_dbases client_dbase_loci client_dbase_schemes locus_client_display_fields
			locus_extended_attributes locus_curators)
		)
		&& $self->{'permissions'}->{'modify_loci'}
	  )
	{
		return 1;
	} elsif ( ( $table eq 'composite_fields' || $table eq 'composite_field_values' ) && $self->{'permissions'}->{'modify_composites'} ) {
		return 1;
	} elsif ( ( $table eq 'schemes' || $table eq 'scheme_members' || $table eq 'scheme_fields' || $table eq 'scheme_curators' )
		&& $self->{'permissions'}->{'modify_schemes'} )
	{
		return 1;
	} elsif ( $table eq 'user_permissions' && $self->{'permissions'}->{'set_user_permissions'} ) {
		return 1;
	} elsif ( ( $table eq 'projects' || $table eq 'project_members' ) && $self->{'permissions'}->{'modify_projects'} ) {
		return 1;
	} elsif ( $table eq 'samples' && $self->{'permissions'}->{'sample_management'} && @{ $self->{'xmlHandler'}->get_sample_field_list } ) {
		return 1;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'sequence_refs' || $table eq 'accession' ) ) {
		my $allowed =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM locus_curators WHERE curator_id=?", $self->get_curator_id )->[0];
		return $allowed;
	} elsif ( $table eq 'isolate_field_extended_attributes' && $self->{'permissions'}->{'modify_field_attributes'} ) {
		return 1;
	} elsif ( $table eq 'isolate_value_extended_attributes' && $self->{'permissions'}->{'modify_value_attributes'} ) {
		return 1;
	} elsif (
		(
			any {
				$table eq $_;
			}
			qw (pcr pcr_locus probes probe_locus)
		)
		&& $self->{'permissions'}->{'modify_probes'}
	  )
	{
		return 1;
	}
	return 0;
}

sub print_warning_sign {
	my ($self) = @_;
	my $image = "$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/images/warning_sign.gif";
	if ( -e $image ) {
		print
"<div style=\"text-align:center\"><img src=\"$self->{'system'}->{'webroot'}/images/warning_sign.gif\" alt=\"Warning!\" /></div>\n";
	} else {
		my $image = "$ENV{'DOCUMENT_ROOT'}/images/warning_sign.gif";
		if ( -e $image ) {
			print "<div style=\"text-align:center\"><img src=\"/images/warning_sign.gif\" alt=\"Access Denied!\" /></div>\n";
		}
	}
}

sub get_curator_id {
	my ($self) = @_;
	if ( $self->{'username'} ) {
		my $qry = "SELECT id,status FROM users WHERE user_name=?";
		my $values = $self->{'datastore'}->run_simple_query( $qry, $self->{'username'} );
		return 0 if ref $values ne 'ARRAY';
		if (   $values->[1]
			&& $values->[1] ne 'curator'
			&& $values->[1] ne 'admin' )
		{
			return 0;
		}
		return $values->[0];
	} else {
		return 0;
	}
}

sub initiate_prefs {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $logger = get_logger('BIGSdb.Application_Initiate');
	return if !$self->{'prefstore'};
	my ( $general_prefs, $field_prefs, $scheme_field_prefs );
	if (   $q->param('page')
		&& $q->param('page') eq 'options'
		&& $q->param('set') )
	{
		foreach (qw(displayrecs pagebar alignwidth flanking)) {
			$self->{'prefs'}->{$_} = $q->param($_);
		}

		#Switches
		foreach (qw (hyperlink_loci traceview tooltips)) {
			$self->{'prefs'}->{$_} = ( $q->param($_) && $q->param($_) eq 'on' ) ? 1 : 0;
		}
		$self->{'prefs'}->{'dropdownfields'}->{'publications'} = $q->param("dropfield_publications") eq 'checked' ? 1 : 0;
	} else {
		return if !$self->{'pref_requirements'}->{'general'} && !$self->{'pref_requirements'}->{'query_field'};
		my $guid = $self->get_guid || 1;
		try {
			$self->{'prefstore'}->update_datestamp($guid);
		}
		catch BIGSdb::PrefstoreConfigurationException with {
			undef $self->{'prefstore'};
			$self->{'fatal'} = 'prefstoreConfig';
		};
		return if !$self->{'prefstore'};
		my $dbname = $self->{'system'}->{'db'};
		$field_prefs = $self->{'prefstore'}->get_all_field_prefs( $guid, $dbname );
		$scheme_field_prefs = $self->{'prefstore'}->get_all_scheme_field_prefs( $guid, $dbname );
		if ( $self->{'pref_requirements'}->{'general'} ) {
			$general_prefs = $self->{'prefstore'}->get_all_general_prefs( $guid, $dbname );
			$self->{'prefs'}->{'displayrecs'} = $general_prefs->{'displayrecs'} || 25;
			$self->{'prefs'}->{'pagebar'}     = $general_prefs->{'pagebar'}     || 'top and bottom';
			$self->{'prefs'}->{'alignwidth'}  = $general_prefs->{'alignwidth'}  || 100;
			$self->{'prefs'}->{'flanking'}    = $general_prefs->{'flanking'}    || 100;

			#default off
			foreach (qw (hyperlink_loci )) {
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'on' ? 1 : 0;
			}

			#default on
			foreach (qw (tooltips traceview)) {
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'off' ? 0 : 1;
			}
		}
		if ( $self->{'pref_requirements'}->{'query_field'} ) {
			if ( defined $field_prefs->{'publications'}->{'dropdown'} ) {
				$self->{'prefs'}->{'dropdownfields'}->{'publications'} = $field_prefs->{'publications'}->{'dropdown'} ? 1 : 0;
			} else {
				$self->{'prefs'}->{'dropdownfields'}->{'publications'} = 1;
			}
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_initiate_isolatedb_prefs( $general_prefs, $field_prefs, $scheme_field_prefs );
	}

	#Set dropdown status for scheme fields
	if ( $self->{'pref_requirements'}->{'query_field'} ) {
		my $guid                       = $self->get_guid || 1;
		my $dbname                     = $self->{'system'}->{'db'};
		my $scheme_ids                 = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		my $scheme_fields              = $self->{'datastore'}->get_all_scheme_fields;
		my $scheme_field_default_prefs = $self->{'datastore'}->get_all_scheme_field_info;
		foreach my $scheme_id (@$scheme_ids) {
			foreach ( @{ $scheme_fields->{$scheme_id} } ) {
				foreach my $action (qw(dropdown)) {
					if ( defined $scheme_field_prefs->{$scheme_id}->{$_}->{$action} ) {
						$self->{'prefs'}->{"$action\_scheme_fields"}->{$scheme_id}->{$_} =
						  $scheme_field_prefs->{$scheme_id}->{$_}->{$action} ? 1 : 0;
					} else {
						$self->{'prefs'}->{"$action\_scheme_fields"}->{$scheme_id}->{$_} =
						  $scheme_field_default_prefs->{$scheme_id}->{$_}->{$action};
					}
				}
			}
		}
	}
	$self->{'datastore'}->update_prefs( $self->{'prefs'} );
}

sub _initiate_isolatedb_prefs {
	my ( $self, $general_prefs, $field_prefs, $scheme_field_prefs ) = @_;
	my $q          = $self->{'cgi'};
	my $logger     = get_logger('BIGSdb.Application_Initiate');
	my $field_list = $self->{'xmlHandler'}->get_field_list();
	my $params     = $q->Vars;
	my $extended   = $self->get_extended_attributes;

	#Parameters set by preference store via session cookie
	if (   $params->{'page'} eq 'options'
		&& $params->{'set'} )
	{

		#Switches
		foreach (
			qw ( update_details sequence_details mark_provisional mark_provisional_main sequence_details_main
			display_pending display_pending_main locus_alias scheme_members_alias sample_details undesignated_alleles)
		  )
		{
			$self->{'prefs'}->{$_} = ( $params->{$_} && $params->{$_} eq 'on' ) ? 1 : 0;
		}
		foreach (@$field_list) {
			if ( $_ ne 'id' ) {
				$self->{'prefs'}->{'maindisplayfields'}->{$_} = $params->{"field_$_"}     eq 'checked' ? 1 : 0;
				$self->{'prefs'}->{'dropdownfields'}->{$_}    = $params->{"dropfield_$_"} eq 'checked' ? 1 : 0;
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						$self->{'prefs'}->{'maindisplayfields'}->{"$_\..$extended_attribute"} =
						  $params->{"extended_$_\..$extended_attribute"} eq 'checked' ? 1 : 0;
						$self->{'prefs'}->{'dropdownfields'}->{"$_\..$extended_attribute"} =
						  $params->{"dropfield_e_$_\..$extended_attribute"} eq 'checked' ? 1 : 0;
					}
				}
			}
		}
		$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $params->{"field_aliases"} eq 'checked' ? 1 : 0;
		my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
		foreach (@$composites) {
			$self->{'prefs'}->{'maindisplayfields'}->{$_} = $params->{"field_$_"} eq 'checked' ? 1 : 0;
		}
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		foreach (@$schemes) {
			my $field = "scheme_$_\_profile_status";
			$self->{'prefs'}->{'dropdownfields'}->{$field} = $params->{"dropfield_$field"} eq 'checked' ? 1 : 0;
		}
		$self->{'prefs'}->{'dropdownfields'}->{'projects'}         = $q->param("dropfield_projects")         eq 'checked' ? 1 : 0;
		$self->{'prefs'}->{'dropdownfields'}->{'linked_sequences'} = $q->param("dropfield_linked_sequences") eq 'checked' ? 1 : 0;
	} else {
		my $guid             = $self->get_guid || 1;
		my $dbname           = $self->{'system'}->{'db'};
		my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
		if ( $self->{'pref_requirements'}->{'general'} ) {

			#default off
			foreach (qw (update_details undesignated_alleles scheme_members_alias sequence_details_main)) {
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'on' ? 1 : 0;
			}

			#default on
			foreach (
				qw (sequence_details sample_details mark_provisional mark_provisional_main display_pending display_pending_main locus_alias)
			  )
			{
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'off' ? 0 : 1;
			}
		}
		if ( $self->{'pref_requirements'}->{'query_field'} ) {
			foreach (qw (linked_sequences projects publications)) {
				if ( defined $field_prefs->{$_}->{'dropdown'} ) {
					$self->{'prefs'}->{'dropdownfields'}->{$_} = $field_prefs->{$_}->{'dropdown'} ? 1 : 0;
				} else {
					$self->{'prefs'}->{'dropdownfields'}->{$_} = $self->{'system'}->{$_} eq 'yes' ? 1 : 0;
				}
			}
			foreach (@$field_list) {
				next if $_ eq 'id';
				if ( defined $field_prefs->{$_}->{'dropdown'} ) {
					$self->{'prefs'}->{'dropdownfields'}->{$_} = $field_prefs->{$_}->{'dropdown'};
				} else {
					$self->{'prefs'}->{'dropdownfields'}->{$_} = $field_attributes->{$_}->{'dropdown'} eq 'yes' ? 1 : 0;
				}
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						if ( defined $field_prefs->{$_}->{'dropdown'} ) {
							$self->{'prefs'}->{'dropdownfields'}->{"$_\..$extended_attribute"} =
							  $field_prefs->{"$_\..$extended_attribute"}->{'dropdown'};
						} else {
							$self->{'prefs'}->{'dropdownfields'}->{"$_\..$extended_attribute"} = 0;
						}
					}
				}
			}
		}
		if ( $self->{'pref_requirements'}->{'main_display'} ) {
			if ( defined $field_prefs->{'aliases'}->{'maindisplay'} ) {
				$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $field_prefs->{'aliases'}->{'maindisplay'};
			} else {
				$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 1 : 0;
			}
			foreach (@$field_list) {
				next if $_ eq 'id';
				if ( defined $field_prefs->{$_}->{'maindisplay'} ) {
					$self->{'prefs'}->{'maindisplayfields'}->{$_} = $field_prefs->{$_}->{'maindisplay'};
				} else {
					$self->{'prefs'}->{'maindisplayfields'}->{$_} = $field_attributes->{$_}->{'maindisplay'} eq 'no' ? 0 : 1;
				}
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						if ( defined $field_prefs->{$_}->{'maindisplay'} ) {
							$self->{'prefs'}->{'maindisplayfields'}->{"$_\..$extended_attribute"} =
							  $field_prefs->{"$_\..$extended_attribute"}->{'maindisplay'};
						} else {
							$self->{'prefs'}->{'maindisplayfields'}->{"$_\..$extended_attribute"} = 0;
						}
					}
				}
			}
			my $qry = "SELECT id,main_display FROM composite_fields";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute(); };
			if ($@) {
				$logger->error("Can't execute $qry");
				return;
			}
			while ( my ( $id, $main_display ) = $sql->fetchrow_array() ) {
				if ( defined $field_prefs->{$id}->{'maindisplay'} ) {
					$self->{'prefs'}->{'maindisplayfields'}->{$id} = $field_prefs->{$id}->{'maindisplay'};
				} else {
					$self->{'prefs'}->{'maindisplayfields'}->{$id} = $main_display ? 1 : 0;
				}
			}
		}

		#Define locus defaults
		my $qry       = "SELECT id,isolate_display,main_display,query_field,analysis FROM loci";
		my $locus_sql = $self->{'db'}->prepare($qry);
		eval { $locus_sql->execute; };
		$logger->error($@) if $@;
		my $prefstore_values = $self->{'prefstore'}->get_all_locus_prefs( $guid, $dbname );
		my $array_ref        = $locus_sql->fetchall_arrayref;
		my $i                = 1;
		foreach my $action (qw (isolate_display main_display query_field analysis)) {
			if ( !$self->{'pref_requirements'}->{$action} ) {
				$i++;
				next;
			}
			my $term = "$action\_loci";
			foreach (@$array_ref) {
				if ( exists $prefstore_values->{ $_->[0] }->{$action} ) {
					if ( $action eq 'isolate_display' ) {
						$self->{'prefs'}->{$term}->{ $_->[0] } = $prefstore_values->{ $_->[0] }->{$action};
					} else {
						$self->{'prefs'}->{$term}->{ $_->[0] } = $prefstore_values->{ $_->[0] }->{$action} eq 'true' ? 1 : 0;
					}
				} else {
					$self->{'prefs'}->{$term}->{ $_->[0] } = $_->[$i];
				}
			}
			$i++;
		}
		return if none { $self->{'pref_requirements'}->{$_} } qw (isolate_display main_display query_field analysis);
		my $scheme_ids                 = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		my $scheme_values              = $self->{'prefstore'}->get_all_scheme_prefs( $guid, $dbname );
		my $scheme_field_default_prefs = $self->{'datastore'}->get_all_scheme_field_info;
		my $scheme_info                = $self->{'datastore'}->get_all_scheme_info;
		my $scheme_fields              = $self->{'datastore'}->get_all_scheme_fields;
		foreach my $scheme_id (@$scheme_ids) {

			foreach my $action (qw(isolate_display main_display query_field query_status analysis)) {
				if ( defined $scheme_values->{$scheme_id}->{$action} ) {
					$self->{'prefs'}->{"$action\_schemes"}->{$scheme_id} = $scheme_values->{$scheme_id}->{$action} ? 1 : 0;
				} else {
					$self->{'prefs'}->{"$action\_schemes"}->{$scheme_id} = $scheme_info->{$scheme_id}->{$action};
				}
			}
			if ( ref $scheme_fields->{$scheme_id} eq 'ARRAY' ) {
				foreach ( @{ $scheme_fields->{$scheme_id} } ) {
					foreach my $action (qw(isolate_display main_display query_field)) {
						if ( defined $scheme_field_prefs->{$scheme_id}->{$_}->{$action} ) {
							$self->{'prefs'}->{"$action\_scheme_fields"}->{$scheme_id}->{$_} =
							  $scheme_field_prefs->{$scheme_id}->{$_}->{$action} ? 1 : 0;
						} else {
							$self->{'prefs'}->{"$action\_scheme_fields"}->{$scheme_id}->{$_} =
							  $scheme_field_default_prefs->{$scheme_id}->{$_}->{$action};
						}
					}
				}
			}
			my $field = "scheme_$scheme_id\_profile_status";
			if ( defined $field_prefs->{$field}->{'dropdown'} ) {
				$self->{'prefs'}->{'dropdownfields'}->{$field} = $field_prefs->{$field}->{'dropdown'};
			} else {
				$self->{'prefs'}->{'dropdownfields'}->{$field} = $self->{'prefs'}->{'query_status_schemes'}->{$scheme_id};
			}
		}
	}
}

sub clean_checkbox_id {
	my ( $self, $var ) = @_;
	$var =~ s/'/__prime__/g;
	$var =~ s/\//__slash__/g;
	$var =~ s/,/__comma__/g;
	$var =~ s/ /__space__/g;
	$var =~ s/\(/_OPEN_/g;
	$var =~ s/\)/_CLOSE_/g;
	$var =~ s/\>/_GT_/g;
	return $var;
}

sub escape_params {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my @param_names = $q->param;
	my %escapes =
	  ( '__prime__' => "'", '__slash__' => "\\", '__comma__' => ',', '__space__' => ' ', '_OPEN_' => "(", '_CLOSE_' => ")", '_GT_' => ">" );
	foreach my $param_name (@param_names) {
		my $key = $param_name;
		if ( any { $param_name =~ /$_/ } keys %escapes ) {
			foreach my $escape_string ( keys %escapes ) {
				$key =~ s/$escape_string/$escapes{$escape_string}/g;
			}
			$q->param( $key, $q->param($param_name) );
		}
	}
}
###SCHEME GROUP TREE DRAWING#################
sub get_tree {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $page = $self->{'cgi'}->param('page');
	my $isolate_clause = defined $isolate_id ? "&amp;id=$isolate_id" : '';
	my $groups_with_no_parent =
	  $self->{'datastore'}->run_list_query(
		"SELECT id FROM scheme_groups WHERE id NOT IN (SELECT group_id FROM scheme_group_group_members) ORDER BY display_order");
	my $schemes_not_in_group =
	  $self->{'datastore'}->run_list_query_hashref(
		"SELECT id,description FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) ORDER BY display_order");
	my $buffer;
	my $scheme_nodes;
	foreach (@$groups_with_no_parent) {
		my $group_info          = $self->{'datastore'}->get_scheme_group_info($_);
		my $group_scheme_buffer = $self->_get_group_schemes( $_, $isolate_id, $options );
		my $child_group_buffer  = $self->_get_child_groups( $_, $isolate_id, 1, $options );
		if ( $group_scheme_buffer || $child_group_buffer ) {
			if ( $options->{'no_link_out'} ) {
				$buffer .= "<li><a>$group_info->{'name'}</a>\n";
			} else {
				$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
			}
			$buffer .= $group_scheme_buffer;
			$buffer .= $child_group_buffer;
			$buffer .= "</li>\n";
		}
	}
	if (@$schemes_not_in_group) {
		my $data_exists = 0;
		my $temp_buffer;
		if (@$groups_with_no_parent) {
			if ( $options->{'no_link_out'} ) {
				$temp_buffer .= "<li><a>Other schemes</a><ul>";
			} else {
				$temp_buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;group_id=0\" rel=\"ajax\">Other schemes</a><ul>";
			}
		}
		foreach (@$schemes_not_in_group) {
			next if $options->{'isolate_display'} && !$self->{'prefs'}->{'isolate_display_schemes'}->{ $_->{'id'} };
			next if $options->{'analysis_pref'}   && !$self->{'prefs'}->{'analysis_schemes'}->{ $_->{'id'} };
			$_->{'description'} =~ s/&/\&amp;/g;
			if ( !defined $isolate_id || $self->_scheme_data_present( $_->{'id'}, $isolate_id ) ) {
				my $scheme_loci_buffer;
				if ( $options->{'list_loci'} ) {
					$scheme_loci_buffer = $self->_get_scheme_loci( $_->{'id'}, $isolate_id, $options );
					$data_exists = 1 if $scheme_loci_buffer;
				} else {
					$data_exists = 1;
				}
				if ( $options->{'no_link_out'} ) {
					$temp_buffer .= "<li><a>$_->{'description'}</a>\n";
				} else {
					$temp_buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=$_->{'id'}\" rel=\"ajax\">$_->{'description'}</a>\n";
				}
				$temp_buffer .= $scheme_loci_buffer;
				$temp_buffer .= "</li>\n";
			}
		}
		$temp_buffer .= "</ul></li>" if @$groups_with_no_parent;
		$buffer .= $temp_buffer if $data_exists;
	}
	my $loci_not_in_schemes = $self->{'datastore'}->get_loci_in_no_scheme;
	if ( @$loci_not_in_schemes && ( !defined $isolate_id || $self->_data_not_in_scheme_present($isolate_id) ) ) {
		my $scheme_loci_buffer;
		if ( $options->{'list_loci'} ) {
			$scheme_loci_buffer = $self->_get_scheme_loci( 0, $isolate_id, $options ) if $options->{'list_loci'};
		}
		if ( !$options->{'list_loci'} || ( $options->{'list_loci'} && $scheme_loci_buffer ) ) {
			if ( $options->{'no_link_out'} ) {
				$buffer .= "<li><a>Loci not in schemes</a>\n";
			} else {
				$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=0\" rel=\"ajax\">Loci not in schemes</a>\n";
			}
			$buffer .= $scheme_loci_buffer;
			$buffer .= "</li>\n";
		}
	}
	my $main_buffer;
	if ($buffer) {
		$main_buffer = "<ul>\n";
		if ( $options->{'no_link_out'} ) {
			$main_buffer .= "<li id=\"all_loci\"><a>All loci</a><ul>\n";
		} else {
			$main_buffer .=
"<li id=\"all_loci\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=-1\" rel=\"ajax\">All loci</a><ul>\n";
		}
		$main_buffer .= $buffer;
		$main_buffer .= "</ul>\n";
		$main_buffer .= "</li></ul>\n";
	} else {
		$main_buffer = "<ul><li><a>No loci available for analysis.</a></li></ul>\n";
	}
	return $main_buffer;
}

sub _get_group_schemes {
	my ( $self, $group_id, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	my $schemes = $self->{'datastore'}->run_list_query(
"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id WHERE group_id=? ORDER BY display_order",
		$group_id
	);
	if (@$schemes) {
		foreach (@$schemes) {
			next if $options->{'isolate_display'} && !$self->{'prefs'}->{'isolate_display_schemes'}->{$_};
			next if $options->{'analysis_pref'}   && !$self->{'prefs'}->{'analysis_schemes'}->{$_};
			my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
			my $scheme_loci_buffer;
			if ( $options->{'list_loci'} ) {
				$scheme_loci_buffer = $self->_get_scheme_loci( $scheme_info->{'id'}, $isolate_id, $options );
				next if !$scheme_loci_buffer;
			}
			$scheme_info->{'description'} =~ s/&/\&amp;/g;
			my $page = $self->{'cgi'}->param('page');
			if ( defined $isolate_id ) {
				if ( $self->_scheme_data_present( $_, $isolate_id ) ) {
					if ( $options->{'no_link_out'} ) {
						$buffer .= "<li><a>$scheme_info->{'description'}</a>";
					} else {
						$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;id=$isolate_id&amp;scheme_id=$scheme_info->{'id'}\" rel=\"ajax\">$scheme_info->{'description'}</a>";
					}
					$buffer .= $scheme_loci_buffer;
					$buffer .= "</li>\n";
				}
			} else {
				if ( $options->{'no_link_out'} ) {
					$buffer .= "<li><a>$scheme_info->{'description'}</a>";
				} else {
					$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;scheme_id=$scheme_info->{'id'}\" rel=\"ajax\">$scheme_info->{'description'}</a>";
				}
				$buffer .= $scheme_loci_buffer;
				$buffer .= "</li>\n";
			}
		}
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
}

sub _get_scheme_loci {
	my ( $self, $scheme_id, $isolate_id, $options ) = @_;
	my $analysis_pref = $self->{'system'}->{'dbtype'} eq 'isolates' ? 1 : 0;
	my ( $loci, $scheme_fields );
	if ($scheme_id) {
		$loci = $self->{'datastore'}->get_scheme_loci( $scheme_id, { 'profile_name' => 0, 'analysis_pref' => $analysis_pref } );
		if ( $options->{'scheme_fields'} ) {
			$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		}
	} else {
		$loci = $self->{'datastore'}->get_loci_in_no_scheme($analysis_pref);
	}
	my $qry    = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
	my $cn_sql = $self->{'db'}->prepare($qry);
	eval { $cn_sql->execute; };
	$logger->error($@) if $@;
	my $common_names = $cn_sql->fetchall_hashref('id');
	my $buffer;
	foreach (@$loci) {
		my $cleaned = $self->clean_checkbox_id($_);
		my $id      = $scheme_id ? "s_$scheme_id\_l_$cleaned" : "l_$cleaned";
		my $locus   = $self->clean_locus($_);
		$buffer .= "<li id=\"$id\"><a>$locus";
		$buffer .= " ($common_names->{$_}->{'common_name'})" if $common_names->{$_}->{'common_name'};
		$buffer .= "</a></li>\n";
	}
	foreach my $scheme_field (@$scheme_fields) {
		my $cleaned = $self->clean_checkbox_id($scheme_field);
		my $id      = "s_$scheme_id\_f_$cleaned";
		$scheme_field =~ tr/_/ /;
		$buffer .= "<li id=\"$id\"><a>$scheme_field</a></li>\n";
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
}

sub _get_child_groups {
	my ( $self, $group_id, $isolate_id, $level, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	my $child_groups = $self->{'datastore'}->run_list_query(
"SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order",
		$group_id
	);
	if (@$child_groups) {
		foreach (@$child_groups) {
			my $group_info = $self->{'datastore'}->get_scheme_group_info($_);
			my $new_level  = $level;
			last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
			my $group_scheme_buffer = $self->_get_group_schemes( $_, $isolate_id, $options );
			my $child_group_buffer = $self->_get_child_groups( $_, $isolate_id, ++$new_level, $options );
			if ( $group_scheme_buffer || $child_group_buffer ) {
				my $page = $self->{'cgi'}->param('page');
				if ( defined $isolate_id ) {
					if ( $options->{'no_link_out'} ) {
						$buffer .= "<li><a>$group_info->{'name'}</a>\n";
					} else {
						$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;id=$isolate_id&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
					}
				} else {
					if ( $options->{'no_link_out'} ) {
						$buffer .= "<li><a>$group_info->{'name'}</a>\n";
					} else {
						$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
					}
				}
				$buffer .= $group_scheme_buffer;
				$buffer .= $child_group_buffer;
				$buffer .= "</li>";
			}
		}
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
}

sub _scheme_data_present {
	my ( $self, $scheme_id, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'scheme_data_designations'} ) {
		$self->{'sql'}->{'scheme_data_designations'} =
		  $self->{'db'}->prepare(
"SELECT EXISTS(SELECT * FROM allele_designations LEFT JOIN scheme_members ON allele_designations.locus=scheme_members.locus WHERE isolate_id=? AND scheme_id=?)"
		  );
	}
	eval { $self->{'sql'}->{'scheme_data_designations'}->execute( $isolate_id, $scheme_id ); };
	$logger->error($@) if $@;
	my ($designations_present) = $self->{'sql'}->{'scheme_data_designations'}->fetchrow_array;
	return 1 if $designations_present;
	if ( !$self->{'sql'}->{'scheme_data_sequences'} ) {
		$self->{'sql'}->{'scheme_data_sequences'} =
		  $self->{'db'}->prepare(
"SELECT EXISTS(SELECT * FROM allele_sequences LEFT JOIN scheme_members ON allele_sequences.locus=scheme_members.locus LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id WHERE isolate_id=? AND scheme_id=?)"
		  );
	}
	eval { $self->{'sql'}->{'scheme_data_sequences'}->execute( $isolate_id, $scheme_id ); };
	$logger->error($@) if $@;
	my ($sequences_present) = $self->{'sql'}->{'scheme_data_sequences'}->fetchrow_array;
	return $sequences_present ? 1 : 0;
}

sub _data_not_in_scheme_present {
	my ( $self, $isolate_id ) = @_;
	my $designations =
	  $self->{'datastore'}->run_simple_query(
		"SELECT EXISTS(SELECT * FROM allele_designations WHERE isolate_id=? AND locus NOT IN (SELECT locus FROM scheme_members))",
		$isolate_id )->[0];
	return 1 if $designations;
	my $sequences = $self->{'datastore'}->run_simple_query(
"SELECT EXISTS(SELECT * FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id WHERE isolate_id=? AND locus NOT IN (SELECT locus FROM scheme_members))",
		$isolate_id
	)->[0];
	return $sequences ? 1 : 0;
}
###END GROUP TREE DRAWING####################
1;
