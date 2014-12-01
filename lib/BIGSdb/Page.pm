#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use warnings;
use 5.010;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);
use List::MoreUtils qw(uniq any none);
use autouse 'Data::Dumper' => qw(Dumper);
use Memoize;
memoize( 'clean_locus', NORMALIZER => '_normalize_clean_locus' );
memoize('get_seq_detail_tooltips');
use parent 'Exporter';
use constant SEQ_METHODS => ( '454', 'Illumina', 'Ion Torrent', 'PacBio', 'Sanger', 'Solexa', 'SOLiD', 'other', 'unknown' );
use constant SEQ_FLAGS => (
	'ambiguous read',
	'apparent misassembly',
	'atypical',
	'contains IS element',
	'downstream fusion',
	'frameshift',
	'internal stop codon',
	'no start codon',
	'phase variable: off',
	'truncated',
	'upstream fusion'
);
use constant ALLELE_FLAGS => (
	'atypical',
	'contains IS element',
	'downstream fusion',
	'frameshift',
	'internal stop codon',
	'no start codon',
	'phase variable: off',
	'truncated',
	'upstream fusion'
);
use constant SEQ_STATUS => ( 'Sanger trace checked', 'WGS: manual extract', 'WGS: automated extract', 'unchecked' );
use constant DIPLOID    => qw(A C G T R Y W S M K);
use constant HAPLOID    => qw(A C G T);
use constant DATABANKS  => qw(ENA Genbank);
use constant FLANKING      => qw(0 20 50 100 200 500 1000 2000 5000 10000 25000 50000);
use constant LOCUS_PATTERN => qr/^(?:l|cn|la)_(.+?)(?:\|\|.+)?$/;
our @EXPORT_OK = qw(SEQ_METHODS SEQ_FLAGS ALLELE_FLAGS SEQ_STATUS DIPLOID HAPLOID DATABANKS FLANKING LOCUS_PATTERN);

sub new {    ## no critic (RequireArgUnpacking)
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
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;                                                      #Use JQuery javascript library
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 1, isolate_display => 1, analysis => 1, query_field => 1 };
	return;
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
		if ( !defined $self->{'username'} ) {

			#This can happen if a not logged in user tries to access a plugin.
			$logger->debug("No logged in user; Database $self->{'system'}->{'db'}");
			$self->{'username'} = '';
		}
		return "$self->{'system'}->{'db'}\|$self->{'username'}";
	} elsif ( $self->{'cgi'}->cookie( -name => 'guid' ) ) {
		return $self->{'cgi'}->cookie( -name => 'guid' );
	} else {
		return 0;
	}
}

sub print_banner {
	my ($self) = @_;
	my $bannerfile = "$self->{'dbase_config_dir'}/$self->{'instance'}/banner.html";
	if ( -e $bannerfile ) {
		print "<div class=\"box\" id=\"banner\">\n";
		$self->print_file($bannerfile);
		print "</div>\n";
	}
	return;
}

sub choose_set {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('choose_set') && defined $q->param('sets_list') && BIGSdb::Utils::is_int( $q->param('sets_list') ) ) {
		my $guid = $self->get_guid;
		if ($guid) {
			try {
				$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, 'set_id', $q->param('sets_list') );
				$self->{'prefs'}->{'set_id'} = $q->param('sets_list');
			}
			catch BIGSdb::PrefstoreConfigurationException with {
				$logger->error("Can't set set_id in prefs");
			};
		} else {
			$self->{'system'}->{'sets'} = 'no';
		}
	}
	return;
}

sub _initiate_plugin {
	my ( $self, $plugin_name ) = @_;
	my $q = $self->{'cgi'};
	$q->param( format => 'html' ) if !defined $q->param('format');
	try {
		my $plugin = $self->{'pluginManager'}->get_plugin($plugin_name);
		my $att    = $plugin->get_attributes;
		if ( $q->param('format') eq 'text' ) {
			$self->{'type'}       = 'text';
			$self->{'attachment'} = $att->{'text_filename'};
		} elsif ( $q->param('format') eq 'xlsx' ) {
			$self->{'type'}       = 'xlsx';
			$self->{'attachment'} = $att->{'xlsx_filename'};
		} elsif ( $q->param('format') eq 'tar' ) {
			$self->{'type'}       = 'tar';
			$self->{'attachment'} = $att->{'tar_filename'};
		} else {
			$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort jQuery.jstree jQuery.slimbox);
		}
	}
	catch BIGSdb::InvalidPluginException with {

		#ignore
	};
	return;
}

sub print_page_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$" = ' ';    ## no critic (RequireLocalizedPunctuationVars) #ensure reset when running under mod_perl
	if ( ( $q->param('page') // '' ) eq 'plugin' ) {
		my $plugin_name = $q->param('name');
		$self->_initiate_plugin($plugin_name);

		#need to determine if tooltips should be displayed since this is set in the <HEAD>.  Also need to define set_id
		#since this is needed to determine page title (other prefs are read later but these are needed early).
		if ( $self->{'prefstore'} ) {
			my $guid = $self->get_guid;
			try {
				$self->{'prefs'}->{'tooltips'} =
				  ( $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'tooltips' ) // '' ) eq 'off' ? 0 : 1;
				$self->{'prefs'}->{'set_id'} = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'set_id' );
			}
			catch BIGSdb::DatabaseNoRecordException with {
				$self->{'prefs'}->{'tooltips'} = 1;
			};
			$self->choose_set;
		}
	} else {
		$self->initiate_prefs;
		$self->initiate_view( $self->{'username'}, $self->{'curate'} );
	}
	$q->charset('UTF-8');
	if ( $self->{'type'} ne 'xhtml' ) {
		my %atts;
		if ( $self->{'type'} eq 'embl' ) {
			$atts{'type'} = 'chemical/x-embl-dl-nucleotide';
			my $id = $q->param('seqbin_id') || $q->param('isolate_id') || '';
			$atts{'attachment'} = "sequence$id.embl";
		} elsif ( $self->{'type'} eq 'tar' ) {
			$atts{'type'}       = 'application/x-tar';
			$atts{'attachment'} = $self->{'attachment'};
		} elsif ( $self->{'type'} eq 'xlsx' ) {
			$atts{'type'}       = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
			$atts{'attachment'} = $self->{'attachment'};
		} elsif ( $self->{'type'} eq 'no_header' ) {
			$atts{'type'} = 'text/html';
		} else {
			$atts{'type'}       = 'text/plain';
			$atts{'attachment'} = $self->{'attachment'};
		}
		$atts{'expires'} = '+1h' if !$self->{'noCache'};
		print $q->header( \%atts );
		$self->print_content;
	} else {
		binmode STDOUT, ":encoding(utf8)";
		if ( !$q->cookie( -name => 'guid' ) && $self->{'prefstore'} ) {
			my $guid = $self->{'prefstore'}->get_new_guid;
			push @{ $self->{'cookies'} }, $q->cookie( -name => 'guid', -value => $guid, -expires => '+10y' );
			$self->{'setOptions'} = 1;
		}
		my %header_options;
		$header_options{'-cookie'} = $self->{'cookies'} if $self->{'cookies'};
		$header_options{'-expires'} = '+1h' if !$self->{'noCache'};
		print $q->header(%header_options);
		my $title   = $self->get_title;
		my $page_js = $self->get_javascript;
		my @javascript;

		if ( $self->{'jQuery'} ) {
			if ( $self->{'config'}->{'intranet'} eq 'yes' ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.js" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery-ui.js" } );
			} else {

				#Load jQuery library from Google CDN
				push @javascript,
				  ( { 'language' => 'Javascript', 'src' => "http://ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js" } );
				push @javascript,
				  ( { 'language' => 'Javascript', 'src' => "http://ajax.googleapis.com/ajax/libs/jqueryui/1.10.2/jquery-ui.min.js" } );
			}
			push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/bigsdb.js?v20130615" } );
			if ( $self->{'jQuery.tablesort'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.tablesorter.js?v20110725" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.metadata.js" } );
			}
			if ( $self->{'jQuery.jstree'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.jstree.js?v20110605" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.cookie.js" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.hotkeys.js" } );
			}
			if ( $self->{'jQuery.coolfieldset'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.coolfieldset.js?v20130405" } );
			}
			if ( $self->{'jQuery.slimbox'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.slimbox2.js?v20130405" } );
			}
			if ( $self->{'jQuery.columnizer'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.columnizer.js" } );
			}
			if ( $self->{'jQuery.multiselect'} ) {
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/modernizr.js" } );
				push @javascript, ( { 'language' => 'Javascript', 'src' => "/javascript/jquery.multiselect.js" } );
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
		my $http_equiv = "<meta name=\"viewport\" content=\"width=device-width\" />";
		if ( $self->{'refresh'} ) {
			my $refresh_page = $self->{'refresh_page'} ? "; URL=$self->{'refresh_page'}" : '';
			$http_equiv .= "<meta http-equiv=\"refresh\" content=\"$self->{'refresh'}$refresh_page\" />";
		}
		my $tooltip_display = $self->{'prefs'}->{'tooltips'} ? 'inline' : 'none';
		my $stylesheets     = $self->get_stylesheets;
		my @args            = (
			-title => $title,
			-meta  => {%meta_content},
			-style => [
				{ -src  => $stylesheets->[0], -media => 'Screen' },
				{ -src  => $stylesheets->[1], -media => 'Screen' },
				{ -code => ".tooltip{display:$tooltip_display}" }
			],
			-script   => \@javascript,
			-encoding => 'utf-8'
		);
		if (%shortcut_icon) {
			push @args, ( -head => [ CGI->Link( {%shortcut_icon} ), $http_equiv ] );
		} else {
			push @args, ( -head => $http_equiv );
		}
		my $head = $q->start_html(@args);
		my $dtd  = '<!DOCTYPE html>';
		$head =~ s/<!DOCTYPE.*?>/$dtd/s;    #CGI.pm doesn't support HTML5 DOCTYPE
		$head =~ s/<html[^>]*>/<html>/;
		say $head;
		$self->_print_header;
		$self->_print_login_details
		  if ( defined $self->{'system'}->{'read_access'} && $self->{'system'}->{'read_access'} ne 'public' ) || $self->{'curate'};
		$self->_print_help_panel;
		$self->print_content;
		$self->_print_footer;
		$self->_debug if $q->param('debug') && $self->{'config'}->{'debug'};
		print $q->end_html;
	}
	return;
}

sub get_stylesheets {
	my ($self) = @_;
	my $stylesheet;
	my $system    = $self->{'system'};
	my $version   = '20141114';
	my @filenames = qw(bigsdb.css jquery-ui.css);
	my @paths;
	foreach my $filename (@filenames) {
		my $vfilename = "$filename?v=$version";
		if ( !$system->{'db'} ) {
			$stylesheet = "/$filename";
		} elsif ( -e "$ENV{'DOCUMENT_ROOT'}$system->{'webroot'}/$system->{'db'}/$filename" ) {
			$stylesheet = "$system->{'webroot'}/$system->{'db'}/$vfilename";
		} elsif ( -e "$ENV{'DOCUMENT_ROOT'}$system->{'webroot'}/$filename" ) {
			$stylesheet = "$system->{'webroot'}/$vfilename";
		} else {
			$stylesheet = "/$vfilename";
		}
		push @paths, $stylesheet;
	}
	return \@paths;
}
sub get_title     { return 'BIGSdb' }
sub print_content { }

sub print_set_section {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	return if $self->{'system'}->{'set_id'} && BIGSdb::Utils::is_int( $self->{'system'}->{'set_id'} );
	my $guid = $self->get_guid;
	return if !$guid;    #Cookies disabled
	my $sets = $self->{'datastore'}->run_query( "SELECT * FROM sets WHERE NOT hidden OR hidden IS NULL ORDER BY display_order,description",
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$sets || ( @$sets == 1 && ( $self->{'system'}->{'only_sets'} // '' ) eq 'yes' );
	say "<div class=\"box\" id=\"sets\">";
	print << "SETS";
<div class="scrollable">	
<div style="float:left; margin-right:1em">
<img src="/images/icons/64x64/choose.png" alt="" />
<h2>Datasets</h2>
<p>This database contains multiple datasets.  
SETS
	print(
		( $self->{'system'}->{'only_sets'} // '' ) eq 'yes'
		? '</p>'
		: 'You can choose to display a single set or the whole database.</p>'
	);
	say $q->start_form;
	say "<label for=\"sets_list\">Please select: </label>";
	my @set_ids;

	if ( ( $self->{'system'}->{'only_sets'} // '' ) ne 'yes' ) {
		push @set_ids, 0;
	}
	my %labels = ( 0 => 'Whole database' );
	foreach my $set (@$sets) {
		push @set_ids, $set->{'id'};
		$labels{ $set->{'id'} } = $set->{'description'};
	}
	say $q->popup_menu( -name => 'sets_list', -id => 'sets_list', -values => \@set_ids, -labels => \%labels, -default => $set_id );
	say $q->submit( -name => 'choose_set', -label => 'Choose', -class => 'smallbutton' );
	say $q->hidden($_) foreach qw (db page name set_id select_sets);
	say $q->end_form;
	say "</div></div></div>";
	return;
}

sub is_scheme_invalid {
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>";
		return 1;
	} elsif ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The selected scheme is unavailable.</p></div>";
			return 1;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info && !( $scheme_id == 0 && $options->{'all_loci'} ) ) {
		say "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>";
		return 1;
	}
	if ( $options->{'with_pk'} && !$scheme_info->{'primary_key'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  This function is unavailable "
		  . "until this has been set.</p></div>";
		return 1;
	}
	return;
}

sub print_scheme_section {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q       = $self->{'cgi'};
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => $options->{'with_pk'} } );
	$q->param( scheme_id => $schemes->[0]->{'id'} ) if !defined $q->param('scheme_id') && @$schemes;
	return if @$schemes < 2;
	say "<div class=\"box\" id=\"schemes\">";
	say "<div class=\"scrollable\">";
	say "<h2>Schemes</h2>";
	say "<p>Please select the scheme you would like to query:</p>";
	my @ids;
	my %desc;

	foreach my $scheme (@$schemes) {
		push @ids, $scheme->{'id'};
		$desc{ $scheme->{'id'} } = $scheme->{'description'};
	}
	if ( $options->{'all_loci'} ) {
		push @ids, 0;
		$desc{0} = 'All loci';
	}
	my $default = $q->param('scheme_id');
	say $q->start_form;
	say $q->popup_menu( -name => 'scheme_id', -values => \@ids, -labels => \%desc, -default => $default );
	say $q->submit( -class => 'submit', -name => 'Select' );
	say $q->hidden($_) foreach qw(db page name);
	say $q->end_form;
	say "</div></div>";
	return;
}

sub print_action_fieldset {
	my ( $self, $options ) = @_;
	my $q = $self->{'cgi'};
	$options = {} if ref $options ne 'HASH';
	my $page         = $options->{'page'}         // $q->param('page');
	my $submit_label = $options->{'submit_label'} // 'Submit';
	my $buffer       = "<fieldset style=\"float:left\"><legend>Action</legend>\n";
	my $url          = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page";
	my @fields       = qw (isolate_id id scheme_id table name ruleset locus profile_id simple set_id);
	if ( $options->{'table'} ) {
		my $pk_fields = $self->{'datastore'}->get_table_pks( $options->{'table'} );
		push @fields, @$pk_fields;
	}
	foreach ( uniq @fields ) {
		$url .= "&amp;$_=$options->{$_}" if defined $options->{$_};
	}

	#use jquery-ui button classes to ensure consistent formatting of reset link and submit button across browsers
	if ( !$options->{'no_reset'} ) {
		$buffer .= "<a href=\"$url\" class=\"resetbutton ui-button ui-widget ui-state-default ui-corner-all ui-button-text-only \">"
		  . "<span class=\"ui-button-text\">Reset</span>";
		$buffer .= "</a>\n";
	}
	$buffer .=
	  $q->submit( -name => 'submit', -label => $submit_label, -class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all' );
	$buffer .= "</fieldset><div style=\"clear:both\"></div>";
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub _debug {
	my ($self) = @_;
	print "<pre>\n" . Dumper($self) . "</pre>\n";
	return;
}

sub _print_header {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $filename = $self->{'curate'} ? 'curate_header.html' : 'header.html';
	my $header_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/$filename";
	$self->print_file($header_file) if ( -e $header_file );
	return;
}

sub _print_login_details {
	my ($self) = @_;
	return if !$self->{'datastore'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	say qq(<div id="logindetails">);
	if ( !$user_info ) {
		if ( !$self->{'username'} ) {
			say "<i>Not logged in.</i>";
		} else {
			say "<i>Logged in: <b>Unregistered user.</b></i>";
		}
	} else {
		say "<i>Logged in: <b>$user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'}).</b></i>";
	}
	if ( $self->{'system'}->{'authentication'} eq 'builtin' ) {
		if ( $self->{'username'} ) {
			say qq( <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=logout">Log out</a> | );
			say qq( <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=changePassword">Change password</a>);
		}
	}
	say "</div>";
	return;
}

sub get_help_url {

	#Override in subclass.
}

sub _print_help_panel {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<div id=\"fieldvalueshelp\">";
	if ( $q->param('page') && $q->param('page') eq 'plugin' && defined $self->{'pluginManager'} ) {
		my $plugin_att = $self->{'pluginManager'}->get_plugin_attributes( $q->param('name') );
		if ( ref $plugin_att eq 'HASH' ) {
			if ( $plugin_att->{'url'} && ( $self->{'config'}->{'intranet'} // '' ) ne 'yes' ) {
				say qq(<span class="context_help"><a href="$plugin_att->{'url'}" target="_blank">Help )
				  . qq(<img src="/images/external_link.png" alt="" title="Open help in new window" /></a></span>);
			}
			if ( ( $plugin_att->{'help'} // '' ) =~ /tooltips/ ) {
				$self->{'tooltips'} = 1;
			}
		}
	} else {
		my $url = $self->get_help_url;
		if ( $url && ( $self->{'config'}->{'intranet'} // '' ) ne 'yes' ) {
			say qq(<span class="context_help"><a href="$url" target="_blank">Help )
			  . qq(<img src="/images/external_link.png" alt="" title="Open help in new window" /></a></span>);
		}
	}
	if ( $self->{'tooltips'} ) {
		print "<span id=\"toggle\" style=\"display:none\">Toggle: </span><a id=\"toggle_tooltips\" href=\""
		  . "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=options&amp;toggle_tooltips=1\" style=\"display:none; "
		  . "margin-right:1em;\">&nbsp;<i>i</i>&nbsp;</a> ";
	}
	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' && $self->{'field_help'} ) {

		#open new page unless already on field values help page
		print $q->param('page') eq 'fieldValues'
		  ? $q->start_form( -style => 'display:inline' )
		  : $q->start_form( -target => '_blank', -style => 'display:inline' );
		print "<b>Field help: </b>";
		my ( $values, $labels ) =
		  $self->get_field_selection_list( { isolate_fields => 1, loci => 1, locus_limit => 100, scheme_fields => 1 } );
		print $self->popup_menu( -name => 'field', -values => $values, -labels => $labels );
		print $q->submit( -name => 'Go', -class => 'fieldvaluebutton' );
		my $refer_page = $q->param('page');
		$q->param( 'page', 'fieldValues' );
		print $q->hidden($_) foreach qw (db page);
		print $q->end_form;
		$q->param( 'page', $refer_page );
	}
	print "</div>\n";
	return;
}

sub get_metaset_and_fieldname {
	my ( $self, $field ) = @_;
	my ( $metaset, $metafield ) = $field =~ /meta_([^:]+):(.*)/ ? ( $1, $2 ) : ( undef, undef );
	return ( $metaset, $metafield );
}

sub add_existing_metadata_to_hashref {
	my ( $self, $data ) = @_;
	my $metadata_list = $self->{'xmlHandler'}->get_metadata_list;
	foreach my $metadata_set (@$metadata_list) {
		my $metadata =
		  $self->{'datastore'}
		  ->run_query( "SELECT * FROM $metadata_set WHERE isolate_id=?", $data->{'id'}, { fetch => 'all_arrayref', slice => {} } );
		foreach my $metadata_ref (@$metadata) {
			foreach my $field ( keys %$metadata_ref ) {
				$data->{"$metadata_set:$field"} = $metadata_ref->{$field};
			}
		}
	}
	return;
}

sub get_extended_attributes {
	my ($self) = @_;
	my $extended;
	my $sql = $self->{'db'}->prepare("SELECT isolate_field,attribute FROM isolate_field_extended_attributes ORDER BY field_order");
	eval { $sql->execute };
	$logger->error($@) if $@;
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
	#locus_limit: don't include loci if there are more than the set value
	#query_pref: only the loci for which the user has a query field preference selected will be returned
	#analysis_pref: only the loci for which the user has an analysis preference selected will be returned
	#scheme_fields: include scheme fields, prefix with s_SCHEME-ID_
	#sort_labels: dictionary sort labels
	my ( $self, $options ) = @_;
	$logger->logdie("Invalid option hashref") if ref $options ne 'HASH';
	$options->{'query_pref'}    //= 1;
	$options->{'analysis_pref'} //= 0;
	my @values;
	if ( $options->{'isolate_fields'} ) {
		my $isolate_fields = $self->_get_provenance_fields($options);
		push @values, @$isolate_fields;
	}
	if ( $options->{'loci'} ) {
		if ( !$self->{'cache'}->{'loci'} ) {
			my @locus_list;
			my $cn_sql = $self->{'db'}->prepare("SELECT id,common_name FROM loci WHERE common_name IS NOT NULL");
			eval { $cn_sql->execute };
			$logger->error($@) if $@;
			my $common_names = $cn_sql->fetchall_hashref('id');
			my $set_id       = $self->get_set_id;
			my $loci         = $self->{'datastore'}->get_loci(
				{
					query_pref    => $options->{'query_pref'},
					analysis_pref => $options->{'analysis_pref'},
					seq_defined   => 0,
					do_not_order  => 1,
					set_id        => $set_id
				}
			);
			my $set_loci = {};

			if ($set_id) {
				my $set_loci_sql = $self->{'db'}->prepare("SELECT * FROM set_loci WHERE set_id=?");
				eval { $set_loci_sql->execute($set_id) };
				$logger->error($@) if $@;
				$set_loci = $set_loci_sql->fetchall_hashref('locus');
			}
			foreach my $locus (@$loci) {
				push @locus_list, "l_$locus";
				$self->{'cache'}->{'labels'}->{"l_$locus"} = $locus;
				my $set_name_is_set;
				if ($set_id) {
					my $set_locus = $set_loci->{$locus};
					if ( $set_locus->{'set_name'} ) {
						$self->{'cache'}->{'labels'}->{"l_$locus"} = $set_locus->{'set_name'};
						if ( $set_locus->{'set_common_name'} ) {
							$self->{'cache'}->{'labels'}->{"l_$locus"} .= " ($set_locus->{'set_common_name'})";
							push @locus_list, "cn_$locus";
							$self->{'cache'}->{'labels'}->{"cn_$locus"} = "$set_locus->{'set_common_name'} ($set_locus->{'set_name'})";
						}
						$set_name_is_set = 1;
					}
				}
				if ( !$set_name_is_set && $common_names->{$locus}->{'common_name'} ) {
					$self->{'cache'}->{'labels'}->{"l_$locus"} .= " ($common_names->{$locus}->{'common_name'})";
					push @locus_list, "cn_$locus";
					$self->{'cache'}->{'labels'}->{"cn_$locus"} = "$common_names->{$locus}->{'common_name'} ($locus)";
				}
			}
			if ( $self->{'prefs'}->{'locus_alias'} ) {
				my $alias_sql = $self->{'db'}->prepare("SELECT locus,alias FROM locus_aliases");
				eval { $alias_sql->execute };
				if ($@) {
					$logger->error($@);
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
		if ( !$options->{'locus_limit'} || @{ $self->{'cache'}->{'loci'} } < $options->{'locus_limit'} ) {
			push @values, @{ $self->{'cache'}->{'loci'} };
		}
	}
	if ( $options->{'scheme_fields'} ) {
		my $scheme_fields = $self->_get_scheme_fields($options);
		push @values, @$scheme_fields;
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

sub _get_provenance_fields {
	my ( $self, $options ) = @_;
	my @isolate_list;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => $self->{'curate'} } );
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $attributes    = $self->{'xmlHandler'}->get_all_field_attributes;
	my $extended      = $options->{'extended_attributes'} ? $self->get_extended_attributes : undef;
	foreach my $field (@$fields) {

		if (   ( $options->{'sender_attributes'} )
			&& ( $field eq 'sender' || $field eq 'curator' || ( $attributes->{$field}->{'userfield'} // '' ) eq 'yes' ) )
		{
			foreach my $user_attribute (qw (id surname first_name affiliation)) {
				push @isolate_list, "f_$field ($user_attribute)";
				( $self->{'cache'}->{'labels'}->{"f_$field ($user_attribute)"} = "$field ($user_attribute)" ) =~ tr/_/ /;
			}
		} else {
			push @isolate_list, "f_$field";
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			( $self->{'cache'}->{'labels'}->{"f_$field"} = $metafield // $field ) =~ tr/_/ /;
			if ( $options->{'extended_attributes'} ) {
				my $extatt = $extended->{$field};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						push @isolate_list, "e_$field||$extended_attribute";
						$self->{'cache'}->{'labels'}->{"e_$field||$extended_attribute"} = $extended_attribute;
					}
				}
			}
		}
	}
	return \@isolate_list;
}

sub _get_scheme_fields {
	my ( $self, $options ) = @_;
	if ( !$self->{'cache'}->{'scheme_fields'} ) {
		my @scheme_field_list;
		my $set_id        = $self->get_set_id;
		my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my $scheme_fields = $self->{'datastore'}->get_all_scheme_fields;
		my $scheme_info   = $self->{'datastore'}->get_all_scheme_info;
		my $set_sql;
		if ($set_id) {
			$set_sql = $self->{'db'}->prepare("SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?");
		}
		foreach my $scheme (@$schemes) {
			my ( $scheme_id, $desc ) = ( $scheme->{'id'}, $scheme->{'description'} );
			my $scheme_db = $scheme_info->{$scheme_id}->{'dbase_name'};

			#No point using scheme fields if no scheme database is available.
			if ( $self->{'prefs'}->{'query_field_schemes'}->{$scheme_id} && $scheme_db ) {
				foreach my $field ( @{ $scheme_fields->{$scheme_id} } ) {
					if ( $self->{'prefs'}->{'query_field_scheme_fields'}->{$scheme_id}->{$field} ) {
						if ($set_id) {
							eval { $set_sql->execute( $set_id, $scheme_id ) };
							$logger->error($@) if $@;
							my ($set_name) = $set_sql->fetchrow_array;
							$desc = $set_name if defined $set_name;
						}
						( $self->{'cache'}->{'labels'}->{"s_$scheme_id\_$field"} = "$field ($desc)" ) =~ tr/_/ /;
						push @scheme_field_list, "s_$scheme_id\_$field";
					}
				}
			}
		}
		$self->{'cache'}->{'scheme_fields'} = \@scheme_field_list;
	}
	return $self->{'cache'}->{'scheme_fields'};
}

sub _print_footer {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $filename = $self->{'curate'} ? 'curate_footer.html' : 'footer.html';
	my $footer_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/$filename";
	$self->print_file($footer_file) if ( -e $footer_file );
	return;
}

sub print_file {
	my ( $self, $file, $ignore_hashlines ) = @_;
	my $lociAdd;
	my $loci;
	my $set_id = $self->get_set_id;
	my $set_string = $set_id ? "&amp;set_id=$set_id" : '';
	if ( $self->{'curate'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		if ( $self->is_admin ) {
			my $qry = "SELECT id FROM loci";
			if ($set_id) {
				$qry .= " WHERE id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE "
				  . "set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id)";
			}
			$loci = $self->{'datastore'}->run_list_query($qry);
		} else {
			my $set_clause =
			  $set_id
			  ? "AND (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
			  . "WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
			  : '';
			my $qry = "SELECT locus_curators.locus from locus_curators LEFT JOIN loci ON locus=id LEFT JOIN scheme_members on "
			  . "loci.id = scheme_members.locus WHERE locus_curators.curator_id=? $set_clause ORDER BY scheme_members.scheme_id,locus_curators.locus";
			$loci = $self->{'datastore'}->run_list_query( $qry, $self->get_curator_id );
		}
		my $first = 1;
		foreach my $locus ( uniq @$loci ) {
			my $cleaned = $self->clean_locus($locus);
			$lociAdd .= ' | ' if !$first;
			$lociAdd .= "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;"
			  . "table=sequences&amp;locus=$locus\">$cleaned</a>";
			$first = 0;
		}
	}
	if ( -e $file ) {
		my $system = $self->{'system'};
		open( my $fh, '<', $file ) or return;
		while (<$fh>) {
			next if /^#/ && $ignore_hashlines;
			s/\$instance/$self->{'instance'}/;
			s/\$webroot/$system->{'webroot'}/;
			s/\$dbase/$system->{'db'}/;
			s/\$indexpage/$system->{'indexpage'}/;
			if ( $self->{'curate'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
				if ( @$loci && @$loci < 30 ) {
					s/\$lociAdd/$lociAdd/;
				} else {
s/\$lociAdd/<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences">Add<\/a>/;
				}
			}
			if ( !$self->{'curate'} && $set_id ) {
				s/(bigsdb\.pl.*page=.+?)"/$1$set_string"/g;
				if ( ~/bigsdb\.pl/ && !/page=/ ) {
					s/(bigsdb\.pl.*)"/$1$set_string"/g;
				}
			}
			print;
		}
		close $fh;
	} else {
		$logger->warn("File $file does not exist.");
	}
	return;
}

sub get_filter {
	my ( $self, $name, $values, $options ) = @_;
	my $q = $self->{'cgi'};
	$options = {} if ref $options ne 'HASH';
	my $class = $options->{'class'} || 'filter';
	( my $text = $options->{'text'} || $name ) =~ tr/_/ /;
	my ( $label, $title ) = $self->get_truncated_label( "$text: ", undef, { capitalize_first => $options->{'capitalize_first'} } );
	my $title_attribute = $title ? "title=\"$title\"" : '';
	( my $id = "$name\_list" ) =~ tr/:/_/;
	my $buffer = "<label for=\"$id\" class=\"$class\" $title_attribute>$label</label>\n";
	unshift @$values, '' if !$options->{'noblank'};
	$options->{'labels'}->{''} = ' ';    #Required for HTML5 validation.
	my %args = ( -name => "$name\_list", -id => $id, -values => $values, -labels => $options->{'labels'}, -class => $class );

	if ( $options->{'multiple'} ) {
		$args{'-multiple'} = 'multiple';
		$args{'-size'} = ( @$values < 4 ) ? @$values : 4;
		my @selected = $q->param("$name\_list");
		$args{'-default'}  = \@selected;      #Not sure why this should be necessary, but only the first selection seems to stick.
		$args{'-override'} = 1;
		$args{'-class'}    = 'multiselect';
	}

	#Page::popup_menu faster than CGI::popup_menu as it doesn't escape values.
	$buffer .= ( $args{'-class'} // '' ) eq 'multiselect' ? $q->popup_menu(%args) : $self->popup_menu(%args);
	$options->{'tooltip'} =~ tr/_/ / if $options->{'tooltip'};
	$buffer .= " <a class=\"tooltip\" title=\"$options->{'tooltip'}\">&nbsp;<i>i</i>&nbsp;</a>" if $options->{'tooltip'};
	return $buffer;
}

sub get_user_filter {
	my ( $self, $field ) = @_;
	my $qry = "SELECT id,first_name,surname FROM users ";
	$qry .= $field eq 'curator' ? "WHERE (status = 'curator' OR status = 'admin') AND " : 'WHERE ';
	$qry .= 'id > 0';
	my $sql = $self->{'db'}->prepare($qry);
	my ( @usernames, %labels );
	my $status = $field eq 'curator' ? 'curator' : 'user';
	eval { $sql->execute };
	$logger->error($@) if $@;

	while ( my $data = $sql->fetchrow_hashref ) {
		push @usernames, $data->{'id'};
		$labels{ $data->{'id'} } = $data->{'surname'} eq 'applicable' ? 'not applicable' : "$data->{'surname'}, $data->{'first_name'}";
	}
	@usernames = sort { lc( $labels{$a} ) cmp lc( $labels{$b} ) } @usernames;
	my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
	return $self->get_filter(
		$field,
		\@usernames,
		{
			'labels' => \%labels,
			'tooltip' =>
			  "$field filter - Select $a_or_an $field to filter your search to only those records that match the selected $field."
		}
	);
}

sub get_number_records_control {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $self->{'cgi'}->param('displayrecs');
	}
	my $buffer = "<span style=\"white-space:nowrap\"><label for=\"displayrecs\" class=\"display\">Display: </label>\n"
	  . $self->{'cgi'}->popup_menu(
		-name   => 'displayrecs',
		-id     => 'displayrecs',
		-values => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $self->{'cgi'}->param('displayrecs') || $self->{'prefs'}->{'displayrecs'}
	  )
	  . " records per page <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather "
	  . "than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>&nbsp;&nbsp;</span>";
	return $buffer;
}

sub get_scheme_filter {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'schemes'} ) {
		my $set_id = $self->get_set_id;
		my $list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		foreach my $scheme (@$list) {
			push @{ $self->{'cache'}->{'schemes'} }, $scheme->{'id'};
			$self->{'cache'}->{'scheme_labels'}->{ $scheme->{'id'} } = $scheme->{'description'};
		}
		push @{ $self->{'cache'}->{'schemes'} }, 0;
		$self->{'cache'}->{'scheme_labels'}->{0} = 'No scheme';
	}
	my $buffer = $self->get_filter(
		'scheme_id',
		$self->{'cache'}->{'schemes'},
		{
			text    => 'scheme',
			labels  => $self->{'cache'}->{'scheme_labels'},
			tooltip => 'scheme filter - Select a scheme to filter your search to only those belonging to the selected scheme.'
		}
	);
	return $buffer;
}

sub get_locus_filter {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	my $buffer =
	  $self->get_filter( 'locus', $loci, { labels => $labels, tooltip => 'locus filter - Select a locus to filter your search by.' } );
	return $buffer;
}

sub get_old_version_filter {
	my ($self) = @_;
	my $buffer = $self->{'cgi'}->checkbox( -name => 'include_old', -id => 'include_old', -label => 'Include old record versions' );
	return $buffer;
}

sub get_isolate_publication_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( $self->{'config'}->{'ref_db'} ) {
		my $view = $self->{'system'}->{'view'};
		my $pmid =
		  $self->{'datastore'}->run_list_query("SELECT DISTINCT(pubmed_id) FROM refs RIGHT JOIN $view ON refs.isolate_id = $view.id");
		my $buffer;
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			if ( @$pmid && $options->{'any'} ) {
				unshift @values, 'none';
				$labels->{'none'} = 'not linked to any publication';
				unshift @values, 'any';
				$labels->{'any'} = 'linked to any publication';
			}
			return $self->get_filter(
				'publication',
				\@values,
				{
					labels   => $labels,
					text     => 'Publication',
					multiple => 1,
					noblank  => 1,
					tooltip  => "publication filter - Select publications to filter your search to only those isolates "
					  . "referred by them."
				}
			);
		}
	}
	return '';
}

sub get_project_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $sql =
	  $self->{'db'}->prepare( "SELECT id, short_description FROM projects WHERE id IN (SELECT project_id FROM project_members "
		  . "WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})) ORDER BY UPPER(short_description)" );
	eval { $sql->execute };
	$logger->error($@) if $@;
	my ( @project_ids, %labels );
	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @project_ids, $id;
		$labels{$id} = $desc;
	}
	if ( @project_ids && $options->{'any'} ) {
		unshift @project_ids, 'none';
		$labels{'none'} = 'not belonging to any project';
		unshift @project_ids, 'any';
		$labels{'any'} = 'belonging to any project';
	}
	if (@project_ids) {
		my $class   = $options->{'class'} || 'filter';
		my $tooltip = 'project filter - Select projects to filter your query to only those isolates belonging to them.';
		my $args    = { labels => \%labels, text => 'Project', tooltip => $tooltip, class => $class };
		if ( $options->{'multiple'} ) {
			$args->{'multiple'} = 1;
			$args->{'noblank'}  = 1;
		}
		return $self->get_filter( 'project', \@project_ids, $args );
	}
	return '';
}

sub get_experiment_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $experiment_list =
	  $self->{'datastore'}
	  ->run_query( "SELECT id,description FROM experiments ORDER BY description", undef, { fetch => 'all_arrayref', slice => {} } );
	my @experiments;
	my %labels;
	foreach (@$experiment_list) {
		push @experiments, $_->{'id'};
		$labels{ $_->{'id'} } = $_->{'description'};
	}
	if (@experiments) {
		my $class = $options->{'class'} || 'filter';
		return $self->get_filter(
			'experiment',
			\@experiments,
			{
				'labels'  => \%labels,
				'text'    => 'Experiment',
				'tooltip' => 'experiments filter - Only include sequences that have been linked to the specified experiment.',
				'class'   => $class
			}
		);
	}
}

sub get_sequence_method_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $class = $options->{'class'} || 'filter';
	return $self->get_filter(
		'seq_method',
		[SEQ_METHODS],
		{
			'text'    => 'Sequence method',
			'tooltip' => 'sequence method filter - Only include sequences generated from the selected method.',
			'class'   => $class
		}
	);
}

sub get_truncated_label {
	my ( $self, $label, $length, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$length //= 25;
	my $title;
	if ( length $label > $length ) {
		$title = $label;
		$title =~ tr/\"//;
		$label = substr( $label, 0, $length - 5 ) . "&hellip;";
	}
	if ( $options->{'capitalize_first'} && $label =~ /^[a-z]+\s+/ ) {    #only if first word is all lower case
		$label = ucfirst $label;
		$title = ucfirst $title if $title;
	}
	return ( $label, $title );
}

sub _normalize_clean_locus {
	my ( $self, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return join( ',', $locus, ( map { $_ => $options->{$_} } sort keys %$options ) );
}

sub clean_locus {
	my ( $self, $locus, $options ) = @_;
	return if !defined $locus;
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $set_id     = $self->get_set_id;
	if ($set_id) {
		my $set_locus =
		  $self->{'datastore'}
		  ->run_query( "SELECT * FROM set_loci WHERE set_id=? AND locus=?", [ $set_id, $locus ], { fetch => 'row_hashref' } );
		if ( $set_locus->{'set_name'} ) {
			$locus = $set_locus->{'set_name'};
			$locus = $set_locus->{'formatted_set_name'} if !$options->{'text_output'} && $set_locus->{'formatted_set_name'};
			if ( !$options->{'no_common_name'} ) {
				my $common_name = '';
				$common_name = " ($set_locus->{'set_common_name'})" if $set_locus->{'set_common_name'};
				$common_name = " ($set_locus->{'formatted_set_common_name'})"
				  if !$options->{'text_output'} && $set_locus->{'formatted_set_common_name'};
				$locus .= $common_name;
			}
		}
	} else {
		$locus = $locus_info->{'formatted_name'} if !$options->{'text_output'} && $locus_info->{'formatted_name'};
		$locus =~ s/^_//;    #locus names can't begin with a digit, so people can use an underscore, but this looks untidy in the interface.
		if ( !$options->{'no_common_name'} ) {
			my $common_name = '';
			$common_name = " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			$common_name = " ($locus_info->{'formatted_common_name'})"
			  if !$options->{'text_output'} && $locus_info->{'formatted_common_name'};
			$locus .= $common_name;
		}
	}
	if ( !$options->{'text_output'} ) {
		if ( ( $self->{'system'}->{'locus_superscript_prefix'} // '' ) eq 'yes' ) {
			$locus =~ s/^([A-Za-z]{1,3})_/<sup>$1<\/sup>/;
		}
		$locus =~ tr/_/ /;
		if ( $options->{'strip_links'} ) {
			$locus =~ s/<[a|A]\s+[href|HREF].+?>//g;
			$locus =~ s/<\/[a|A]>//g;
		}
	}
	return $locus;
}

sub get_set_id {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		my $set_id = $self->{'system'}->{'set_id'} // $self->{'prefs'}->{'set_id'};
		return $set_id if $set_id && BIGSdb::Utils::is_int($set_id);
	}
	if ( ( $self->{'system'}->{'only_sets'} // '' ) eq 'yes' && !$self->{'curate'} ) {
		if ( !$self->{'cache'}->{'set_list'} ) {
			$self->{'cache'}->{'set_list'} = $self->{'datastore'}->run_list_query("SELECT id FROM sets ORDER BY display_order,description");
		}
		return $self->{'cache'}->{'set_list'}->[0] if @{ $self->{'cache'}->{'set_list'} };
	}
	return;
}

sub extract_scheme_desc {
	my ( $self, $scheme_data ) = @_;
	my ( @scheme_ids, %desc );
	foreach (@$scheme_data) {
		push @scheme_ids, $_->{'id'};
		$desc{ $_->{'id'} } = $_->{'description'};
	}
	return ( \@scheme_ids, \%desc );
}

sub get_db_description {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'};
	return $desc if $self->{'system'}->{'sets'} && $self->{'system'}->{'set_id'};
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $desc_ref = $self->{'datastore'}->run_query( "SELECT * FROM sets WHERE id=?", $set_id, { fetch => 'row_hashref' } );
		$desc .= ' (' . $desc_ref->{'description'} . ')' if $desc_ref->{'description'} && !$desc_ref->{'hidden'};
	}
	$desc =~ s/\&/\&amp;/g;
	return $desc;
}

sub get_link_button_to_ref {
	my ( $self, $ref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	if ( !$self->{'sql'}->{'link_ref'} ) {
		my $qry = "SELECT COUNT(refs.isolate_id) FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id="
		  . "$self->{'system'}->{'view'}.id WHERE pubmed_id=?";
		$self->{'sql'}->{'link_ref'} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'link_ref'}->execute($ref) };
	$logger->error($@) if $@;
	my ($count) = $self->{'sql'}->{'link_ref'}->fetchrow_array;
	my $plural = $count == 1 ? '' : 's';
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form( -style => 'display:inline' );
	$q->param( curate => 1 ) if $self->{'curate'};
	$q->param( pmid   => $ref );
	$q->param( page   => 'pubquery' );
	$buffer .= $q->hidden($_) foreach qw(db page curate pmid);
	$buffer .= $q->submit( -value => "$count isolate$plural", -class => $options->{'class'} // 'smallbutton' );
	$buffer .= $q->end_form;
	$q->param( page => 'info' );
	return $buffer;
}

sub get_isolate_name_from_id {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'isolate_id'} ) {
		my $view        = $self->{'system'}->{'view'};
		my $label_field = $self->{'system'}->{'labelfield'};
		$self->{'sql'}->{'isolate_id'} = $self->{'db'}->prepare("SELECT $view.$label_field FROM $view WHERE id=?");
	}
	eval { $self->{'sql'}->{'isolate_id'}->execute($isolate_id) };
	$logger->error($@) if $@;
	my ($isolate) = $self->{'sql'}->{'isolate_id'}->fetchrow_array;
	return $isolate // '';
}

sub get_isolate_id_and_name_from_seqbin_id {
	my ( $self, $seqbin_id ) = @_;
	my $view        = $self->{'system'}->{'view'};
	my $label_field = $self->{'system'}->{'labelfield'};
	return $self->{'datastore'}
	  ->run_query( "SELECT $view.id,$view.$label_field FROM $view LEFT JOIN sequence_bin ON $view.id = isolate_id WHERE sequence_bin.id=?",
		$seqbin_id, { cache => 'Page::get_isolate_id_and_name_from_seqbin_id' } );
}

sub get_isolates_with_seqbin {

	#Return list and formatted labels
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $view = $self->{'system'}->{'view'};
	my $qry;
	if ( $options->{'use_all'} ) {
		$qry = "SELECT $view.id,$view.$self->{'system'}->{'labelfield'},new_version FROM $view ORDER BY $view.id";
	} else {
		$qry = "SELECT $view.id,$view.$self->{'system'}->{'labelfield'},new_version FROM $view WHERE EXISTS (SELECT * FROM seqbin_stats "
		  . "WHERE $view.id=seqbin_stats.isolate_id) ORDER BY $view.id";
	}
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	my @ids;
	my %labels;
	foreach (@$data) {
		my ( $id, $isolate, $new_version ) = @$_;
		push @ids, $id;
		$labels{$id} = $new_version ? "$id) $isolate [old version]" : "$id) $isolate";
	}
	return ( \@ids, \%labels );
}

sub get_record_name {
	my ( $self, $table ) = @_;
	$table ||= '';
	my %names = (
		users                             => 'user',
		user_groups                       => 'user group',
		user_group_members                => 'user group member',
		loci                              => 'locus',
		refs                              => 'PubMed link',
		allele_designations               => 'allele designation',
		scheme_members                    => 'scheme member',
		schemes                           => 'scheme',
		scheme_fields                     => 'scheme field',
		composite_fields                  => 'composite field',
		composite_field_values            => 'composite field value',
		isolates                          => 'isolate',
		sequences                         => 'allele sequence',
		accession                         => 'accession number',
		sequence_refs                     => 'PubMed link',
		profiles                          => 'profile',
		sequence_bin                      => 'sequence (contig)',
		allele_sequences                  => 'allele sequence tag',
		isolate_aliases                   => 'isolate alias',
		locus_aliases                     => 'locus alias',
		curator_permissions               => 'curator permission record',
		isolate_user_acl                  => 'isolate access control record',
		isolate_usergroup_acl             => 'isolate group access control record',
		client_dbases                     => 'client database',
		client_dbase_loci                 => 'locus to client database definition',
		client_dbase_schemes              => 'scheme to client database definition',
		locus_extended_attributes         => 'locus extended attribute',
		projects                          => 'project description',
		project_members                   => 'project member',
		profile_refs                      => 'Pubmed link',
		samples                           => 'sample storage record',
		scheme_curators                   => 'scheme curator access record',
		locus_curators                    => 'locus curator access record',
		experiments                       => 'experiment',
		experiment_sequences              => 'experiment sequence link',
		isolate_field_extended_attributes => 'isolate field extended attribute',
		isolate_value_extended_attributes => 'isolate field extended attribute value',
		locus_descriptions                => 'locus description',
		scheme_groups                     => 'scheme group',
		scheme_group_scheme_members       => 'scheme group scheme member',
		scheme_group_group_members        => 'scheme group group member',
		pcr                               => 'PCR reaction',
		pcr_locus                         => 'PCR locus link',
		probes                            => 'nucleotide probe',
		probe_locus                       => 'probe locus link',
		client_dbase_loci_fields          => 'locus to client database isolate field definition',
		sets                              => 'set',
		set_loci                          => 'set member locus',
		set_schemes                       => 'set member schemes',
		set_metadata                      => 'set metadata',
		set_view                          => 'database view linked to set',
		history                           => 'update record',
		profile_history                   => 'profile update record',
		sequence_attributes               => 'sequence attribute'
	);
	return $names{$table};
}

sub rewrite_query_ref_order_by {
	my ( $self, $qry_ref ) = @_;
	my $view = $self->{'system'}->{'view'};
	if ( $$qry_ref =~ /ORDER BY s_(\d+)_\S+\s/ ) {
		my $scheme_id            = $1;
		my $isolate_scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $scheme_join          = "LEFT JOIN $isolate_scheme_table AS ordering ON $view.id=ordering.id";
		$$qry_ref =~ s/(SELECT \.* FROM $view)/$1 $scheme_join/;
		$$qry_ref =~ s/FROM $view/FROM $view $scheme_join/;
		$$qry_ref =~ s/ORDER BY s_(\d+)_/ORDER BY ordering\./;
	} elsif ( $$qry_ref =~ /ORDER BY l_(\S+)\s/ ) {
		my $locus      = $1;
		my $locus_join = $self->_create_join_sql_for_locus($locus);
		( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
		$$qry_ref =~ s/(SELECT .* FROM $view)/$1 $locus_join/;
		$$qry_ref =~
s/FROM $view/FROM $view LEFT JOIN allele_designations AS ordering ON ordering.isolate_id=$view.id AND ordering.locus=E'$cleaned_locus'/;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$$qry_ref =~ s/ORDER BY l_\S+\s/ORDER BY CAST(ordering.allele_id AS int) /;
		} else {
			$$qry_ref =~ s/ORDER BY l_\S+\s/ORDER BY ordering.allele_id /;
		}
	} elsif ( $$qry_ref =~ /ORDER BY f_(\S+)/ ) {
		my $field = $1;
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		if ( defined $metaset ) {
			my $metafield_join = $self->_create_join_sql_for_metafield($metaset);
			$$qry_ref =~ s/(SELECT \.* FROM $view)/$1 $metafield_join/;
			$$qry_ref =~ s/FROM $view/FROM $view $metafield_join/;
			$$qry_ref =~ s/ORDER BY f_$field/ORDER BY ordering\.$metafield/;
		} else {
			$$qry_ref =~ s/ORDER BY f_/ORDER BY $view\./;
		}
	}
	return;
}

sub is_allowed_to_view_isolate {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'allowed_to_view'} ) {
		$self->{'sql'}->{'allowed_to_view'} =
		  $self->{'db'}->prepare("SELECT EXISTS (SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)");
	}
	eval { $self->{'sql'}->{'allowed_to_view'}->execute($isolate_id) };
	$logger->error($@) if $@;
	my $allowed_to_view = $self->{'sql'}->{'allowed_to_view'}->fetchrow_array;
	return $allowed_to_view;
}

sub _create_join_sql_for_locus {
	my ( $self, $locus ) = @_;
	( my $clean_locus_name = $locus ) =~ s/'/_PRIME_/g;
	$clean_locus_name =~ s/-/_/g;
	( my $escaped_locus = $locus ) =~ s/'/\\'/g;
	my $qry = " LEFT JOIN allele_designations AS l_$clean_locus_name ON l_$clean_locus_name\.isolate_id=$self->{'system'}->{'view'}.id "
	  . "AND l_$clean_locus_name.locus=E'$escaped_locus'";
	return $qry;
}

sub _create_join_sql_for_metafield {
	my ( $self, $metaset ) = @_;
	my $qry = " LEFT JOIN meta_$metaset AS ordering ON ordering.isolate_id = $self->{'system'}->{'view'}.id";
	return $qry;
}

sub get_update_details_tooltip {
	my ( $self, $locus, $allele_ref ) = @_;
	my $buffer;
	my $sender  = $self->{'datastore'}->get_user_info( $allele_ref->{'sender'} );
	my $curator = $self->{'datastore'}->get_user_info( $allele_ref->{'curator'} );
	$buffer = "$locus:$allele_ref->{'allele_id'} - ";
	$buffer .= "sender: $sender->{'first_name'} $sender->{'surname'}<br />";
	$buffer .= "status: $allele_ref->{'status'}<br />" if $allele_ref->{'status'};
	$buffer .= "method: $allele_ref->{'method'}<br />";
	$buffer .= "curator: $curator->{'first_name'} $curator->{'surname'}<br />";
	$buffer .= "first entered: $allele_ref->{'date_entered'}<br />";
	$buffer .= "last updated: $allele_ref->{'datestamp'}<br />";
	$buffer .= "comments: $allele_ref->{'comments'}<br />"
	  if $allele_ref->{'comments'};
	return $buffer;
}

sub _get_seq_detail_tooltip_text {
	my ( $self, $locus, $allele_designations, $allele_sequences, $flags_ref ) = @_;
	my @allele_ids;
	push @allele_ids, $_->{'allele_id'} foreach @$allele_designations;
	local $" = ', ';
	my $buffer = @allele_ids ? "$locus:@allele_ids - " : "$locus - ";
	my $i = 0;
	local $" = '; ';
	foreach (@$allele_sequences) {
		$buffer .= '<br />'      if $i;
		$buffer .= "Seqbin id:$_->{'seqbin_id'}: $_->{'start_pos'} &rarr; $_->{'end_pos'}";
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

sub get_seq_detail_tooltips {

	#With 'get_all' passed as an option, all the designations and tags are retrieved (once only) and cached for future use.
	#This is much more efficient when this method is called hundreds or thousands of times for a particular isolate, e.g. for
	#the isolate info page.  It will be slower if the results for only a few loci are required, especially if this involves
	#multiple isolates e.g. for a query results table.
	my ( $self, $isolate_id, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer           = '';
	my $allele_sequences = [];
	if ( $options->{'get_all'} ) {
		if ( !$self->{'cache'}->{'allele_sequences'}->{$isolate_id} ) {
			$self->{'cache'}->{'allele_sequences'}->{$isolate_id} =
			  $self->{'datastore'}->get_all_allele_sequences( $isolate_id, { keys => [qw(locus id)] } );
		}
		my $locus_allele_sequences = $self->{'cache'}->{'allele_sequences'}->{$isolate_id}->{$locus};
		foreach my $allele_sequence_id (
			sort { $locus_allele_sequences->{$a}->{'complete'} cmp $locus_allele_sequences->{$b}->{'complete'} }
			keys %$locus_allele_sequences
		  )
		{
			push @$allele_sequences, $locus_allele_sequences->{$allele_sequence_id};
		}
	} else {
		$allele_sequences = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
	}
	my $designations = [];
	if ( $options->{'get_all'} ) {
		if ( !$self->{'cache'}->{'allele_designations'}->{$isolate_id} ) {
			$self->{'cache'}->{'allele_designations'}->{$isolate_id} = $self->{'datastore'}->get_all_allele_designations($isolate_id);
		}
		my $locus_allele_designations = $self->{'cache'}->{'allele_designations'}->{$isolate_id}->{$locus};
		no warnings 'numeric';    #sort by status, then by numeric values, then by alphabetical value.
		foreach my $allele_id (
			sort { $locus_allele_designations->{$a} cmp $locus_allele_designations->{$b} || $a <=> $b || $a cmp $b }
			keys %$locus_allele_designations
		  )
		{
			push @$designations, { allele_id => $allele_id };
		}
	} else {
		$designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $designation_flags;
	my ( @all_flags, %flag_from_designation, %flag_from_alleleseq );
	if ( $options->{'allele_flags'} && $locus_info->{'flag_table'} ) {
		foreach my $designation (@$designations) {
			$designation_flags = $self->{'datastore'}->get_locus($locus)->get_flags( $designation->{'allele_id'} );
			push @all_flags, @$designation_flags;
			$flag_from_designation{$_} = 1 foreach @$designation_flags;
		}
	}
	my ( @flags_foreach_alleleseq, $complete );
	if (@$allele_sequences) {
		if ( $options->{'get_all'} ) {
			if ( !$self->{'sequence_flags_returned'} ) {
				$self->{'cache'}->{'sequence_flags'}->{$isolate_id} = $self->{'datastore'}->get_all_sequence_flags($isolate_id);
				$self->{'sequence_flags_returned'} = 1;
			}
			my $isolate_flags = $self->{'cache'}->{'sequence_flags'}->{$isolate_id};
			foreach my $alleleseq (@$allele_sequences) {
				foreach my $flag ( keys %{ $isolate_flags->{ $alleleseq->{'id'} } } ) {
					push @flags_foreach_alleleseq, $flag;
					push @all_flags,               $flag;
					$flag_from_alleleseq{$flag} = 1;
				}
				$complete = 1 if $alleleseq->{'complete'};
			}
		} else {
			foreach my $alleleseq (@$allele_sequences) {
				my $flaglist_ref = $self->{'datastore'}->get_sequence_flags( $alleleseq->{'id'} );
				push @flags_foreach_alleleseq, $flaglist_ref;
				push @all_flags,               @$flaglist_ref;
				$flag_from_alleleseq{$_} = 1 foreach @$flaglist_ref;
				$complete = 1 if $alleleseq->{'complete'};
			}
		}
	}
	@all_flags = uniq sort @all_flags;
	my $cleaned_locus = $self->clean_locus( $locus, { text_output => 1 } );
	my $sequence_tooltip =
	  $self->_get_seq_detail_tooltip_text( $cleaned_locus, $designations, $allele_sequences, \@flags_foreach_alleleseq );
	if (@$allele_sequences) {
		my $sequence_class = $complete ? 'sequence_tooltip' : 'sequence_tooltip_incomplete';
		$buffer .=
		    qq(<span style="font-size:0.2em"> </span><a class="$sequence_class" title="$sequence_tooltip" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleSequence&amp;id=$isolate_id&amp;)
		  . qq(locus=$locus">&nbsp;S&nbsp;</a>);
	}
	if (@all_flags) {
		my $text = "Flags - ";
		foreach my $flag (@all_flags) {
			$text .= "$flag";
			if ( $options->{'allele_flags'} ) {
				if ( $flag_from_designation{$flag} && !$flag_from_alleleseq{$flag} ) {
					$text .= " (allele designation)<br />";
				} elsif ( !$flag_from_designation{$flag} && $flag_from_alleleseq{$flag} ) {
					$text .= " (sequence tag)<br />";
				} else {
					$text .= " (designation + tag)<br />";
				}
			} else {
				$text .= '<br />';
			}
		}
		local $" = "</a> <a class=\"seqflag_tooltip\" title=\"$text\">";
		$buffer .= "<a class=\"seqflag_tooltip\" title=\"$text\">@all_flags</a>";
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
	open( my $fh, '>:encoding(utf8)', $full_file_path ) || $logger->error("Can't open $full_file_path for writing");
	local $" = "\n";
	print $fh "@list";
	close $fh;
	return $filename;
}

sub get_query_from_temp_file {
	my ( $self, $file ) = @_;
	return if !defined $file;
	$file = $file =~ /([\w\.]+)/ ? $1 : undef;    #untaint
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$file";
	if ( -e $full_path ) {
		open( my $fh, '<:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for reading");
		my $qry = <$fh>;
		close $fh;
		return $qry;
	}
	return;
}

sub mark_cache_stale {

	#Mark all cache subdirectories as stale (each locus set will use a different directory)
	my ($self) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}";
	if ( -d $dir ) {
		foreach my $subdir ( glob "$dir/*" ) {
			next if !-d $subdir;    #skip if not a dirctory
			if ( $subdir =~ /\/(all|\d+)$/ ) {
				$subdir = $1;
				my $stale_flag_file = "$dir/$subdir/stale";
				open( my $fh, '>', $stale_flag_file ) || $logger->error("Can't mark BLAST db stale.");
				close $fh;
			}
		}
	}
	return;
}

sub is_admin {
	my ($self) = @_;
	if ( $self->{'username'} ) {
		my $status =
		  $self->{'datastore'}
		  ->run_query( "SELECT status FROM users WHERE user_name=?", $self->{'username'}, { cache => 'Page::is_admin' } );
		return 0 if !$status;
		return 1 if $status eq 'admin';
	}
	return 0;
}

sub can_modify_table {
	my ( $self, $table ) = @_;
	my $scheme_id = $self->{'cgi'}->param('scheme_id');
	my $locus     = $self->{'cgi'}->param('locus');
	return 0 if $table eq 'history' || $table eq 'profile_history';
	return 1 if $self->is_admin;
	if ( $table eq 'users' && $self->{'permissions'}->{'modify_users'} ) {
		return 1;
	} elsif ( ( $table eq 'user_groups' || $table eq 'user_group_members' ) && $self->{'permissions'}->{'modify_usergroups'} ) {
		return 1;
	} elsif (
		$self->{'system'}->{'dbtype'} eq 'isolates' && (
			any {
				$table eq $_;
			}
			qw(isolates isolate_aliases refs)
		)
		&& $self->{'permissions'}->{'modify_isolates'}
	  )
	{
		return 1;
	} elsif ( ( $table eq 'isolate_user_acl' || $table eq 'isolate_usergroup_acl' ) && $self->{'permissions'}->{'modify_isolates_acl'} ) {
		return 1;
	} elsif ( ( $table eq 'allele_designations' )
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
			return $self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id );
		}
	} elsif ( $table eq 'allele_sequences' && $self->{'permissions'}->{'tag_sequences'} ) {
		return 1;
	} elsif ( $table eq 'profile_refs' ) {
		my $allowed =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM scheme_curators WHERE curator_id=?)", $self->get_curator_id );
		return $allowed;
	} elsif ( ( $table eq 'profiles' || $table eq 'profile_fields' || $table eq 'profile_members' ) ) {
		return 0 if !$scheme_id;
		my $allowed = $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM scheme_curators WHERE scheme_id=? AND curator_id=?)",
			[ $scheme_id, $self->get_curator_id ] );
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
	} elsif ( ( $table eq 'projects' || $table eq 'project_members' ) && $self->{'permissions'}->{'modify_projects'} ) {
		return 1;
	} elsif ( $table eq 'samples' && $self->{'permissions'}->{'sample_management'} && @{ $self->{'xmlHandler'}->get_sample_field_list } ) {
		return 1;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'sequence_refs' || $table eq 'accession' ) ) {
		my $allowed =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM locus_curators WHERE curator_id=?)", $self->get_curator_id );
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
		say qq(<div style="text-align:center"><img src="$self->{'system'}->{'webroot'}/images/warning_sign.gif" alt="Warning!" /></div>);
	} else {
		$image = "$ENV{'DOCUMENT_ROOT'}/images/warning_sign.gif";
		if ( -e $image ) {
			say qq(<div style="text-align:center"><img src="/images/warning_sign.gif" alt="Warning!" /></div>);
		}
	}
	return;
}

sub get_curator_id {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'curator_id'} ) {
		if ( $self->{'username'} ) {
			my $qry = "SELECT id,status FROM users WHERE user_name=?";
			my $values = $self->{'datastore'}->run_query( $qry, $self->{'username'}, { fetch => 'row_hashref' } );
			return 0 if ref $values ne 'HASH';
			if (   $values->{'status'}
				&& $values->{'status'} ne 'curator'
				&& $values->{'status'} ne 'admin' )
			{
				$self->{'cache'}->{'curator_id'} = 0;
			} else {
				$self->{'cache'}->{'curator_id'} = $values->{'id'};
			}
		} else {
			$self->{'cache'}->{'curator_id'} = 0;
		}
	}
	return $self->{'cache'}->{'curator_id'};
}

sub isolate_exists {
	my ( $self, $id ) = @_;
	return $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'} WHERE id=?)", $id, { cache => 'Page::isolate_exists' } );
}

sub initiate_prefs {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'prefstore'};
	my ( $general_prefs, $field_prefs, $scheme_field_prefs );
	my $guid = $self->get_guid || 1;
	try {
		$self->{'prefstore'}->update_datestamp($guid);
	}
	catch BIGSdb::PrefstoreConfigurationException with {
		undef $self->{'prefstore'};
		$self->{'fatal'} = 'prefstoreConfig';
	};
	if ( ( $q->param('page') // '' ) eq 'options' && $q->param('set') ) {
		foreach (qw(displayrecs pagebar alignwidth flanking)) {
			$self->{'prefs'}->{$_} = $q->param($_);
		}

		#Switches
		foreach (qw (hyperlink_loci tooltips)) {
			$self->{'prefs'}->{$_} = ( $q->param($_) && $q->param($_) eq 'on' ) ? 1 : 0;
		}
		return if !$self->{'prefstore'};
		$self->{'prefs'}->{'set_id'} = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'set_id' )
		  if $self->{'pref_requirements'}->{'general'};
	} else {
		return if !$self->{'pref_requirements'}->{'general'} && !$self->{'pref_requirements'}->{'query_field'};
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
			$self->{'prefs'}->{'set_id'}      = $general_prefs->{'set_id'};

			#default off
			foreach (qw (hyperlink_loci )) {
				$general_prefs->{$_} ||= 'off';
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'on' ? 1 : 0;
			}

			#default on
			foreach (qw (tooltips)) {
				$general_prefs->{$_} ||= 'on';
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'off' ? 0 : 1;
			}
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_initiate_isolatedb_prefs( $general_prefs, $field_prefs, $scheme_field_prefs );
	}

	#Set dropdown status for scheme fields
	if ( $self->{'pref_requirements'}->{'query_field'} ) {
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
	return;
}

sub _initiate_isolatedb_prefs {
	my ( $self, $general_prefs, $field_prefs, $scheme_field_prefs ) = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $params        = $q->Vars;
	my $extended      = $self->get_extended_attributes;

	#Parameters set by preference store via session cookie
	if (   $params->{'page'} eq 'options'
		&& $params->{'set'} )
	{
		#Switches
		foreach (
			qw ( update_details sequence_details allele_flags mark_provisional mark_provisional_main sequence_details_main
			display_seqbin_main display_contig_count locus_alias scheme_members_alias sample_details)
		  )
		{
			$self->{'prefs'}->{$_} = $params->{$_} ? 1 : 0;
		}
		foreach (@$field_list) {
			if ( $_ ne 'id' ) {
				$self->{'prefs'}->{'maindisplayfields'}->{$_} = $params->{"field_$_"}     ? 1 : 0;
				$self->{'prefs'}->{'dropdownfields'}->{$_}    = $params->{"dropfield_$_"} ? 1 : 0;
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						$self->{'prefs'}->{'maindisplayfields'}->{"$_\..$extended_attribute"} =
						  $params->{"extended_$_\..$extended_attribute"} ? 1 : 0;
						$self->{'prefs'}->{'dropdownfields'}->{"$_\..$extended_attribute"} =
						  $params->{"dropfield_e_$_\..$extended_attribute"} ? 1 : 0;
					}
				}
			}
		}
		$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $params->{"field_aliases"} ? 1 : 0;
		my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
		foreach (@$composites) {
			$self->{'prefs'}->{'maindisplayfields'}->{$_} = $params->{"field_$_"} ? 1 : 0;
		}
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		$self->{'prefs'}->{'dropdownfields'}->{'Publications'} = $params->{"dropfield_Publications"} ? 1 : 0;
		foreach (@$schemes) {
			my $field = "scheme_$_\_profile_status";
			$self->{'prefs'}->{'dropdownfields'}->{$field} = $params->{"dropfield_$field"} ? 1 : 0;
		}
	} else {
		my $guid             = $self->get_guid || 1;
		my $dbname           = $self->{'system'}->{'db'};
		my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
		if ( $self->{'pref_requirements'}->{'general'} ) {

			#default off
			foreach (
				qw (update_details allele_flags scheme_members_alias sequence_details_main
				display_seqbin_main display_contig_count locus_alias)
			  )
			{
				$general_prefs->{$_} ||= 'off';
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'on' ? 1 : 0;
			}

			#default on
			foreach (qw (sequence_details sample_details mark_provisional mark_provisional_main)) {
				$general_prefs->{$_} ||= 'on';
				$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'off' ? 0 : 1;
			}
		}
		if ( $self->{'pref_requirements'}->{'query_field'} ) {
			foreach (@$field_list) {
				next if $_ eq 'id';
				if ( defined $field_prefs->{$_}->{'dropdown'} ) {
					$self->{'prefs'}->{'dropdownfields'}->{$_} = $field_prefs->{$_}->{'dropdown'};
				} else {
					$field_attributes->{$_}->{'dropdown'} ||= 'no';
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
			if ( defined $field_prefs->{'Publications'}->{'dropdown'} ) {
				$self->{'prefs'}->{'dropdownfields'}->{'Publications'} = $field_prefs->{'Publications'}->{'dropdown'};
			} else {
				$self->{'prefs'}->{'dropdownfields'}->{'Publications'} =
				  ( $self->{'system'}->{'no_publication_filter'} // '' ) eq 'yes' ? 0 : 1;
			}
		}
		if ( $self->{'pref_requirements'}->{'main_display'} ) {
			if ( defined $field_prefs->{'aliases'}->{'maindisplay'} ) {
				$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $field_prefs->{'aliases'}->{'maindisplay'};
			} else {
				$self->{'system'}->{'maindisplay_aliases'} ||= 'no';
				$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 1 : 0;
			}
			foreach (@$field_list) {
				next if $_ eq 'id';
				if ( defined $field_prefs->{$_}->{'maindisplay'} ) {
					$self->{'prefs'}->{'maindisplayfields'}->{$_} = $field_prefs->{$_}->{'maindisplay'};
				} else {
					$field_attributes->{$_}->{'maindisplay'} ||= 'yes';
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
			eval { $sql->execute };
			$logger->logdie($@) if $@;
			while ( my ( $id, $main_display ) = $sql->fetchrow_array ) {
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
		eval { $locus_sql->execute };
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
				if ( defined $prefstore_values->{ $_->[0] }->{$action} ) {
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
	return;
}

sub initiate_view {
	my ( $self, $username, $curate ) = @_;
	return if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $set_id = $self->get_set_id;
	if ( defined $self->{'system'}->{'view'} && $set_id ) {
		if ( $self->{'system'}->{'views'} && BIGSdb::Utils::is_int($set_id) ) {
			my $view_ref = $self->{'datastore'}->run_simple_query( "SELECT view FROM set_view WHERE set_id=?", $set_id );
			$self->{'system'}->{'view'} = $view_ref->[0] if ref $view_ref eq 'ARRAY';
		}
	}
	if ( $username && ( $self->{'system'}->{'read_access'} eq 'acl' || ( ( $self->{'system'}->{'write_access'} // '' ) eq 'acl' ) ) ) {

		#create view containing only isolates that are allowed to be viewed by user
		my $status_ref = $self->{'datastore'}->run_simple_query( "SELECT status FROM users WHERE user_name=?", $username );
		return if ref $status_ref ne 'ARRAY' || $status_ref->[0] eq 'admin';

		#You need to be able to read and write to a record to view it in the curator's interface
		my $write_clause = $curate ? ' AND write=true' : '';
		my $view_clause = << "SQL";
SELECT * FROM $self->{'system'}->{'view'} WHERE id IN (SELECT isolate_id FROM isolate_user_acl 
LEFT JOIN users ON isolate_user_acl.user_id = users.id WHERE user_name='$username' AND read$write_clause) OR 
id IN (SELECT isolate_id FROM isolate_usergroup_acl LEFT JOIN user_group_members 
ON user_group_members.user_group=isolate_usergroup_acl.user_group_id LEFT JOIN users 
ON user_group_members.user_id=users.id WHERE users.user_name ='$username' AND read$write_clause)
SQL
		eval { $self->{'db'}->do("CREATE TEMP VIEW tmp_userview AS $view_clause") };
		if ($@) {
			$logger->error("Can't create user view $@");
			$self->{'db'}->rollback;
		} else {
			$self->{'system'}->{'view'} = 'tmp_userview';
		}
	}
	return;
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
	$var =~ tr/:/_/;
	return $var;
}

sub get_all_foreign_key_fields_and_labels {

	#returns arrayref of fields needed to order label and a hashref of labels
	my ( $self, $attribute_hashref ) = @_;
	my @fields;
	my @values = split /\|/, $attribute_hashref->{'labels'};
	foreach (@values) {
		if ( $_ =~ /\$(.*)/ ) {
			push @fields, $1;
		}
	}
	local $" = ',';
	my $qry = "select id,@fields from $attribute_hashref->{'foreign_key'}";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %desc;
	while ( my $data = $sql->fetchrow_hashref ) {
		my $temp = $attribute_hashref->{'labels'};
		foreach (@fields) {
			$temp =~ s/$_/$data->{$_}/;
		}
		$temp =~ s/[\|\$]//g;
		$desc{ $data->{'id'} } = $temp;
	}
	return ( \@fields, \%desc );
}

sub textfield {

	#allow HTML5 attributes (use instead of CGI->textfield)
	my ( $self, %args ) = @_;
	foreach ( keys %args ) {
		( my $stripped_key = $_ ) =~ s/^\-//;
		$args{$stripped_key} = delete $args{$_};    #strip off initial dash in key so can be used as drop-in replacement for CGI->textfield
	}
	if ( ( $args{'type'} // '' ) eq 'number' ) {
		delete @args{qw(size maxlength)};
	}
	$args{'type'} //= 'text';
	my $args_string;
	foreach ( keys %args ) {
		$args{$_} //= '';
		$args_string .= qq/$_="$args{$_}" /;
	}
	my $buffer = "<input $args_string/>";
	return $buffer;
}

sub popup_menu {

	#Faster than CGI::popup_menu when listing thousands of values as it doesn't need to escape all values
	my ( $self, %args ) = @_;
	my ( $name, $id, $values, $labels, $default, $class, $multiple, $size ) =
	  @args{qw ( -name -id -values -labels -default -class -multiple -size)};
	my $q     = $self->{'cgi'};
	my $value = $q->param($name);
	$value =~ s/"/&quot;/g if defined $value;
	my %default = ref $default eq 'ARRAY' ? map { $_ => 1 } @$default : ();
	$default{$value} = 1 if defined $value;
	my $buffer = qq(<select name="$name");
	$buffer .= qq( class="$class")      if defined $class;
	$buffer .= qq( id="$id")            if defined $id;
	$buffer .= qq( size="$size")        if defined $size;
	$buffer .= qq( multiple="multiple") if ( $multiple // '' ) eq 'true';
	$buffer .= ">\n";

	foreach (@$values) {
		s/"/&quot;/g;
		$labels->{$_} //= $_;
		my $select = $default{$_} ? qq( selected="selected") : '';
		$buffer .= qq(<option value="$_"$select>$labels->{$_}</option>\n);
	}
	$buffer .= "</select>\n";
	return $buffer;
}
1;
