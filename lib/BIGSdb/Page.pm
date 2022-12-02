#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
use BIGSdb::Exceptions;
use Try::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(uniq none);
use JSON;
use BIGSdb::Constants qw(:interface :limits :scheme_flags :login_requirements :design SEQ_METHODS);
use autouse 'Data::Dumper' => qw(Dumper);

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'prefs'} = {};
	$logger->logdie('No CGI object passed')     if !$self->{'cgi'};
	$logger->logdie('No system hashref passed') if !$self->{'system'};
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

sub need_openlayers {
	my ($self) = @_;
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	foreach my $field ( keys %$field_attributes ) {
		if ( $field_attributes->{$field}->{'type'} eq 'geography_point'
			|| ( $field_attributes->{$field}->{'geography_point_lookup'} // q() ) eq 'yes' )
		{
			return 1;
		}
	}
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 1, isolate_display => 1, analysis => 1, query_field => 1 };
	return;
}

#Override by returning javascript code to include in header
sub get_javascript {
	return q();    #Empty string
}

sub _get_cookie_js {
	my ($self) = @_;
	return q() if $self->{'config'}->{'no_cookie_consent'} || $self->{'curate'} || !$self->{'instance'};
	return q() if !$self->{'instance'} || !$self->{'system'}->{'script_name'};
	return <<"JS";
window.addEventListener("load", function(){
window.cookieconsent.utils.isMobile = () => false; //Don't float on mobile devices.
window.cookieconsent.initialise({
  "palette": {
    "popup": {
      "background": "#237afc"
    },
    "button": {
      "background": "#fff",
      "text": "#237afc"
    }
  },
  "theme": "classic",
  "content": {
    "message": "This website requires the use of cookies for authentication and storing user preferences.",
    "href": "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=cookies"
   }
})});	
JS
}

sub get_list_javascript {
	my ($self)          = @_;
	my $list_url        = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=idList";
	my $list_genome_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=idList&genomes=1";
	my $js              = <<"JS";
function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").prop("selected",isSelect);
}

function listbox_clear(listID) {
	\$("#" + listID).val("");
}

function listbox_listall(listID) {
	\$.ajax({
    	url : "$list_url",
		dataType: "text",
		success : function (data) {
			\$("#" + listID).val(data);
		}
	});
}

function listbox_listgenomes(listID) {
	\$.ajax({
    	url : "$list_genome_url",
		dataType: "text",
		success : function (data) {
			\$("#" + listID).val(data);
		}
	});
}	

function isolate_list_show() {
	\$("#isolate_paste_list_div").show(500);
	\$("#isolate_list_show_button").hide(0);
	\$("#isolate_list_hide_button").show(0);
}

function isolate_list_hide() {
	\$("#isolate_paste_list_div").hide(500);
	\$("#isolate_paste_list").val('');
	\$("#isolate_list_show_button").show(0);
	\$("#isolate_list_hide_button").hide(0);
}

function locus_list_show() {
	\$("#locus_paste_list_div").show(500);
	\$("#locus_list_show_button").hide(0);
	\$("#locus_list_hide_button").show(0);
}

function locus_list_hide() {
	\$("#locus_paste_list_div").hide(500);
	\$("#locus_paste_list").val('');
	\$("#locus_list_show_button").show(0);
	\$("#locus_list_hide_button").hide(0);
}
JS
	return $js;
}

sub _get_javascript_paths {
	my ($self) = @_;
	my $page_js = $self->get_javascript;
	$page_js .= $self->_get_cookie_js;
	my $js = [];
	my $relative_js_path = $self->{'config'}->{'relative_js_dir'} // '/javascript';
	if ( $self->{'jQuery'} ) {
		push @$js, { src => "$relative_js_path/jquery.min.js",    version => '3.6.0' };
		push @$js, { src => "$relative_js_path/jquery-ui.min.js", defer   => 1, version => '1.12.1' };
		push @$js, { src => "$relative_js_path/bigsdb.min.js",    defer   => 1, version => '20210628' };
		if ( !$self->{'config'}->{'no_cookie_consent'} && !$self->{'curate'} && $self->{'instance'} ) {
			push @$js, { src => "$relative_js_path/cookieconsent.min.js", defer => 1 };
		}
		my $features = {
			'jQuery.tablesort'      => { src => [qw(jquery.tablesorter.js)],        defer => 1, version => '20200308' },
			'jQuery.jstree'         => { src => [qw(jquery.jstree.js)],             defer => 1, version => '20200308' },
			'jQuery.coolfieldset'   => { src => [qw(jquery.coolfieldset.js)],       defer => 1, version => '20200308' },
			'jQuery.slimbox'        => { src => [qw(jquery.slimbox2.js)],           defer => 1, version => '20200308' },
			'jQuery.columnizer'     => { src => [qw(jquery.columnizer.js)],         defer => 1, version => '20200308' },
			'jQuery.fonticonpicker' => { src => [qw(jquery.fonticonpicker.min.js)], defer => 1, version => '20210719' },
			'modal'                 => { src => [qw(jquery.modal.min.js)],          defer => 1, version => '20210624' },
			'fitty'                 => { src => [qw(fitty.min.js)],                 defer => 1, version => '20210706' },
			'jQuery.multiselect'    => {
				src     => [qw(jquery.multiselect.min.js jquery.multiselect.filter.min.js)],
				defer   => 1,
				version => '2020308'
			},
			'CryptoJS.MD5' => { src => [qw(md5.js)],         defer => 1, version => '20200308' },
			'packery'      => { src => [qw(packery.min.js)], defer => 1, version => '20210620' },
			'muuri'        => { src => [qw(muuri.min.js)],   defer => 1, version => '20210620' },
			'dropzone'     => { src => [qw(dropzone.js)],    defer => 0, version => '20200308' },

			#See https://dolmenweb.it/viewers/openlayer/doc/tutorials/custom-builds.html
			'ol'        => { src => [qw(ol-custom.js)], defer => 0, version => '6.14.1#20220517' },
			'billboard' => {
				src     => [qw(d3.v6.min.js billboard.min.js jquery.ui.touch-punch.min.js)],
				defer   => 1,
				version => '20210510'
			},
			'd3.layout.cloud' => { src => [qw(d3.layout.cloud.min.js)], defer => 1, version => '20210729' },
			'pivot'           => {
				src     => [qw(pivot.min.js export_renderers.min.js jquery.ui.touch-punch.min.js)],
				defer   => 1,
				version => '20200308'
			},
			'papaparse' => { src => [qw(papaparse.min.js)],    defer => 1, version => '20200308' },
			'heatmap'   => { src => [qw(heatmap.min.js)],      defer => 1, version => '20200308' },
			'filesaver' => { src => [qw(FileSaver.min.js)],    defer => 1, version => '20200308' },
			'modernizr' => { src => [qw(modernizr-custom.js)], defer => 1, version => '20200308' },
			'geomap'    => {
				src     => [qw(d3.v6.min.js d3.geomap.min.js d3-geo-projection.min.js topojson.min.js)],
				defer   => 1,
				version => '20200308'
			},
			'igv'              => { src => [qw(igv.min.js)],              defer => 1, version => '20200308' },
			'bigsdb.dashboard' => { src => [qw(bigsdb.dashboard.min.js)], defer => 1, version => '20221202' },
			'bigsdb.dataexplorer' =>
			  { src => [qw(bigsdb.dataexplorer.min.js d3.v6.min.js)], defer => 1, version => '20221119' }
		};
		if ( $self->{'pluginJS'} ) {
			$features->{'pluginJS'} = { src => ["Plugins/$self->{'pluginJS'}"], defer => 1, version => '20220620' };
		}
		my %used;
		foreach my $feature ( keys %$features ) {
			next if !$self->{$feature};
			my $libs = $features->{$feature}->{'src'};
			foreach my $lib (@$libs) {
				next if $used{$lib};
				my $version = $features->{$feature}->{'version'} ? "?v=$features->{$feature}->{'version'}" : q();
				if ( $self->{'config'}->{'relative_js_dir'} ) {
					push @$js,
					  {
						src   => "$self->{'config'}->{'relative_js_dir'}/$lib$version",
						defer => $features->{$feature}->{'defer'}
					  };
				} elsif ( -e "$ENV{'DOCUMENT_ROOT'}/javascript/$lib" ) {
					push @$js, { src => "/javascript/$lib$version", defer => $features->{$feature}->{'defer'} };
				} else {
					$logger->error("/javascript/$lib file not installed.");
				}
				$used{$lib} = 1;
			}
		}
		push @$js, { code => $page_js } if $page_js;
	}
	return $js;
}

sub get_guid {

	#If the user is logged in, use a combination of database and user names as the
	#GUID for preference storage, otherwise use a random GUID which is stored as a browser cookie.
	my ($self) = @_;
	if ( defined $self->{'username'} ) {
		return "$self->{'system'}->{'db'}\|$self->{'username'}";
	} elsif ( $self->{'cgi'}->cookie( -name => 'guid' ) ) {
		return $self->{'cgi'}->cookie( -name => 'guid' );
	} else {
		return 0;
	}
}

sub show_user_projects {
	my ($self) = @_;
	if ( ( ( $self->{'system'}->{'public_login'} // q() ) ne 'no' )
		|| $self->{'system'}->{'read_access'} ne 'public' )
	{
		if ( ( $self->{'system'}->{'user_projects'} // q() ) eq 'yes' ) {
			return 1;
		}
		if ( $self->{'config'}->{'user_projects'} && ( $self->{'system'}->{'user_projects'} // q() ) ne 'no' ) {
			return 1;
		}
	}
	return;
}

sub clean_value {
	my ( $self, $value, $options ) = @_;
	return if !defined $value;
	if ( ref $value eq 'ARRAY' ) {
		my @list;
		foreach my $value (@$value) {
			$value =~ s/"/\\"/gx;
			$value =~ s/^\s+|\s+$//x;
			next if $value eq q();
			push @list, $value;
		}
		local $" = q(",");
		return qq({"@list"});
	}
	$value =~ s/'/\\'/gx if !$options->{'no_escape'};
	$value =~ s/\r//gx;
	$value =~ s/[\n\t]/ /gx;
	$value =~ s/^\s*//x;
	$value =~ s/\s*$//x;
	return $value;
}

sub create_temp_tables {
	my ( $self, $qry_ref ) = @_;
	return 1 if $self->{'temp_tables_created'};
	my $qry     = $$qry_ref;
	my $q       = $self->{'cgi'};
	my $format  = $q->param('format') || 'html';
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my $cschemes =
	  $self->{'datastore'}->run_query( 'SELECT id FROM classification_schemes', undef, { fetch => 'col_arrayref' } );
	my $continue = 1;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $view = $self->{'system'}->{'view'};
		try {
			foreach my $scheme_id (@$schemes) {
				if (   $qry =~ /temp_(?:isolates|$view)_scheme_fields_$scheme_id\D/x
					|| $qry =~ /ORDER\ BY\ s_$scheme_id\_/x )
				{
					$self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				}
				if ( $qry =~ /temp_(?:isolates|$view)_scheme_completion_$scheme_id\D/x ) {
					$self->{'datastore'}->create_temp_scheme_status_table($scheme_id);
				}
				if ( $qry =~ /temp_lincodes_$scheme_id\D/x ) {
					$self->{'datastore'}->create_temp_lincodes_table($scheme_id);
				}
				if ( $qry =~ /temp_lincode_${scheme_id}_field_values/x ) {
					$self->{'datastore'}->create_temp_lincode_prefix_values_table($scheme_id);
				}
			}
			foreach my $cscheme_id (@$cschemes) {
				if ( $qry =~ /temp_cscheme_$cscheme_id\D/x ) {
					$self->{'datastore'}->create_temp_cscheme_table($cscheme_id);
				}
			}
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
				if ( $format ne 'text' ) {
					$self->print_bad_status(
						{ message => q(Cannot connect to remote database. The query can not be performed.) } );
				} else {
					say q(Cannot connect to remote database. The query cannot be performed.);
				}
				$logger->error('Cannot connect to remote database.');
				$continue = 0;
			} else {
				$logger->logdie($_);
			}
		};
	}
	if ( $q->param('list_file') && $q->param('datatype') ) {
		$self->{'datastore'}->create_temp_list_table( scalar $q->param('datatype'), scalar $q->param('list_file') );
	}
	if ( defined $q->param('temp_table_file') ) {
		$self->{'datastore'}->create_temp_combinations_table_from_file( scalar $q->param('temp_table_file') );
	}
	$self->{'temp_tables_created'} = 1;
	return $continue;
}

sub print_banner {
	my ( $self, $options ) = @_;
	my $bannerfile = "$self->{'dbase_config_dir'}/$self->{'instance'}/banner.html";
	my $class = $options->{'class'} // 'banner';
	if ( -e $bannerfile ) {
		say qq(<div class="box $class">);
		$self->print_file($bannerfile);
		say q(</div>);
	}
	return;
}

sub choose_set {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (   $q->param('choose_set')
		&& defined $q->param('sets_list')
		&& BIGSdb::Utils::is_int( scalar $q->param('sets_list') ) )
	{
		my $guid = $self->get_guid;
		if ($guid) {
			try {
				$self->{'prefstore'}
				  ->set_general( $guid, $self->{'system'}->{'db'}, 'set_id', scalar $q->param('sets_list') );
				$self->{'prefs'}->{'set_id'} = $q->param('sets_list');
			}
			catch {
				if ( $_->isa('BIGSdb::Exception::Prefstore') ) {
					$logger->error(q(Cannot set set_id in prefs));
				} else {
					$logger->logdie($_);
				}
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
		my $plugin  = $self->{'pluginManager'}->get_plugin($plugin_name);
		my $att     = $plugin->get_attributes;
		my $formats = {
			text => sub {
				$self->{'type'}       = 'text';
				$self->{'attachment'} = $att->{'text_filename'};
			},
			xlsx => sub {
				$self->{'type'}       = 'xlsx';
				$self->{'attachment'} = $att->{'xlsx_filename'};
			},
			tar => sub {
				$self->{'type'}       = 'tar';
				$self->{'attachment'} = $att->{'tar_filename'};
			},
			json => sub {
				$self->{'type'} = 'json';
			},
			fasta => sub {
				$self->{'type'} = 'text';
			}
		};
		if ( $formats->{ $q->param('format') } ) {
			$formats->{ $q->param('format') }->();
		} else {
			$self->{$_} = 1 foreach qw(jQuery);
		}
		my $init_values = $plugin->get_initiation_values;
		$self->{'breadcrumbs'} = $plugin->get_breadcrumbs;
		foreach my $key ( keys %$init_values ) {
			$self->{$key} = $init_values->{$key};
		}
		if ( $q->param('no_header') ) {
			$self->{'type'} = 'no_header';
		}
	}
	catch {
		#ignore
	};
	return;
}

sub get_file_icon {
	my ( $self, $type ) = @_;
	my $buffer = q(<span class="file_icon fa-stack" style="padding-left:0.5em">);
	$buffer .= q(<span class="fas fa-file fa-stack-2x"></span>);
	$buffer .= qq(<span class="fa-stack-1x filetype-text" style="top:0.25em">$type</span>);
	$buffer .= q(</span>);
	return $buffer;
}

sub get_field_group_icon {
	my ( $self, $group ) = @_;
	return if !$group;
	my $divider = q(,);
	my @group_values =
	  $self->{'system'}->{'field_groups'} ? ( split /$divider/x, $self->{'system'}->{'field_groups'} ) : ();
	foreach my $value ( sort @group_values ) {
		my ( $name, $icon ) = split /\|/x, $value;
		return $icon if $name eq $group;
	}
	return;
}

sub get_eav_group_icon {
	my ( $self, $group ) = @_;
	return if !$group;
	my $divider = q(,);
	my @group_values =
	  $self->{'system'}->{'eav_groups'} ? ( split /$divider/x, $self->{'system'}->{'eav_groups'} ) : ();
	foreach my $value ( sort @group_values ) {
		my ( $name, $icon ) = split /\|/x, $value;
		return $icon if $name eq $group;
	}
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
			if ($guid) {
				try {
					$self->{'prefs'}->{'tooltips'} =
					  ( $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'tooltips' ) // '' )
					  eq 'off' ? 0 : 1;
					$self->{'prefs'}->{'set_id'} =
					  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'set_id' );
				}
				catch {
					if ( $_->isa('BIGSdb::Exception::Database::NoRecord') ) {
						$self->{'prefs'}->{'tooltips'} = 1;
					} else {
						$logger->logdie($_);
					}
				};
			}
			$self->choose_set;
		}
	} else {
		$self->initiate_prefs;
		$self->initiate_view( $self->{'username'} );
	}
	$q->charset('UTF-8');
	if ( !$q->cookie( -name => 'guid' ) && $self->{'prefstore'} ) {
		my $guid = $self->{'prefstore'}->get_new_guid;
		push @{ $self->{'cookies'} }, $q->cookie( -name => 'guid', -value => $guid, -expires => '+10y' );
		$self->{'setOptions'} = 1;
	}
	my %header_options;
	$header_options{'-cookie'} = $self->{'cookies'} if $self->{'cookies'};
	$header_options{'-expires'} = '+1h' if !$self->{'noCache'};
	if ( $self->{'type'} ne 'xhtml' ) {
		my %mime_type = (
			embl      => 'chemical/x-embl-dl-nucleotide',
			genbank   => 'chemical/seq-na-genbank',
			gff3      => 'application/x-gff',
			tar       => 'application/x-tar',
			xlsx      => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
			no_header => 'text/html',
			text      => 'text/plain',
			html      => 'text/html',
			png       => 'image/png',
			jpg       => 'image/jpeg',
			gif       => 'image/gif',
			pdf       => 'application/pdf',
			docx      => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
		);
		my %attachment = (
			embl    => 'sequence' . ( $q->param('seqbin_id') // $q->param('isolate_id') // q() ) . '.embl',
			gff3    => 'sequence' . ( $q->param('seqbin_id') // $q->param('isolate_id') // q() ) . '.gff3',
			genbank => 'sequence' . ( $q->param('seqbin_id') // $q->param('isolate_id') // q() ) . '.gbk',
		);
		$header_options{'-type'} = $mime_type{ $self->{'type'} } // 'text/plain';
		$header_options{'-attachment'} = $attachment{ $self->{'type'} } // $self->{'attachment'} // undef;
		my %utf8_types = map { $_ => 1 } qw(no_header text json);
		binmode STDOUT, ':encoding(utf8)' if $utf8_types{ $self->{'type'} };
		print $q->header( \%header_options );
		$self->print_content;
	} else {
		binmode STDOUT, ':encoding(utf8)';
		$header_options{'-status'} = $self->{'status'} if $self->{'status'};
		print $q->header(%header_options);
		my $title        = $self->get_title;
		my $javascript   = $self->_get_javascript_paths;
		my $meta_content = $self->_get_meta_data;
		my $stylesheets  = $self->_get_stylesheets;
		$self->_start_html(
			{
				title  => $title,
				meta   => $meta_content,
				style  => $stylesheets,
				script => $javascript
			}
		);
		my $max_width            = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
		my $main_max_width       = $max_width - 15;
		my $main_container_class = $self->{'login'} ? q( main_container_login) : q();
		my $main_content_class   = $self->{'login'} ? q( main_content_login) : q();

		if ( $self->{'system'}->{'db'} && $self->{'instance'} ) {
			$self->_print_header;
			$self->_print_breadcrumbs;
			say qq(<div class="main_container$main_container_class">);
			say qq(<div class="main_content$main_content_class" style="max-width:${main_max_width}px">);
			$self->_print_button_panel;
			say qq(<script>var max_width=${main_max_width}</script>);
			$self->print_content;
			say q(</div></div>);
			$self->_print_footer;
		} else {
			$self->_print_site_header;
			$self->_print_breadcrumbs;
			say qq(<div class="main_container$main_container_class">);
			say qq(<div class="main_content $main_content_class" style="max-width:${main_max_width}px">);
			say qq(<script>var max_width=${main_max_width}</script>);
			$self->print_content;
			say q(</div></div>);
			$self->_print_site_footer;
		}
		$self->_debug if $q->param('debug') && $self->{'config'}->{'debug'};
		say q(</body>);
		say q(</html>);
	}
	return;
}

sub _start_html {
	my ( $self, $args ) = @_;
	my ( $title, $meta, $style, $script, $shortcut_icon ) = @{$args}{qw(title meta style script shortcut_icon)};
	my $tooltip_display = $self->{'prefs'}->{'tooltips'} ? 'inline' : 'none';
	say q(<!DOCTYPE html>);
	say q(<html>);
	say q(<head>);
	say qq(<title>$title</title>) if $title;
	say q(<meta name="viewport" content="width=device-width" />);
	say q(<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />);

	if ( $self->{'refresh'} ) {
		my $refresh_page = $self->{'refresh_page'} ? qq(; URL=$self->{'refresh_page'}) : q();
		say qq(<meta http-equiv="refresh" content="$self->{'refresh'}$refresh_page" />);
	}
	if ($meta) {
		say $meta;
	}
	foreach my $css (@$style) {
		say qq(<link rel="stylesheet" type="text/css" href="$css" />);
	}
	say q(<style>);
	say qq(  .tooltip{display:$tooltip_display});
	say q(</style>);
	foreach my $js (@$script) {
		if ( $js->{'src'} ) {
			my $version = $js->{'version'} ? "?v=$js->{'version'}" : q();
			my $defer = $js->{'defer'} ? ' defer' : q();
			say qq(<script src="$js->{'src'}$version"$defer></script>);
		} elsif ( $js->{'code'} ) {
			say q(<script>);
			say $js->{'code'};
			say q(</script>);
		}
	}
	say q(</head>);
	say q(<body>);
	return;
}

sub _get_meta_data {
	my ($self) = @_;
	$self->{'instance'} //= q();
	my @potential_meta_files = (
		"$self->{'dbase_config_dir'}/$self->{'instance'}/meta.html",
		"$ENV{'DOCUMENT_ROOT'}/meta.html",
		"$self->{'config_dir'}/meta.html"
	);
	my $content = q();
	foreach my $file (@potential_meta_files) {
		next if !-e $file;
		my $content_ref = BIGSdb::Utils::slurp($file);
		return $$content_ref;
	}
	return $content;
}

sub _get_stylesheets {
	my ($self)  = @_;
	my $system  = $self->{'system'};
	my $version = '20221202';
	my @filenames;
	push @filenames, q(dropzone.css)                                          if $self->{'dropzone'};
	push @filenames, q(billboard.min.css)                                     if $self->{'billboard'};
	push @filenames, q(pivot.min.css)                                         if $self->{'pivot'};
	push @filenames, qw(jquery.multiselect.css jquery.multiselect.filter.css) if $self->{'jQuery.multiselect'};
	push @filenames, qw(d3.geomap.css)                                        if $self->{'geomap'};
	push @filenames, qw(jquery.modal.min.css)                                 if $self->{'modal'};
	push @filenames, qw(ol.css)                                               if $self->{'ol'};
	push @filenames, qw(jquery.fonticonpicker.min.css jquery.fonticonpicker.darkgrey.min.css)
	  if $self->{'jQuery.fonticonpicker'};

	if ( !$self->{'config'}->{'no_cookie_consent'} && !$self->{'curate'} && $self->{'instance'} ) {
		push @filenames, q(cookieconsent.min.css);
	}
	push @filenames, qw(jquery-ui.min.css fontawesome-all.css bigsdb.min.css);
	my @paths;
	foreach my $filename (@filenames) {
		my $stylesheet;
		my $vfilename = "$filename?v=$version";
		if ( $self->{'config'}->{'relative_css_dir'} ) {
			$stylesheet = "$self->{'config'}->{'relative_css_dir'}/$vfilename";
		} else {
			if ( !$system->{'db'} ) {
				$stylesheet = -e "$ENV{'DOCUMENT_ROOT'}/css/$filename" ? "/css/$vfilename" : "/$vfilename";
			} else {
				my @css_paths = ( "$system->{'webroot'}/$system->{'db'}", $system->{'webroot'}, '/css', '' );
				my $found = 0;
				foreach my $path (@css_paths) {
					if ( -e "$ENV{'DOCUMENT_ROOT'}$path/$filename" ) {
						$stylesheet = "$path/$vfilename";
						$found      = 1;
						last;
					}
				}
				$logger->error("Stylesheet $filename not found!") if !$found;
			}
		}
		push @paths, $stylesheet;
	}
	if ( $self->{'config'}->{'stylesheets'} ) {
		my @css = split /,/x, $self->{'config'}->{'stylesheets'};
		push @paths, @css;
	}
	if ( $self->{'jQuery.jstree'} ) {
		push @paths, "/javascript/themes/default/style.min.css?v=$version";
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
	my $sets =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM sets WHERE NOT hidden OR hidden IS NULL ORDER BY display_order,description',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$sets || ( @$sets == 1 && ( $self->{'system'}->{'only_sets'} // '' ) eq 'yes' );
	say q(<div class="box" id="sets">);
	say q(<div class="scrollable">);
	say q(<div style="float:left; margin-right:1em">);
	say q(<span class="dataset_icon fas fa-database fa-3x fa-pull-left"></span>);
	say q(<h2>Datasets</h2>);
	say q(<p>This database contains multiple datasets.);
	print(
		( $self->{'system'}->{'only_sets'} // '' ) eq 'yes'
		? '</p>'
		: 'You can choose to display a single set or the whole database.</p>'
	);
	say $q->start_form;
	say q(<label for="sets_list">Please select: </label>);
	my @set_ids;

	if ( ( $self->{'system'}->{'only_sets'} // '' ) ne 'yes' ) {
		push @set_ids, 0;
	}
	my %labels = ( 0 => 'Whole database' );
	foreach my $set (@$sets) {
		push @set_ids, $set->{'id'};
		$labels{ $set->{'id'} } = $set->{'description'};
	}
	say $q->popup_menu(
		-name    => 'sets_list',
		-id      => 'sets_list',
		-values  => \@set_ids,
		-labels  => \%labels,
		-default => $set_id
	);
	say $q->submit( -name => 'choose_set', -label => 'Choose', -class => 'small_submit' );
	say $q->hidden($_) foreach qw (db page name set_id select_sets);
	say $q->end_form;
	say q(</div></div></div>);
	return;
}

sub is_scheme_invalid {
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$self->print_bad_status( { message => q(Scheme id must be an integer.), navbar => 1 } );
		return 1;
	} elsif ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			$self->print_bad_status( { message => q(The selected scheme is unavailable.), navbar => 1 } );
			return 1;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info && !( $scheme_id == 0 && $options->{'all_loci'} ) ) {
		$self->print_bad_status( { message => q(Scheme does not exist.), navbar => 1 } );
		return 1;
	}
	if ( $options->{'with_pk'} && !$scheme_info->{'primary_key'} ) {
		$self->print_bad_status(
			{
				message => q(No primary key field has been set for this scheme. )
				  . q(This function is unavailable until this has been set.),
				navbar => 1
			}
		);
		return 1;
	}
	return;
}

sub print_scheme_section {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my $schemes = $self->get_scheme_data( { with_pk => $options->{'with_pk'} } );
	$q->param( scheme_id => $schemes->[0]->{'id'} ) if !defined $q->param('scheme_id') && @$schemes;
	return if @$schemes < 2;
	say q(<div class="box" id="schemes">);
	say q(<div class="scrollable">);
	say q(<h2>Schemes</h2>);
	say q(<p>Please select the scheme you would like to query:</p>);
	my @ids;
	my %desc;

	foreach my $scheme (@$schemes) {
		push @ids, $scheme->{'id'};
		$desc{ $scheme->{'id'} } = $scheme->{'name'};
	}
	if ( $options->{'all_loci'} ) {
		push @ids, 0;
		$desc{0} = 'All loci';
	}
	my $default = $q->param('scheme_id');
	say $q->start_form;
	say $q->popup_menu( -name => 'scheme_id', -values => \@ids, -labels => \%desc, -default => $default );
	say $q->submit( -class => 'small_submit', -name => 'Select' );
	say $q->hidden($_) foreach qw(db page name);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub print_action_fieldset {
	my ( $self, $options ) = @_;
	my $q = $self->{'cgi'};
	$options = {} if ref $options ne 'HASH';
	my $page         = $options->{'page'}         // $q->param('page');
	my $submit_name  = $options->{'submit_name'}  // 'submit';
	my $submit_label = $options->{'submit_label'} // 'Submit';
	my $reset_label  = $options->{'reset_label'}  // 'Reset';
	my $legend       = $options->{'legend'}       // 'Action';
	my $buffer       = qq(<fieldset style="float:left"><legend>$legend</legend>\n);
	$buffer .= $options->{'text'} if $options->{'text'};
	my $url    = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page);
	my @fields = qw (isolate_id id scheme_id table name ruleset locus
	  profile_id simple set_id modify project_id edit private user_header);

	if ( $options->{'table'} ) {
		my $pk_fields = $self->{'datastore'}->get_table_pks( $options->{'table'} );
		push @fields, @$pk_fields;
	}
	foreach my $field ( uniq @fields ) {
		$url .= "&amp;$field=$options->{$field}" if defined $options->{$field};
	}

	#use jquery-ui button classes to ensure consistent formatting of reset link and submit button across browsers
	if ( !$options->{'no_reset'} ) {
		$buffer .= qq(<a href="$url" class="reset"><span>$reset_label</span></a>\n);
	}
	local $" = q( );
	my %id = $options->{'id'} ? ( id => $options->{'id'} ) : ();
	$buffer .= $q->submit( -name => $submit_name, -label => $submit_label, -class => 'submit', %id );
	if ( $options->{'submit2'} ) {
		$options->{'submit2_label'} //= $options->{'submit2'};
		$buffer .= $q->submit(
			-name  => $options->{'submit2'},
			-label => $options->{'submit2_label'},
			-class => 'submit',
			-style => 'margin-left:0.2em'
		);
	}
	$buffer .= q(</fieldset>);
	$buffer .= q(<div style="clear:both"></div>) if !$options->{'no_clear'};
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub _debug {
	my ($self) = @_;
	print "<pre>\n" . Dumper($self) . "</pre>\n";
	return;
}

sub _print_first_valid_file {
	my ( $self, $paths, $options ) = @_;
	foreach my $file (@$paths) {
		if ( -e $file ) {
			$self->print_file( $file, $options );
			return;
		}
	}
	return;
}

sub _print_header {
	my ($self) = @_;
	my $system = $self->{'system'};
	return if !$self->{'instance'};
	my $q = $self->{'cgi'};
	my @potential_headers;
	if ( $self->{'curate'} && !$q->param('user_header') ) {
		push @potential_headers,
		  (
			"$self->{'dbase_config_dir'}/$self->{'instance'}/curate_header.html",
			"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/curate_header.html",
			"$ENV{'DOCUMENT_ROOT'}/curate_header.html",
			"$self->{'config_dir'}/curate_header.html"
		  );
	}
	push @potential_headers,
	  (
		"$self->{'dbase_config_dir'}/$self->{'instance'}/header.html",
		"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/header.html",
		"$ENV{'DOCUMENT_ROOT'}/header.html",
		"$self->{'config_dir'}/header.html"
	  );
	$self->_print_first_valid_file( \@potential_headers );
	return;
}

sub _print_site_header {
	my ($self) = @_;
	my @potential_headers;
	if ( $self->{'curate'} ) {
		@potential_headers =
		  ( "$ENV{'DOCUMENT_ROOT'}/curate_site_header.html", "$self->{'config_dir'}/curate_site_header.html" );
	}
	push @potential_headers, ( "$ENV{'DOCUMENT_ROOT'}/site_header.html", "$self->{'config_dir'}/site_header.html" );
	$self->_print_first_valid_file( \@potential_headers, { no_substitutions => 1 } );
	return;
}

sub _print_login_details {
	my ($self) = @_;
	return if !$self->{'datastore'};
	my $login_requirement = $self->{'datastore'}->get_login_requirement;
	return if $login_requirement == NOT_ALLOWED && !$self->{'needs_authentication'};
	my $user_info       = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $q               = $self->{'cgi'};
	my $page            = $q->param('page');
	my $instance_clause = $self->{'instance'} ? qq(db=$self->{'instance'}&amp;) : q();
	my %curator         = map { $_ => 1 } qw(admin curator submitter);
	if ($user_info) {

		if ( $self->{'curate'} ) {
			if ( $self->{'config'}->{'query_script'} ) {
				say q(<div id="login_details">);
				say q(<span class="icon_button">)
				  . qq(<a href="$self->{'config'}->{'query_script'}?db=$self->{'instance'}">)
				  . q(<span class="fas fa-lg fa-user" )
				  . qq(title="Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'}) - )
				  . q(Click to access public interface"></span>)
				  . q(<div class="icon_label">User interface</div></a></span>);
				say q(</div>);
			} else {
				$logger->error('query_script attribute is not set in bigsdb.conf');
				say q(<div id="login_details"><span class="icon_button">);
				say q(<span class="fas fa-lg fa-user" )
				  . qq(title="Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'})">)
				  . q(</span><div class="icon_label">Logged in</div></span>);
				say q(</div>);
			}
		} else {
			my $curate_config = $self->{'system'}->{'curate_config'} // $self->{'instance'};
			if ( $curator{ $user_info->{'status'} } ) {
				if ( $self->{'config'}->{'curate_script'} ) {
					my $title =
					    qq(Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'}) )
					  . q( - Click to access curator interface);
					$title =~ s/&lt;\s*script|script\s*&gt;//gx;
					say q(<span class="icon_button"><a id="curator_link" )
					  . qq(class="trigger_button" href="$self->{'config'}->{'curate_script'}?db=$curate_config" )
					  . qq(title="$title"><span class="fas fa-lg fa-user-tie"></span>)
					  . q(<div class="icon_label">Curator interface</div></a></span>);
				} else {
					$logger->error('curate_script attribute is not set in bigsdb.conf');
					say q(<div id="login_details"><span class="icon_button">);
					say q(<span class="fas fa-lg fa-user" )
					  . qq(title="Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'})">)
					  . q(</span><div class="icon_label">Logged in</div></span>);
					say q(</div>);
				}
			} else {
				say q(<div id="login_details"><span class="icon_button">);
				say qq(<a href="$self->{'system'}->{'script_name'}"><span class="fas fa-lg fa-user" )
				  . qq(title="Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($self->{'username'})">)
				  . q(</span><div class="icon_label">Logged in</div></a></span>);
				say q(</div>);
			}
		}
	} elsif ( $self->{'username'} ) {
		say q(<div id="login_details"><span class="icon_button">);
		say q(<span class="fas fa-lg fa-user" title="Logged in: Unregistered user"></span>);
		say q(<div class="icon_label">Logged in</div></span></div>);
	}
	return;
}

sub get_cache_string {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $logged_in        = $self->{'username'} ? 1                     : 0;
	my $logged_in_string = $self->{'username'} ? "&amp;l=$logged_in"   : q();
	my $set_string       = $set_id             ? "&amp;set_id=$set_id" : q();

	#Append to URLs to ensure unique caching.
	my $cache_string = $set_string . $logged_in_string;
	return $cache_string;
}

sub get_help_url {

	#Override in subclass.
}

sub _print_button_panel {
	my ($self) = @_;
	say q(<div class="button_panel">);
	$self->_print_login_details;
	$self->_print_help_button;
	$self->_print_tooltip_toggle;
	$self->_print_expand_trigger;
	$self->print_panel_buttons;
	say q(</div>);
	return;
}

sub _print_tooltip_toggle {
	my ($self) = @_;
	if ( $self->{'tooltips'} ) {
		my $enabled = $self->{'prefs'}->{'tooltips'} ? 'tooltips_enabled' : 'tooltips_disabled';
		my $title   = $self->{'prefs'}->{'tooltips'} ? 'Disable tooltips' : 'Enable tooltips';
		say qq(<span class="icon_button"><a id="toggle_tooltips" class="trigger_button $enabled" style="display:none" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=options&amp;)
		  . q(toggle_tooltips=1">)
		  . q(<span class="fas fa-lg fa-info-circle"></span><div class="icon_label">Tooltips</div></a></span>);
	}
	return;
}

sub _print_help_button {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('page') && $q->param('page') eq 'plugin' && defined $self->{'pluginManager'} ) {
		my $plugin_att = $self->{'pluginManager'}->get_plugin_attributes( scalar $q->param('name') );
		if ( ref $plugin_att eq 'HASH' ) {
			if ( $plugin_att->{'url'} && !$self->{'config'}->{'intranet'} ) {
				say q(<span class="icon_button">)
				  . qq(<a id="help_link" class="trigger_button" href="$plugin_att->{'url'}" target="_blank" )
				  . q(title="Open context-sensitive help in new window">)
				  . q(<span style="margin-left:0.5em" class="fas fa-lg fa-external-link-alt"></span>)
				  . q(<div class="icon_label">Help</div></a></span>);
			}
			if ( ( $plugin_att->{'help'} // '' ) =~ /tooltips/ ) {
				$self->{'tooltips'} = 1;
			}
		}
	} else {
		my $url = $self->get_help_url;
		if ( $url && !$self->{'config'}->{'intranet'} ) {
			say q(<span class="icon_button">)
			  . qq(<a id="help_link" class="trigger_button" href="$url" target="_blank" )
			  . q(title="Open context-sensitive help in new window">)
			  . q(<span style="margin-left:0.5em" class="fas fa-lg fa-external-link-alt"></span>)
			  . q(<div class="icon_label">Help</div></a></span>);
		}
	}
	return;
}

sub _print_expand_trigger {
	my ($self) = @_;
	return if !$self->{'allowExpand'};
	say q(<span class="icon_button"><a id="expand_trigger" class="trigger_button" style="display:none">)
	  . q(<span id="expand" class="fas fa-lg fa-expand" title="Expand width"></span>)
	  . q(<span id="contract" class="fas fa-lg fa-compress" style="display:none" title="Compress width">)
	  . q(</span><div class="icon_label">Expand</div></a></span>);
	return;
}

#Override in subclasses.
sub print_panel_buttons { }

sub _print_breadcrumbs {
	my ($self) = @_;
	return if !$self->{'system'}->{'db'};
	my $q = $self->{'cgi'};
	my $page = $q->param('page') // q();
	my @breadcrumbs;
	my %root_pages = map { $_ => 1 } qw(registration user usernameRemind resetPassword);
	if ( !$root_pages{$page} ) {
		my @potential_breadcrumb_files = (
			"$self->{'dbase_config_dir'}/$self->{'instance'}/breadcrumbs.conf",
			"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/breadcrumbs.conf",
			"$ENV{'DOCUMENT_ROOT'}/breadcrumbs.conf",
			"$self->{'config_dir'}/breadcrumbs.conf"
		);
		foreach my $file (@potential_breadcrumb_files) {
			if ( -e $file ) {
				open( my $fh, '<:encoding(utf8)', $file ) || $logger->error("Cannot open $file for reading");
				while ( my $line = <$fh> ) {
					if ( $line =~ /^(.+)\|(.+)$/x ) {
						my ( $text, $url ) = ( $1, $2 );
						push @breadcrumbs, qq(<a href="$url">$text</a>);
					}
				}
				close $fh;
				last;
			}
		}
	}
	if ( $self->{'breadcrumbs'} ) {
		foreach my $crumb ( @{ $self->{'breadcrumbs'} } ) {
			my $breadcrumb;
			$breadcrumb = qq(<a href="$crumb->{'href'}">) if $crumb->{'href'};

			#Simple conversion of markdown (bold and italics) to HTML.
			my $label = $crumb->{'label'};
			$label =~ s/\*\*(.*?)\*\*/<strong>$1\<\/strong>/gx;
			$label =~ s/\*(.*?)\*/<em>$1\<\/em>/gx;
			$breadcrumb .= $label;
			$breadcrumb .= q(</a>) if $crumb->{'href'};
			push @breadcrumbs, $breadcrumb;
		}
	}
	my $max_width = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $breadcrumbs_max_width = $max_width - 15;
	return if !@breadcrumbs;
	say q(<div class="breadcrumb_container">);
	say qq(<div class="breadcrumbs" style="width:100vw;max-width:${breadcrumbs_max_width}px">);
	local $" = q(<span class="breadcrumb_divider">&gt;</span>);
	say qq(@breadcrumbs);
	say q(</div></div>);
	return;
}

sub add_existing_eav_data_to_hashref {
	my ( $self, $data ) = @_;
	return if !defined $data->{'id'};
	my @types = qw(int float text date boolean);
	foreach my $type (@types) {
		my $eav_data = $self->{'datastore'}->run_query( "SELECT * FROM eav_$type WHERE isolate_id=?",
			$data->{'id'}, { fetch => 'all_arrayref', slice => {} } );
		foreach my $record (@$eav_data) {
			$data->{ $record->{'field'} } = $record->{'value'};
		}
	}
	return;
}

sub get_extended_attributes {
	my ($self) = @_;
	my $data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT isolate_field,attribute FROM isolate_field_extended_attributes ORDER BY field_order',
		undef, { fetch => 'all_arrayref', slice => {}, cache => 'Page::get_extended_attributes' } );
	my $extended;
	foreach (@$data) {
		push @{ $extended->{ $_->{'isolate_field'} } }, $_->{'attribute'};
	}
	return $extended;
}

sub get_field_selection_list {

#options passed as hashref:
#isolate_fields: include isolate fields, prefix with f_
#eav_fields: include EAV fields, prefix with eav_
#extended_attributes: include isolate field extended attributes, named e_FIELDNAME||EXTENDED-FIELDNAME
#loci: include loci, prefix with either l_ or cn_ (common name)
#locus_limit: don't include loci if there are more than the set value
#query_pref: only the loci for which the user has a query field preference selected will be returned
#analysis_pref: only the loci for which the user has an analysis preference selected will be returned
#scheme_fields: include scheme fields, prefix with s_SCHEME-ID_
#lincodes: include scheme LINcode field, named lin_SCHEME-ID
#lincode_fields: include fields linked to LINcode prefixes (must also select lincodes options), prefixed with lin_SCHEME_ID_
#classification_groups: include classification group ids and field, prefix with cg_
#sort_labels: dictionary sort labels
	my ( $self, $options ) = @_;
	$options->{'query_pref'}    //= 1;
	$options->{'analysis_pref'} //= 0;
	my $values = [];
	if ( $options->{'isolate_fields'} ) {
		my $isolate_fields = $self->_get_provenance_fields($options);
		push @$values, @$isolate_fields;
	}
	if ( $options->{'eav_fields'} ) {
		my $eav_fields = $self->_get_eav_fields($options);
		push @$values, @$eav_fields;
	}
	if ( $options->{'loci'} ) {
		my $loci = $self->_get_loci_list($options);
		push @$values, @$loci;
	}
	if ( $options->{'scheme_fields'} ) {
		my $scheme_fields = $self->_get_scheme_fields($options);
		push @$values, @$scheme_fields;
	}
	if ( $options->{'lincodes'} ) {
		my $lincode_fields = $self->_get_lincode_schemes($options);
		push @$values, @$lincode_fields;
	}
	if ( $options->{'classification_groups'} ) {
		my $classification_group_fields = $self->_get_classification_groups_fields;
		push @$values, @$classification_group_fields;
	}
	if ( $options->{'annotation_status'} ) {
		my $annotation_status_fields = $self->_get_annotation_status_fields;
		push @$values, @$annotation_status_fields;
	}
	if ( $options->{'sort_labels'} ) {
		$values = BIGSdb::Utils::dictionary_sort( $values, $self->{'cache'}->{'labels'} );
	}
	return $values, $self->{'cache'}->{'labels'};
}

sub _get_loci_list {
	my ( $self, $options ) = @_;
	if ( !$self->{'cache'}->{'loci'} ) {
		my @locus_list;
		my $cn_sql = $self->{'db'}->prepare('SELECT id,common_name FROM loci WHERE common_name IS NOT NULL');
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
		my $set_loci =
		    $set_id
		  ? $self->{'datastore'}
		  ->run_query( 'SELECT * FROM set_loci WHERE set_id=?', $set_id, { fetch => 'all_hashref', key => 'locus' } )
		  : {};

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
						$self->{'cache'}->{'labels'}->{"cn_$locus"} =
						  "$set_locus->{'set_common_name'} ($set_locus->{'set_name'})";
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
			my $alias_sql = $self->{'db'}->prepare('SELECT locus,alias FROM locus_aliases');
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
		@locus_list =
		  sort { lc( $self->{'cache'}->{'labels'}->{$a} ) cmp lc( $self->{'cache'}->{'labels'}->{$b} ) } @locus_list;
		@locus_list = uniq @locus_list;
		$self->{'cache'}->{'loci'} = \@locus_list;
	}
	my $values = [];
	if ( !$options->{'locus_limit'} || @{ $self->{'cache'}->{'loci'} } < $options->{'locus_limit'} ) {
		push @$values, @{ $self->{'cache'}->{'loci'} };
	}
	return $values;
}

sub _get_provenance_fields {
	my ( $self, $options ) = @_;
	my @isolate_list;
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $fields     = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	my $extended   = $options->{'extended_attributes'} ? $self->get_extended_attributes : undef;
	foreach my $field (@$fields) {
		next if $options->{'query_pref'} && ( $attributes->{$field}->{'query'} // q() ) eq 'no';
		if (
			( $options->{'sender_attributes'} )
			&& (   $field eq 'sender'
				|| $field eq 'curator'
				|| ( $attributes->{$field}->{'userfield'} // '' ) eq 'yes' )
		  )
		{
			foreach my $user_attribute (qw (id surname first_name affiliation)) {
				push @isolate_list, "f_$field ($user_attribute)";
				( $self->{'cache'}->{'labels'}->{"f_$field ($user_attribute)"} = "$field ($user_attribute)" ) =~
				  tr/_/ /;
			}
		} elsif ( ( $attributes->{$field}->{'type'} // q() ) eq 'geography_point'
			&& !$options->{'nosplit_geography_points'} )
		{
			if ( $options->{'include_unsplit_geography_point'} ) {
				push @isolate_list, "f_$field";
				( $self->{'cache'}->{'labels'}->{"f_$field"} = $field ) =~ tr/_/ /;
			}
			foreach my $term (qw(latitude longitude)) {
				push @isolate_list, "gp_${field}_$term";
				( $self->{'cache'}->{'labels'}->{"gp_${field}_$term"} = "${field} ($term)" ) =~ tr/_/ /;
			}
		} else {
			push @isolate_list, "f_$field";
			( $self->{'cache'}->{'labels'}->{"f_$field"} = $field ) =~ tr/_/ /;
			if ( $options->{'extended_attributes'} ) {
				my $extatt = $extended->{$field};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						push @isolate_list, "e_$field||$extended_attribute";
						( $self->{'cache'}->{'labels'}->{"e_$field||$extended_attribute"} = $extended_attribute ) =~
						  tr/_/ /;
					}
				}
			}
		}
	}
	return \@isolate_list;
}

sub _get_eav_fields {
	my ( $self, $options ) = @_;
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
	my $list       = [];
	foreach my $fieldname (@$eav_fields) {
		push @$list, qq(eav_$fieldname);
		( my $cleaned = $fieldname ) =~ tr/_/ /;
		$self->{'cache'}->{'labels'}->{qq(eav_$fieldname)} = $cleaned;
	}
	return $list;
}

sub _get_scheme_fields {
	my ( $self, $options ) = @_;
	if ( !$self->{'cache'}->{'scheme_fields'} ) {
		my @scheme_field_list;
		my $set_id        = $self->get_set_id;
		my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my $scheme_fields = $self->{'datastore'}->get_all_scheme_fields;
		my $scheme_info   = $self->{'datastore'}->get_all_scheme_info;
		foreach my $scheme (@$schemes) {
			my ( $scheme_id, $desc ) = ( $scheme->{'id'}, $scheme->{'name'} );
			my $scheme_db = $scheme_info->{$scheme_id}->{'dbase_name'};

			#No point using scheme fields if no scheme database is available.
			next
			  if !( ( $self->{'prefs'}->{'query_field_schemes'}->{$scheme_id} || $options->{'ignore_prefs'} )
				&& $scheme_db );
			foreach my $field ( @{ $scheme_fields->{$scheme_id} } ) {
				if (   $self->{'prefs'}->{'query_field_scheme_fields'}->{$scheme_id}->{$field}
					|| $options->{'ignore_prefs'} )
				{
					if ($set_id) {
						my $set_name = $self->{'datastore'}->run_query(
							'SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?',
							[ $set_id, $scheme_id ],
							{ cache => 'Page::get_scheme_fields' }
						);
						$desc = $set_name if defined $set_name;
					}
					( $self->{'cache'}->{'labels'}->{"s_${scheme_id}_$field"} = "$field ($desc)" ) =~ tr/_/ /;
					push @scheme_field_list, "s_${scheme_id}_$field";
				}
			}
		}
		$self->{'cache'}->{'scheme_fields'} = \@scheme_field_list;
	}
	return $self->{'cache'}->{'scheme_fields'};
}

sub _get_lincode_schemes {
	my ( $self, $options ) = @_;
	if ( !$self->{'cache'}->{'lincode_fields'} ) {
		my $lincode_field_list = [];
		my $set_id             = $self->get_set_id;
		my $schemes            = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my $scheme_info        = $self->{'datastore'}->get_all_scheme_info;
		foreach my $scheme (@$schemes) {
			my ( $scheme_id, $desc ) = ( $scheme->{'id'}, $scheme->{'name'} );
			my $scheme_db = $scheme_info->{$scheme_id}->{'dbase_name'};

			#No point using LINcodes if no scheme database is available.
			next
			  if !( ( $self->{'prefs'}->{'query_field_schemes'}->{$scheme_id} || $options->{'ignore_prefs'} )
				&& $scheme_db );
			if ( $self->{'datastore'}->are_lincodes_defined($scheme_id) ) {
				if ($set_id) {
					my $set_name = $self->{'datastore'}->run_query(
						'SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?',
						[ $set_id, $scheme_id ],
						{ cache => 'Page::get_scheme_fields' }
					);
					$desc = $set_name if defined $set_name;
				}
				( $self->{'cache'}->{'labels'}->{"lin_$scheme_id"} = "LINcode ($desc)" ) =~ tr/_/ /;
				push @$lincode_field_list, "lin_$scheme_id";
				next if !$options->{'lincode_fields'};
				my $fields =
				  $self->{'datastore'}
				  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
					$scheme_id, { fetch => 'col_arrayref' } );
				foreach my $field (@$fields) {
					push @$lincode_field_list, "lin_${scheme_id}_$field";
					( $self->{'cache'}->{'labels'}->{"lin_${scheme_id}_$field"} = "$field ($desc)" ) =~ tr/_/ /;
				}
			}
		}
		$self->{'cache'}->{'lincode_fields'} = $lincode_field_list;
	}
	return $self->{'cache'}->{'lincode_fields'};
}

sub _get_classification_groups_fields {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'classification_group_fields'} ) {
		my $list = [];
		my $cg_pkeys =
		  $self->{'datastore'}->run_query( 'SELECT id,name FROM classification_schemes ORDER BY display_order,name',
			undef, { fetch => 'all_arrayref', slice => {} } );
		foreach my $key (@$cg_pkeys) {
			push @$list, "cg_$key->{'id'}_group";
			$self->{'cache'}->{'labels'}->{"cg_$key->{'id'}_group"} = "$key->{'name'} group";
		}
		$self->{'cache'}->{'classification_group_fields'} = $list;
	}
	return $self->{'cache'}->{'classification_group_fields'};
}

sub _get_annotation_status_fields {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'annotation_status_fields'} ) {
		my $list                 = [];
		my $set_id               = $self->get_set_id;
		my $schemes              = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my $schemes_with_metrics = $self->{'datastore'}
		  ->run_query( 'SELECT id FROM schemes WHERE quality_metric', undef, { fetch => 'col_arrayref' } );
		my %with_metrics = map { $_ => 1 } @$schemes_with_metrics;
		foreach my $scheme (@$schemes) {
			next if !$with_metrics{ $scheme->{'id'} };
			push @$list, "as_$scheme->{'id'}";
			$self->{'cache'}->{'labels'}->{"as_$scheme->{'id'}"} = "$scheme->{'name'} annotation status";
		}
		$self->{'cache'}->{'annotation_status_fields'} = $list;
	}
	return $self->{'cache'}->{'annotation_status_fields'};
}

sub _print_footer {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $filename = $self->{'curate'} ? 'curate_footer.html' : 'footer.html';
	return if !$self->{'instance'};
	my @potential_footers;
	if ( $self->{'curate'} ) {
		push @potential_footers,
		  (
			"$self->{'dbase_config_dir'}/$self->{'instance'}/curate_footer.html",
			"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/curate_footer.html",
			"$ENV{'DOCUMENT_ROOT'}/curate_footer.html",
			"$self->{'config_dir'}/curate_footer.html"
		  );
	}
	push @potential_footers,
	  (
		"$self->{'dbase_config_dir'}/$self->{'instance'}/footer.html",
		"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/footer.html",
		"$ENV{'DOCUMENT_ROOT'}/footer.html",
		"$self->{'config_dir'}/footer.html"
	  );
	$self->_print_first_valid_file( \@potential_footers );
	return;
}

sub _print_site_footer {
	my ($self) = @_;
	my @potential_footers;
	if ( $self->{'curate'} ) {
		push @potential_footers,
		  ( "$ENV{'DOCUMENT_ROOT'}/curate_site_footer.html", "$self->{'config_dir'}/curate_site_footer.html" );
	}
	push @potential_footers, ( "$ENV{'DOCUMENT_ROOT'}/footer.html", "$self->{'config_dir'}/footer.html" );
	$self->_print_first_valid_file( \@potential_footers, { no_substitutions => 1 } );
	return;
}

sub print_file {
	my ( $self, $file, $options ) = @_;
	my $cache_string = $self->get_cache_string;
	my $buffer;
	if ( -e $file ) {
		my $system = $self->{'system'};
		open( my $fh, '<', $file ) or return;
		while (<$fh>) {
			next if /^\#/x && $options->{'ignore_hashlines'};
			if ( !$options->{'no_substitutions'} ) {
				s/\$instance/$self->{'instance'}/x;
				s/\$webroot/$system->{'webroot'}/x;
				s/\$dbase/$system->{'db'}/x;
				s/\$indexpage/$system->{'indexpage'}/x;
				s/\$contents/$system->{'script_name'}?db=$self->{'instance'}/x;
				if ( $self->{'curate'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
					my $link =
					  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences";
					s/\$lociAdd/<a href="$link">Add<\/a>/x;
				}
				if ( !$self->{'curate'} ) {
					s/(bigsdb\.pl.*page=.+?)"/$1$cache_string"/gx;
					if ( ~/bigsdb\.pl/x && !/page=/x ) {
						s/(bigsdb\.pl.*)"/$1$cache_string"/gx;
					}
				}
			}
			$buffer .= $_;
		}
		close $fh;
	} else {
		$logger->warn("File $file does not exist.");
	}
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub get_filter {
	my ( $self, $name, $values, $options ) = @_;
	my $q = $self->{'cgi'};
	$options = {} if ref $options ne 'HASH';
	my $class = $options->{'class'} || 'filter';
	( my $text = $options->{'text'} || $name ) =~ tr/_/ /;
	my $length = $options->{'remove_id'} ? 23 : 25;
	my ( $label, $title ) =
	  $self->get_truncated_label( "$text: ", $length, { capitalize_first => $options->{'capitalize_first'} } );
	my $title_attribute = $title ? qq(title="$title") : q();
	( my $id = "$name\_list" ) =~ tr/:/_/;

	if ( $options->{'remove_id'} ) {
		my $delete = DELETE;
		$label =
		    qq(<a id="$options->{'remove_id'}" class="remove_filter" style="cursor:pointer" title="Remove filter">)
		  . qq($delete</a> $label);
	}
	my $buffer = qq(<label for="$id" class="$class" $title_attribute>$label</label>\n);
	unshift @$values, '' if !$options->{'noblank'};
	$options->{'labels'}->{''} = '&nbsp;';    #Required for HTML5 validation.
	my %args = (
		-name   => "$name\_list",
		-id     => $id,
		-values => $values,
		-labels => $options->{'labels'},
		-class  => $class,
		-style  => 'max-width:20em'
	);
	if ( $options->{'multiple'} ) {
		$args{'-multiple'} = 'multiple';
		$args{'-size'} = ( @$values < 4 ) ? @$values : 4;
		my @selected = $q->multi_param("${name}_list");
		$args{'-default'} =
		  \@selected;    #Not sure why this should be necessary, but only the first selection seems to stick.
		$args{'-override'} = 1;
		$args{'-class'}    = 'multiselect';
	}

	#Page::popup_menu faster than CGI::popup_menu as it doesn't escape values.
	$buffer .= ( $args{'-class'} // '' ) eq 'multiselect' ? $q->scrolling_list(%args) : $self->popup_menu(%args);
	if ( $options->{'tooltip'} ) {
		$options->{'tooltip'} =~ tr/_/ /;
		$buffer .= $self->get_tooltip( $options->{'tooltip'} );
	}
	return $buffer;
}

sub get_user_filter {
	my ( $self, $field, $args ) = @_;
	$args = {} if ref $args ne 'HASH';
	my $options = $field =~ /^curator/x ? { curators => 1 } : {};
	my ( $users, $labels ) = $self->{'datastore'}->get_users($options);
	my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
	return $self->get_filter(
		$field, $users,
		{
			labels  => $labels,
			tooltip => qq($field filter - Select $a_or_an $field to filter your search to only )
			  . qq(those records that match the selected $field.),
			%$args
		}
	);
}

sub get_number_records_control {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $self->{'cgi'}->param('displayrecs');
	}
	my $buffer = q(<span style="white-space:nowrap"><label for="displayrecs" class="display">Display: </label>);
	$buffer .= $self->{'cgi'}->popup_menu(
		-name   => 'displayrecs',
		-id     => 'displayrecs',
		-values => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $self->{'cgi'}->param('displayrecs') || $self->{'prefs'}->{'displayrecs'}
	);
	$buffer .= q( records per page);
	$buffer .=
	  $self->get_tooltip(q(Records per page - Analyses use the full query dataset, rather than just the page shown.));
	$buffer .= q(</span>);
	return $buffer;
}

sub get_scheme_filter {
	my ( $self, $options ) = @_;
	if ( !$self->{'cache'}->{'schemes'} ) {
		my $set_id = $self->get_set_id;
		my $list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => $options->{'with_pk'} } );
		foreach my $scheme (@$list) {
			push @{ $self->{'cache'}->{'schemes'} }, $scheme->{'id'};
			$self->{'cache'}->{'scheme_labels'}->{ $scheme->{'id'} } = $scheme->{'name'};
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
			tooltip => 'scheme filter - Select a scheme to filter your search to '
			  . 'only those belonging to the selected scheme.'
		}
	);
	return $buffer;
}

sub get_locus_filter {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	my $buffer =
	  $self->get_filter( 'locus', $loci,
		{ labels => $labels, tooltip => 'locus filter - Select a locus to filter your search by.' } );
	return $buffer;
}

sub get_old_version_filter {
	my ($self) = @_;
	my $buffer =
	  $self->{'cgi'}->checkbox( -name => 'include_old', -id => 'include_old', -label => 'Include old record versions' );
	return $buffer;
}

sub get_isolate_publication_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( $self->{'config'}->{'ref_db'} ) {
		my $view = $self->{'system'}->{'view'};
		my $pmid =
		  $self->{'datastore'}
		  ->run_query( "SELECT DISTINCT(pubmed_id) FROM refs JOIN $view ON refs.isolate_id=$view.id ",
			undef, { fetch => 'col_arrayref' } );
		my $buffer;
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { uc( $labels->{$a} ) cmp uc( $labels->{$b} ) } keys %$labels;
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
					tooltip  => q(publication filter - Select publications to filter your )
					  . q(search to only those isolates referred by them.)
				}
			);
		}
	}
	return '';
}

sub get_project_filter {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $args = [];
	my $qry  = 'SELECT id,short_description FROM projects WHERE id IN (SELECT project_id FROM project_members WHERE '
	  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})) AND (NOT private";
	if ( $self->{'username'} ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$qry .= ' OR id IN (SELECT project_id FROM merged_project_users WHERE user_id=?)';
		push @$args, $user_info->{'id'};
	}
	$qry .= ') ORDER BY UPPER(short_description)';
	my $projects = $self->{'datastore'}->run_query( $qry, $args, { fetch => 'all_arrayref', slice => {} } );
	my ( @project_ids, %labels );
	foreach my $project (@$projects) {
		push @project_ids, $project->{'id'};
		$labels{ $project->{'id'} } = $project->{'short_description'};
	}
	if ( @project_ids && $options->{'any'} ) {
		unshift @project_ids, 'none';
		$labels{'none'} = 'not belonging to any project';
		unshift @project_ids, 'any';
		$labels{'any'} = 'belonging to any project';
	}
	if (@project_ids) {
		my $class = $options->{'class'} || 'filter';
		my $tooltip = 'project filter - Select projects to filter your query to only those isolates belonging to them.';
		$args = { labels => \%labels, text => 'Project', tooltip => $tooltip, class => $class };
		if ( $options->{'multiple'} ) {
			$args->{'multiple'} = 1;
			$args->{'noblank'}  = 1;
		}
		return $self->get_filter( 'project', \@project_ids, $args );
	}
	return '';
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
	my $ellipsis = $options->{'no_html'} ? '...' : '&hellip;';
	$length //= 25;
	my $title;
	if ( length $label > $length ) {
		$title = $label;
		$title =~ tr/\"//;
		$label = substr( $label, 0, $length - 5 ) . $ellipsis;
	}
	if ( $options->{'capitalize_first'} && ( $label =~ /^[a-z]+\s+/x || $label =~ /^[a-z]+\:\s$/x ) )
	{    #only if first word is all lower case
		$label = ucfirst $label;
		$title = ucfirst $title if $title;
	}
	return ( $label, $title );
}

sub get_scheme_flags {
	my ( $self, $scheme_id, $options ) = @_;
	my $buffer = q();
	return $buffer if !BIGSdb::Utils::is_int($scheme_id);
	my $flags = $self->{'datastore'}->run_query( 'SELECT flag FROM scheme_flags WHERE scheme_id=?',
		$scheme_id, { fetch => 'col_arrayref', cache => 'DownloadAlleles::flags' } );
	if (@$flags) {
		my $colours = SCHEME_FLAG_COLOURS;
		$buffer .= q(<div class="flags">);
		if ( $options->{'link'} ) {
			$buffer .= qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=schemeInfo&amp;scheme_id=$scheme_id">);
		}
		foreach my $flag (@$flags) {
			$buffer .= qq(<span class="flag" style="color:$colours->{$flag}">$flag</span>\n);
		}
		if ( $options->{'link'} ) {
			$buffer .= q(</a>);
		}
		$buffer .= q(</div>);
	}
	return $buffer;
}

sub clean_locus {
	my ( $self, $locus, $options ) = @_;
	return if !defined $locus;
	$options = {} if ref $options ne 'HASH';
	my $set_id = $self->get_set_id;
	my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
	my $formatting_defined;
	if ( $set_id && $locus_info->{'set_name'} ) {
		$locus = $locus_info->{'set_name'};
		if ( !$options->{'text_output'} && $locus_info->{'formatted_set_name'} ) {
			$locus              = $locus_info->{'formatted_set_name'};
			$formatting_defined = 1;
		}
		if ( !$options->{'no_common_name'} ) {
			my $common_name = '';
			$common_name = " ($locus_info->{'set_common_name'})" if $locus_info->{'set_common_name'};
			if ( !$options->{'text_output'} && $locus_info->{'formatted_set_common_name'} ) {
				$common_name        = " ($locus_info->{'formatted_set_common_name'})";
				$formatting_defined = 1;
			}
			$locus .= $common_name;
		}
	} else {
		if ( !$options->{'text_output'} && $locus_info->{'formatted_name'} ) {
			$locus              = $locus_info->{'formatted_name'};
			$formatting_defined = 1;
		}
		if ( !$options->{'no_common_name'} ) {
			my $common_name = '';
			$common_name = " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			if ( !$options->{'text_output'} && $locus_info->{'formatted_common_name'} ) {
				$common_name        = " ($locus_info->{'formatted_common_name'})";
				$formatting_defined = 1;
			}
			$locus .= $common_name;
		}
	}
	if ( !$options->{'text_output'} ) {
		if ( !$formatting_defined ) {
			if ( ( $self->{'system'}->{'locus_superscript_prefix'} // '' ) eq 'yes' ) {
				$locus =~ s/^([A-Za-z]{1,3})_/<sup>$1<\/sup>/x;
			}
		}
		if ( $options->{'strip_links'} ) {
			$locus =~ s/<[a|A]\s+[href|HREF].+?>//gx;
			$locus =~ s/<\/[a|A]>//gx;
		}
	}
	return $locus;
}

sub get_set_id {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		my $set_id = $self->{'system'}->{'set_id'} // $q->param('set_id') // $self->{'prefs'}->{'set_id'};
		return $set_id if $set_id && BIGSdb::Utils::is_int($set_id);
	}
	return if !$self->{'datastore'};
	if ( ( $self->{'system'}->{'only_sets'} // '' ) eq 'yes' && !$self->{'curate'} ) {
		if ( !$self->{'cache'}->{'set_list'} ) {
			$self->{'cache'}->{'set_list'} =
			  $self->{'datastore'}->run_query( 'SELECT id FROM sets ORDER BY display_order,description',
				undef, { fetch => 'col_arrayref' } );
		}
		return $self->{'cache'}->{'set_list'}->[0] if @{ $self->{'cache'}->{'set_list'} };
	}
	return;
}

sub extract_scheme_desc {
	my ( $self, $scheme_data ) = @_;
	my ( @scheme_ids, %desc );
	foreach my $scheme (@$scheme_data) {
		push @scheme_ids, $scheme->{'id'};
		$desc{ $scheme->{'id'} } = $scheme->{'name'};
	}
	return ( \@scheme_ids, \%desc );
}

sub get_db_description {
	my ( $self, $options ) = @_;
	my $desc;

	#Simple conversion of markdown (bold and italics) to HTML.
	if ( $options->{'formatted'} ) {
		$desc = $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'};
		$desc =~ s/\*\*(.*?)\*\*/<strong>$1\<\/strong>/gx;
		$desc =~ s/\*(.*?)\*/<em>$1\<\/em>/gx;
	} else {
		$desc = $self->{'system'}->{'description'};
	}
	return $desc if $self->{'system'}->{'sets'} && $self->{'system'}->{'set_id'};
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $desc_ref =
		  $self->{'datastore'}->run_query( 'SELECT * FROM sets WHERE id=?', $set_id, { fetch => 'row_hashref' } );
		$desc .= ' (' . $desc_ref->{'description'} . ')' if $desc_ref->{'description'} && !$desc_ref->{'hidden'};
	}
	$desc =~ s/\&/\&amp;/gx;
	return $desc;
}

sub get_link_button_to_ref {
	my ( $self, $ref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	my $qry = "SELECT COUNT(refs.isolate_id) FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id="
	  . "$self->{'system'}->{'view'}.id WHERE pubmed_id=? AND new_version IS NULL";
	my $count = $self->{'datastore'}->run_query( $qry, $ref, { cache => 'Page::link_ref' } );
	my $plural = $count == 1 ? '' : 's';
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form( -style => 'display:inline;margin-left:0.5em' );
	$q->param( curate => 1 ) if $self->{'curate'};
	$q->param( pmid   => $ref );
	$q->param( page   => 'pubquery' );
	$buffer .= $q->hidden($_) foreach qw(db page curate pmid set_id);
	$buffer .= $q->submit( -value => "$count isolate$plural", -class => $options->{'class'} // 'small_submit' );
	$buffer .= $q->end_form;
	$q->param( page => 'info' );
	return $buffer;
}

sub get_isolate_name_from_id {
	my ( $self, $isolate_id ) = @_;
	my $isolate =
	  $self->{'datastore'}
	  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
		$isolate_id, { cache => 'Page::get_isolate_name_from_id' } );
	return $isolate // '';
}

sub get_isolate_id_and_name_from_seqbin_id {
	my ( $self, $seqbin_id ) = @_;
	my $view        = $self->{'system'}->{'view'};
	my $label_field = $self->{'system'}->{'labelfield'};
	return $self->{'datastore'}->run_query(
		qq(SELECT $view.id,$view.$label_field FROM $view LEFT JOIN sequence_bin )
		  . qq(ON $view.id = isolate_id WHERE sequence_bin.id=?),
		$seqbin_id,
		{ cache => 'Page::get_isolate_id_and_name_from_seqbin_id' }
	);
}

#Return list and formatted labels
sub get_isolates_with_seqbin {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $view = $self->{'system'}->{'view'};
	my $qry;
	if ( $options->{'use_all'} ) {
		$qry = "SELECT $view.id,$view.$self->{'system'}->{'labelfield'},new_version FROM $view ORDER BY $view.id";
	} else {
		$qry = "SELECT $view.id,$view.$self->{'system'}->{'labelfield'},new_version FROM $view WHERE EXISTS "
		  . "(SELECT * FROM seqbin_stats WHERE $view.id=seqbin_stats.isolate_id) ORDER BY $view.id";
	}
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	my @ids;
	my %labels;
	foreach (@$data) {
		my ( $id, $isolate, $new_version ) = @$_;
		$isolate //= '';    #One database on PubMLST uses a restricted view that hides some isolate names.
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
		curator                           => 'curator permission record',
		client_dbases                     => 'client database',
		client_dbase_loci                 => 'locus to client database definition',
		client_dbase_schemes              => 'scheme to client database definition',
		locus_extended_attributes         => 'locus extended attribute',
		projects                          => 'project description',
		project_members                   => 'project member',
		profile_refs                      => 'Pubmed link',
		scheme_curators                   => 'scheme curator access record',
		locus_curators                    => 'locus curator access record',
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
		set_view                          => 'database view linked to set',
		history                           => 'update record',
		profile_history                   => 'profile update record',
		sequence_attributes               => 'sequence attribute',
		retired_allele_ids                => 'retired allele id',
		retired_profiles                  => 'retired profile',
		retired_isolates                  => 'retired isolate id',
		classification_schemes            => 'classification scheme',
		classification_group_fields       => 'classification group field',
		classification_group_field_values => 'classification group field value',
		user_dbases                       => 'user database',
		locus_links                       => 'locus link',
		oauth_credentials                 => 'OAuth credentials',
		eav_fields                        => 'sparse field',
		eav_field_groups                  => 'sparse field group member',
		client_dbase_cschemes             => 'classification scheme to client database definition',
		validation_conditions             => 'validation condition',
		validation_rules                  => 'validation rule',
		validation_rule_conditions        => 'rule condition',
		lincode_schemes                   => 'LINcode scheme',
		lincode_fields                    => 'LINcode field',
		lincode_prefixes                  => 'LINcode prefix nomenclature',
		codon_tables                      => 'isolate codon table',
		sequence_extended_attributes      => 'sequence extended attribute',
		geography_point_lookup            => 'geography point lookup value',
		curator_configs                   => 'curator database configuration'
	);
	return $names{$table};
}

sub rewrite_query_ref_order_by {
	my ( $self, $qry_ref ) = @_;
	my $view = $self->{'system'}->{'view'};
	if ( $$qry_ref =~ /ORDER\ BY\ s_(\d+)_\S+\s/x ) {
		my $scheme_id            = $1;
		my $isolate_scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $scheme_join          = "LEFT JOIN $isolate_scheme_table AS ordering ON $view.id=ordering.id";
		$$qry_ref =~ s/FROM\ $view/FROM $view $scheme_join/x;
		$$qry_ref =~ s/ORDER\ BY\ s_(\d+)_/ORDER BY ordering\./x;
	} elsif ( $$qry_ref =~ /ORDER\ BY\ l_(\S+)\s/x ) {
		my $locus = $1;
		( my $cleaned_locus = $locus ) =~ s/'/\\'/gx;
		my $join = qq(LEFT JOIN allele_designations AS ordering ON ordering.isolate_id=$view.id )
		  . qq(AND ordering.locus=E'$cleaned_locus');
		$$qry_ref =~ s/FROM\ $view/FROM $view $join/x;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$$qry_ref =~ s/ORDER\ BY\ l_\S+\s/ORDER BY CAST(ordering.allele_id AS int) /x;
		} else {
			$$qry_ref =~ s/ORDER\ BY\ l_\S+\s/ORDER BY ordering.allele_id /x;
		}
	} elsif ( $$qry_ref =~ /ORDER\ BY\ f_(\S+)/x ) {
		my $field = $1;
		$$qry_ref =~ s/ORDER BY f_/ORDER BY $view\./;
	}
	return;
}

sub is_allowed_to_view_isolate {
	my ( $self, $isolate_id ) = @_;
	my $allowed =
	  $self->{'datastore'}->run_query( "SELECT EXISTS (SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
		$isolate_id, { cache => 'is_allowed_to_view_isolate' } );
	return $allowed;
}

sub get_update_details_tooltip {
	my ( $self, $locus, $allele_ref ) = @_;
	my $buffer;
	my $sender  = $self->{'datastore'}->get_user_info( $allele_ref->{'sender'} );
	my $curator = $self->{'datastore'}->get_user_info( $allele_ref->{'curator'} );
	$buffer = qq($locus:$allele_ref->{'allele_id'} - ) . qq(sender: $sender->{'first_name'} $sender->{'surname'}<br />);
	$buffer .= qq(status: $allele_ref->{'status'}<br />) if $allele_ref->{'status'};
	$buffer .=
	    qq(method: $allele_ref->{'method'}<br />)
	  . qq(curator: $curator->{'first_name'} $curator->{'surname'}<br />)
	  . qq(first entered: $allele_ref->{'date_entered'}<br />)
	  . qq(last updated: $allele_ref->{'datestamp'}<br />);
	$buffer .= qq(comments: $allele_ref->{'comments'}<br />) if $allele_ref->{'comments'};
	return $buffer;
}

sub _get_seq_detail_tooltip_text {
	my ( $self, $locus, $allele_designations, $allele_sequences, $flags_ref ) = @_;
	my @allele_ids;
	push @allele_ids, $_->{'allele_id'} foreach @$allele_designations;
	local $" = ', ';
	my $buffer = @allele_ids ? qq($locus:@allele_ids - ) : qq($locus - );
	my $i = 0;
	local $" = '; ';
	foreach (@$allele_sequences) {
		$buffer .= q(<br />)      if $i;
		$buffer .= qq(Seqbin id:$_->{'seqbin_id'}: $_->{'start_pos'} &rarr; $_->{'end_pos'});
		$buffer .= q( (reverse))  if $_->{'reverse'};
		$buffer .= q( incomplete) if !$_->{'complete'};
		if ( ref $flags_ref->[$i] eq 'ARRAY' ) {
			my @flags = sort @{ $flags_ref->[$i] };
			$buffer .= qq(<br />@flags) if @flags;
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
	my $allele_sequences = $self->_get_isolate_allele_sequence( $isolate_id, $locus, $options );
	my $designations     = $self->_get_isolate_allele_designation( $isolate_id, $locus, $options );
	my $locus_info       = $self->{'datastore'}->get_locus_info($locus);
	my $designation_flags;
	my ( @all_flags, %flag_from_designation, %flag_from_alleleseq );

	if ( $options->{'allele_flags'} ) {
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
				$self->{'cache'}->{'sequence_flags'}->{$isolate_id} =
				  $self->{'datastore'}->get_all_sequence_flags($isolate_id);
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
	  $self->_get_seq_detail_tooltip_text( $cleaned_locus, $designations, $allele_sequences,
		\@flags_foreach_alleleseq );
	if (@$allele_sequences) {
		my $set_id         = $self->get_set_id;
		my $set_clause     = $set_id ? qq(&amp;set_id=$set_id) : q();
		my $sequence_class = $complete ? 'sequence_tooltip' : 'sequence_tooltip_incomplete';
		$buffer .=
		    qq(<span style="font-size:0.2em"> </span><a class="$sequence_class" title="$sequence_tooltip" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleSequence$set_clause&amp;)
		  . qq(id=$isolate_id&amp;locus=$locus">&nbsp;S&nbsp;</a>);
	}
	if (@all_flags) {
		my $text = 'Flags - ';
		foreach my $flag (@all_flags) {
			$text .= $flag;
			if ( $options->{'allele_flags'} ) {
				if ( $flag_from_designation{$flag} && !$flag_from_alleleseq{$flag} ) {
					$text .= q( (allele designation)<br />);
				} elsif ( !$flag_from_designation{$flag} && $flag_from_alleleseq{$flag} ) {
					$text .= q( (sequence tag)<br />);
				} else {
					$text .= q( (designation + tag)<br />);
				}
			} else {
				$text .= q(<br />);
			}
		}
		local $" = qq(</a> <a class="seqflag_tooltip" title="$text">);
		$buffer .= qq(<a class="seqflag_tooltip" title="$text">@all_flags</a>);
	}
	return $buffer;
}

sub _get_isolate_allele_sequence {
	my ( $self, $isolate_id, $locus, $options ) = @_;
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
	return $allele_sequences;
}

sub _get_isolate_allele_designation {
	my ( $self, $isolate_id, $locus, $options ) = @_;
	my $designations = [];
	if ( $options->{'get_all'} ) {
		if ( !$self->{'cache'}->{'allele_designations'}->{$isolate_id} ) {
			$self->{'cache'}->{'allele_designations'}->{$isolate_id} =
			  $self->{'datastore'}->get_all_allele_designations($isolate_id);
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
	return $designations;
}

sub make_temp_file {
	my ( $self, @list ) = @_;
	my ( $filename, $full_file_path );
	do {
		$filename       = BIGSdb::Utils::get_random();
		$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	} while ( -e $full_file_path );
	open( my $fh, '>:encoding(utf8)', $full_file_path ) || $logger->error("Can't open $full_file_path for writing");
	local $" = "\n";
	print $fh "@list";
	close $fh;
	return $filename;
}

sub get_query_from_temp_file {
	my ( $self, $file ) = @_;
	return if !defined $file;
	$file = $file =~ /([\w\.]+)/x ? $1 : undef;    #untaint
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$file";
	if ( -e $full_path ) {
		open( my $fh, '<:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for reading");
		my $qry = <$fh>;
		close $fh;
		return $qry;
	}
	return;
}

sub is_admin {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} eq 'user';
	if ( $self->{'username'} ) {
		my $status = $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?',
			$self->{'username'}, { cache => 'Page::is_admin' } );
		return   if !$status;
		return 1 if $status eq 'admin';
	}
	return;
}

sub can_delete_all {
	my ($self) = @_;
	return 1 if $self->{'permissions'}->{'delete_all'} || $self->is_admin;
	return;
}

sub can_modify_table {
	my ( $self, $table ) = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $locus     = $q->param('locus');
	$locus =~ s/%27/'/gx if $locus;    #Web-escaped locus
	return if $table eq 'history' || $table eq 'profile_history';
	return 1 if $self->is_admin;
	my $curator_id = $self->get_curator_id;

	if ( !defined $self->{'cache'}->{'curator_configs'} ) {
		my $curator_configs =
		  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM curator_configs WHERE user_id=?',
			$curator_id, { fetch => 'col_arrayref' } );
		$self->{'cache'}->{'curator_configs'} = { map { $_ => 1 } @$curator_configs };
	}
	if ( keys %{ $self->{'cache'}->{'curator_configs'} }
		&& !$self->{'cache'}->{'curator_configs'}->{ $self->{'instance'} } )
	{
		return;
	}
	my %general_permissions = (
		users              => $self->{'permissions'}->{'modify_users'},
		user_groups        => $self->{'permissions'}->{'modify_usergroups'},
		user_group_members => $self->{'permissions'}->{'modify_usergroups'},
	);
	$general_permissions{$_} = $self->{'permissions'}->{'modify_loci'}
	  foreach qw(loci locus_aliases client_dbases client_dbase_loci client_dbase_schemes
	  locus_client_display_fields locus_extended_attributes locus_curators);
	$general_permissions{$_} = $self->{'permissions'}->{'modify_schemes'}
	  foreach qw(schemes scheme_members scheme_fields scheme_curators classification_schemes
	  classification_group_fields scheme_groups scheme_group_group_members scheme_group_scheme_members
	  lincode_schemes);
	if ( $general_permissions{$table} ) {
		return $general_permissions{$table};
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {

		#Isolate only tables
		my %isolate_permissions = (
			allele_designations               => $self->{'permissions'}->{'designate_alleles'},
			sequence_bin                      => $self->{'permissions'}->{'modify_sequences'},
			allele_sequences                  => $self->{'permissions'}->{'tag_sequences'},
			isolate_field_extended_attributes => $self->{'permissions'}->{'modify_field_attributes'},
			isolate_value_extended_attributes => $self->{'permissions'}->{'modify_value_attributes'},
			eav_fields                        => $self->{'permissions'}->{'modify_sparse_fields'},
			geography_point_lookup            => $self->{'permissions'}->{'modify_geopoints'}
		);
		$isolate_permissions{$_} = $self->{'permissions'}->{'modify_isolates'}
		  foreach qw(isolates isolate_aliases refs);
		my $user_info = $self->{'datastore'}->get_user_info($curator_id);
		$isolate_permissions{'retired_isolates'} = $self->{'permissions'}->{'modify_isolates'}
		  if $user_info->{'status'} eq 'curator';
		$isolate_permissions{$_} = $self->{'permissions'}->{'modify_composites'}
		  foreach qw(composite_fields composite_field_values);
		$isolate_permissions{$_} = $self->{'permissions'}->{'modify_projects'} foreach qw(projects project_members);
		$isolate_permissions{$_} = $self->{'permissions'}->{'modify_probes'}
		  foreach qw(pcr pcr_locus probes probe_locus);

		if ( $isolate_permissions{$table} ) {
			return $isolate_permissions{$table};
		}
	} else {    #Sequence definition database only tables

		#Locus descriptions/links. Checks for specific loci are in next section
		my %desc_tables = map { $_ => 1 } qw (locus_descriptions locus_links);
		if ( $desc_tables{$table} ) {
			return if !$self->{'permissions'}->{'modify_locus_descriptions'};
		}

		#Alleles and locus descriptions
		my %seq_tables =
		  map { $_ => 1 } qw (sequences locus_descriptions locus_links retired_allele_ids sequence_extended_attributes);
		if ( $seq_tables{$table} ) {
			return 1 if !$locus;
			return $self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id );
		}

		#Profile refs and retired profiles
		my %general_profile_tables = map { $_ => 1 } qw(profile_refs retired_profiles);
		if ( $general_profile_tables{$table} ) {
			return $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM scheme_curators WHERE curator_id=?)', $self->get_curator_id );
		}

		#Profiles
		my %profile_tables = map { $_ => 1 } qw (profiles profile_fields profile_members);
		if ( $profile_tables{$table} ) {
			return 0 if !$scheme_id;
			return $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM scheme_curators WHERE scheme_id=? AND curator_id=?)',
				[ $scheme_id, $self->get_curator_id ] );
		}

		#Sequence refs
		my %seq_ref_tables = map { $_ => 1 } qw(sequence_refs accession);
		return $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM locus_curators WHERE curator_id=?)', $self->get_curator_id )
		  if ( $seq_ref_tables{$table} );
	}

	#Default deny
	return;
}

sub get_curator_id {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'curator_id'} ) {
		if ( $self->{'username'} ) {
			my $qry = 'SELECT id,status FROM users WHERE user_name=?';
			my $values = $self->{'datastore'}->run_query( $qry, $self->{'username'}, { fetch => 'row_hashref' } );
			return 0 if !$values;
			if ( ( $values->{'status'} // '' ) eq 'user' ) {
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
	my ( $self, $id, $options ) = @_;
	if ( $options->{'has_seqbin'} ) {
		return $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'} v JOIN "
			  . 'seqbin_stats s ON v.id=s.isolate_id WHERE v.id=?)',
			$id,
			{ cache => 'Page::isolate_exists::has_seqbin' }
		);
	}
	return $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'} WHERE id=?)",
		$id, { cache => 'Page::isolate_exists' } );
}

sub dashboard_enabled {
	my ( $self, $options ) = @_;
	return if !$self->{'config'}->{'enable_dashboard'} && ( $self->{'system'}->{'enable_dashboard'} // q() ) ne 'yes';
	return if ( $self->{'system'}->{'enable_dashboard'} // q() ) eq 'no';
	return
	     if $options->{'query_dashboard'}
	  && ( $self->{'config'}->{'query_dashboard'} // 1 ) == 0
	  && ( $self->{'system'}->{'query_dashboard'} // 'no' ) eq 'no';
	return
	     if $options->{'query_dashboard'}
	  && ( $self->{'config'}->{'query_dashboard'} // 1 ) == 1
	  && ( $self->{'system'}->{'query_dashboard'} // 'yes' ) eq 'no';
	return 1;
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
	catch {
		if ( $_->isa('BIGSdb::Exception::Prefstore') ) {
			undef $self->{'prefstore'};
			$self->{'fatal'} = 'prefstoreConfig';
		} else {
			$logger->logdie($_);
		}
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
		$self->{'prefs'}->{'set_id'} =
		  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'set_id' )
		  if $self->{'pref_requirements'}->{'general'};
	} else {
		return if !$self->{'pref_requirements'}->{'general'} && !$self->{'pref_requirements'}->{'query_field'};
		return if !$self->{'prefstore'};
		my $dbname = $self->{'system'}->{'db'};
		$field_prefs = $self->{'prefstore'}->get_all_field_prefs( $guid, $dbname );
		$scheme_field_prefs = $self->{'prefstore'}->get_all_scheme_field_prefs( $guid, $dbname );
		if ( $self->{'pref_requirements'}->{'general'} ) {
			$general_prefs = $self->{'prefstore'}->get_all_general_prefs( $guid, $dbname );
			$self->_initiate_general_prefs( $guid, $general_prefs );
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_initiate_isolatedb_prefs( $general_prefs, $field_prefs, $scheme_field_prefs );
	} else {
		$self->_initiate_seqdefdb_prefs;
	}

	#Set dropdown status for scheme fields
	if ( $self->{'pref_requirements'}->{'query_field'} ) {
		my $dbname = $self->{'system'}->{'db'};
		my $scheme_ids =
		  $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
		my $scheme_fields              = $self->{'datastore'}->get_all_scheme_fields;
		my $scheme_field_default_prefs = $self->{'datastore'}->get_all_scheme_field_info;
		foreach my $scheme_id (@$scheme_ids) {
			foreach my $field ( @{ $scheme_fields->{$scheme_id} } ) {
				if ( defined $scheme_field_prefs->{$scheme_id}->{$field}->{'dropdown'} ) {
					$self->{'prefs'}->{'dropdown_scheme_fields'}->{$scheme_id}->{$field} =
					  $scheme_field_prefs->{$scheme_id}->{$field}->{'dropdown'} ? 1 : 0;
				} else {
					$self->{'prefs'}->{'dropdown_scheme_fields'}->{$scheme_id}->{$field} =
					  $scheme_field_default_prefs->{$scheme_id}->{$field}->{'dropdown'};
				}
			}
		}
	}
	$self->{'datastore'}->update_prefs( $self->{'prefs'} );
	return;
}

sub _initiate_general_prefs {
	my ( $self, $guid, $general_prefs ) = @_;
	$self->{'prefs'}->{'displayrecs'} = $general_prefs->{'displayrecs'} // 25;
	$self->{'prefs'}->{'pagebar'}     = $general_prefs->{'pagebar'}     // 'top and bottom';
	$self->{'prefs'}->{'alignwidth'}  = $general_prefs->{'alignwidth'}  // 100;
	$self->{'prefs'}->{'flanking'}    = $general_prefs->{'flanking'}    // 100;
	foreach (
		qw(set_id submit_allele_technology submit_allele_read_length
		submit_allele_coverage submit_allele_assembly submit_allele_software)
	  )
	{
		$self->{'prefs'}->{$_} = $general_prefs->{$_};
	}

	#default off
	foreach (qw (hyperlink_loci )) {
		$general_prefs->{$_} //= 'off';
		$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'on' ? 1 : 0;
	}

	#default on
	foreach (qw (tooltips submit_email)) {
		$general_prefs->{$_} //= 'on';
		$self->{'prefs'}->{$_} = $general_prefs->{$_} eq 'off' ? 0 : 1;
	}
	return;
}

sub _initiate_isolatedb_prefs {
	my ( $self, $general_prefs, $field_prefs, $scheme_field_prefs ) = @_;
	my $q                = $self->{'cgi'};
	my $set_id           = $self->get_set_id;
	my $field_list       = $self->{'xmlHandler'}->get_field_list;
	my $eav_field_list   = $self->{'datastore'}->get_eav_fieldnames;
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	my $extended         = $self->get_extended_attributes;
	my $args             = {
		field_list       => $field_list,
		eav_field_list   => $eav_field_list,
		field_prefs      => $field_prefs,
		extended         => $extended,
		field_attributes => $field_attributes
	};

	#Parameters set by preference store via session cookie
	if ( $q->param('page') eq 'options' && $q->param('set') ) {
		$self->_set_isolatedb_options($args);
	} else {
		my $guid = $self->get_guid || 1;
		my $dbname = $self->{'system'}->{'db'};
		$self->_initiate_isolatedb_general_prefs($general_prefs) if $self->{'pref_requirements'}->{'general'};
		$self->_initiate_isolatedb_query_field_prefs($args)      if $self->{'pref_requirements'}->{'query_field'};
		$self->_initiate_isolatedb_main_display_prefs($args)     if $self->{'pref_requirements'}->{'main_display'};
		return if none { $self->{'pref_requirements'}->{$_} } qw (isolate_display main_display query_field analysis);
		$self->_initiate_isolatedb_locus_prefs( $guid, $dbname );
		$self->_initiate_isolatedb_scheme_prefs( $guid, $dbname, $field_prefs, $scheme_field_prefs );
	}
	return;
}

sub _initiate_seqdefdb_prefs {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $guid          = $self->get_guid || 1;
	my $dbname        = $self->{'system'}->{'db'};
	my $scheme_values = $self->{'prefstore'}->get_all_scheme_prefs( $guid, $dbname );
	my $set_id        = $self->get_set_id;
	my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $scheme_info   = $self->{'datastore'}->get_all_scheme_info;
	foreach my $scheme (@$schemes) {

		if ( defined $scheme_values->{ $scheme->{'id'} }->{'disable'} ) {
			$self->{'prefs'}->{'disable_schemes'}->{ $scheme->{'id'} } =
			  $scheme_values->{ $scheme->{'id'} }->{'disable'} ? 1 : 0;
		} else {
			$self->{'prefs'}->{'disable_schemes'}->{ $scheme->{'id'} } =
			  $scheme_info->{ $scheme->{'id'} }->{'disable'};
		}
	}
	return;
}

sub _set_isolatedb_options {
	my ( $self, $args ) = @_;
	my ( $field_list, $eav_field_list, $extended ) = @{$args}{qw(field_list eav_field_list extended)};
	my $q      = $self->{'cgi'};
	my $params = $q->Vars;

	#Switches
	foreach my $option (
		qw ( update_details sequence_details allele_flags mark_provisional mark_provisional_main
		sequence_details_main display_seqbin_main display_contig_count locus_alias scheme_members_alias
		display_publications query_dashboard)
	  )
	{
		$self->{'prefs'}->{$option} = $params->{$option} ? 1 : 0;
	}
	foreach my $field (@$field_list) {
		if ( $field ne 'id' ) {
			$self->{'prefs'}->{'maindisplayfields'}->{$field} = $params->{"field_$field"}     ? 1 : 0;
			$self->{'prefs'}->{'dropdownfields'}->{$field}    = $params->{"dropfield_$field"} ? 1 : 0;
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					$self->{'prefs'}->{'maindisplayfields'}->{"${field}..$extended_attribute"} =
					  $params->{"extended_${field}..$extended_attribute"} ? 1 : 0;
					$self->{'prefs'}->{'dropdownfields'}->{"${field}..$extended_attribute"} =
					  $params->{"dropfield_e_${field}..$extended_attribute"} ? 1 : 0;
				}
			}
		}
	}
	foreach my $field (@$eav_field_list) {
		$self->{'prefs'}->{'maindisplayfields'}->{$field} = $params->{"field_$field"} ? 1 : 0;
	}
	$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $params->{'field_aliases'} ? 1 : 0;
	my $composites =
	  $self->{'datastore'}->run_query( 'SELECT id FROM composite_fields', undef, { fetch => 'col_arrayref' } );
	foreach my $field (@$composites) {
		$self->{'prefs'}->{'maindisplayfields'}->{$field} = $params->{"field_$field"} ? 1 : 0;
	}
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	foreach my $scheme_id (@$schemes) {
		my $field = "scheme_${scheme_id}_profile_status";
		$self->{'prefs'}->{'dropdownfields'}->{$field} = $params->{"dropfield_$field"} ? 1 : 0;
	}
	return;
}

sub _initiate_isolatedb_general_prefs {
	my ( $self, $general_prefs ) = @_;

	#default off
	foreach my $option (
		qw (update_details allele_flags scheme_members_alias sequence_details_main
		display_seqbin_main display_contig_count display_publications)
	  )
	{
		$general_prefs->{$option} //= 'off';
		$self->{'prefs'}->{$option} = $general_prefs->{$option} eq 'on' ? 1 : 0;
	}

	#default on
	foreach my $option (qw (sequence_details mark_provisional mark_provisional_main query_dashboard)) {
		$general_prefs->{$option} //= 'on';
		$self->{'prefs'}->{$option} = $general_prefs->{$option} eq 'off' ? 0 : 1;
	}

	#Locus aliases - default off
	my $default_locus_aliases = ( $self->{'system'}->{'locus_aliases'} // '' ) eq 'yes' ? 'on' : 'off';
	$general_prefs->{'locus_alias'} //= $default_locus_aliases // 'off';
	$self->{'prefs'}->{'locus_alias'} = $general_prefs->{'locus_alias'} eq 'on' ? 1 : 0;
	return;
}

sub _initiate_isolatedb_query_field_prefs {
	my ( $self, $args ) = @_;
	my ( $field_list, $field_prefs, $field_attributes, $extended ) =
	  @{$args}{qw(field_list field_prefs field_attributes extended)};
	foreach my $field (@$field_list) {
		next if $field eq 'id';
		if ( defined $field_prefs->{$field}->{'dropdown'} ) {
			$self->{'prefs'}->{'dropdownfields'}->{$field} = $field_prefs->{$field}->{'dropdown'};
		} else {
			$field_attributes->{$field}->{'dropdown'} ||= 'no';
			$self->{'prefs'}->{'dropdownfields'}->{$field} =
			  $field_attributes->{$field}->{'dropdown'} eq 'yes' ? 1 : 0;
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( defined $field_prefs->{"${field}..$extended_attribute"}->{'dropdown'} ) {
					$self->{'prefs'}->{'dropdownfields'}->{"${field}..$extended_attribute"} =
					  $field_prefs->{"${field}..$extended_attribute"}->{'dropdown'};
				} else {
					$self->{'prefs'}->{'dropdownfields'}->{"${field}..$extended_attribute"} = 0;
				}
			}
		}
	}
	return;
}

sub _initiate_isolatedb_main_display_prefs {
	my ( $self, $args ) = @_;
	my ( $field_list, $eav_field_list, $field_prefs, $field_attributes, $extended ) =
	  @{$args}{qw(field_list eav_field_list field_prefs field_attributes extended)};
	if ( defined $field_prefs->{'aliases'}->{'maindisplay'} ) {
		$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} = $field_prefs->{'aliases'}->{'maindisplay'};
	} else {
		$self->{'system'}->{'maindisplay_aliases'} ||= 'no';
		$self->{'prefs'}->{'maindisplayfields'}->{'aliases'} =
		  $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 1 : 0;
	}
	foreach my $field (@$field_list) {
		next if $field eq 'id';
		if ( defined $field_prefs->{$field}->{'maindisplay'} ) {
			$self->{'prefs'}->{'maindisplayfields'}->{$field} = $field_prefs->{$field}->{'maindisplay'};
		} else {
			$field_attributes->{$field}->{'maindisplay'} ||= 'yes';
			$self->{'prefs'}->{'maindisplayfields'}->{$field} =
			  $field_attributes->{$field}->{'maindisplay'} eq 'no' ? 0 : 1;
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( defined $field_prefs->{$field}->{'maindisplay'} ) {
					$self->{'prefs'}->{'maindisplayfields'}->{"${field}..$extended_attribute"} =
					  $field_prefs->{"${field}..$extended_attribute"}->{'maindisplay'};
				} else {
					$self->{'prefs'}->{'maindisplayfields'}->{"${field}..$extended_attribute"} = 0;
				}
			}
		}
	}
	foreach my $field (@$eav_field_list) {
		if ( defined $field_prefs->{$field}->{'maindisplay'} ) {
			$self->{'prefs'}->{'maindisplayfields'}->{$field} = $field_prefs->{$field}->{'maindisplay'};
		}
	}
	my $qry = 'SELECT id,main_display FROM composite_fields';
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
	return;
}

sub _initiate_isolatedb_locus_prefs {
	my ( $self, $guid, $dbname ) = @_;
	my $locus_prefs =
	  $self->{'datastore'}->run_query( 'SELECT id,isolate_display,main_display,query_field,analysis FROM loci',
		undef, { fetch => 'all_arrayref' } );
	my $prefstore_values = $self->{'prefstore'}->get_all_locus_prefs( $guid, $dbname );
	my $i = 1;
	foreach my $action (qw (isolate_display main_display query_field analysis)) {
		if ( !$self->{'pref_requirements'}->{$action} ) {
			$i++;
			next;
		}
		my $term = "${action}_loci";
		foreach my $locus_pref (@$locus_prefs) {
			my $locus = $locus_pref->[0];
			if ( defined $prefstore_values->{$locus}->{$action} ) {
				if ( $action eq 'isolate_display' ) {
					$self->{'prefs'}->{$term}->{$locus} = $prefstore_values->{$locus}->{$action};
				} else {
					$self->{'prefs'}->{$term}->{$locus} = $prefstore_values->{$locus}->{$action} eq 'true' ? 1 : 0;
				}
			} else {
				$self->{'prefs'}->{$term}->{$locus} = $locus_pref->[$i];
			}
		}
		$i++;
	}
	return;
}

sub _initiate_isolatedb_scheme_prefs {
	my ( $self, $guid, $dbname, $field_prefs, $scheme_field_prefs ) = @_;
	my $scheme_ids = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my $scheme_values              = $self->{'prefstore'}->get_all_scheme_prefs( $guid, $dbname );
	my $scheme_field_default_prefs = $self->{'datastore'}->get_all_scheme_field_info;
	my $scheme_info                = $self->{'datastore'}->get_all_scheme_info;
	my $scheme_fields              = $self->{'datastore'}->get_all_scheme_fields;
	foreach my $scheme_id (@$scheme_ids) {
		foreach my $action (qw(isolate_display main_display query_field query_status analysis)) {
			if ( defined $scheme_values->{$scheme_id}->{$action} ) {
				$self->{'prefs'}->{"$action\_schemes"}->{$scheme_id} =
				  $scheme_values->{$scheme_id}->{$action} ? 1 : 0;
			} else {
				$self->{'prefs'}->{"$action\_schemes"}->{$scheme_id} = $scheme_info->{$scheme_id}->{$action};
			}
		}
		if ( ref $scheme_fields->{$scheme_id} eq 'ARRAY' ) {
			foreach my $field ( @{ $scheme_fields->{$scheme_id} } ) {
				foreach my $action (qw(isolate_display main_display query_field)) {
					if ( defined $scheme_field_prefs->{$scheme_id}->{$field}->{$action} ) {
						$self->{'prefs'}->{"${action}_scheme_fields"}->{$scheme_id}->{$field} =
						  $scheme_field_prefs->{$scheme_id}->{$field}->{$action} ? 1 : 0;
					} else {
						$self->{'prefs'}->{"${action}_scheme_fields"}->{$scheme_id}->{$field} =
						  $scheme_field_default_prefs->{$scheme_id}->{$field}->{$action};
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
	return;
}

sub initiate_view {
	my ( $self, $username ) = @_;
	return if !$self->{'datastore'};
	my $args = { username => $username };
	$args->{'curate'} = $self->{'curate'} if $self->{'curate'};
	my $set_id = $self->get_set_id;
	$args->{'set_id'} = $set_id if $set_id;
	$self->{'datastore'}->initiate_view($args);
	return;
}

sub clean_checkbox_id {
	my ( $self, $var ) = @_;
	$var =~ s/'/__prime__/gx;
	$var =~ s/\//__slash__/gx;
	$var =~ s/,/__comma__/gx;
	$var =~ s/\ /__space__/gx;
	$var =~ s/\(/_OPEN_/gx;
	$var =~ s/\)/_CLOSE_/gx;
	$var =~ s/\>/_GT_/gx;
	$var =~ tr/:/_/;
	return $var;
}

sub get_all_foreign_key_fields_and_labels {

	#returns arrayref of fields needed to order label and a hashref of labels
	my ( $self, $attribute_hashref ) = @_;
	my @fields;
	my @values = split /\|/x, $attribute_hashref->{'labels'};
	foreach my $value (@values) {
		if ( $value =~ /\$(.*)/x ) {
			push @fields, $1;
		}
	}
	local $" = ',';
	my $qry = "select id,@fields from $attribute_hashref->{'foreign_key'}";
	my $dataset = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my %desc;
	foreach my $data (@$dataset) {
		my $temp = $attribute_hashref->{'labels'};
		foreach my $field (@fields) {
			$temp =~ s/\|\$$field\|/$data->{$field}/gx;
		}
		$desc{ $data->{'id'} } = $temp;
	}
	return ( \@fields, \%desc );
}

sub textfield {

	#allow HTML5 attributes (use instead of CGI->textfield)
	my ( $self, %args ) = @_;
	foreach ( keys %args ) {
		( my $stripped_key = $_ ) =~ s/^\-//x;
		$args{$stripped_key} =
		  delete $args{$_};    #strip off initial dash in key so can be used as drop-in replacement for CGI->textfield
	}
	if ( ( $args{'type'} // '' ) eq 'number' ) {
		delete @args{qw(size maxlength)};
	}
	$args{'type'} //= 'text';
	my $args_string;
	foreach ( keys %args ) {
		$args{$_} //= '';
		$args_string .= qq($_="$args{$_}" );
	}
	my $buffer = "<input $args_string/>";
	return $buffer;
}

sub popup_menu {

	#Faster than CGI::popup_menu when listing thousands of values as it doesn't need to escape all values
	my ( $self, %args ) = @_;
	my ( $name, $id, $values, $labels, $default, $class, $multiple, $size, $style, $required, $disabled ) =
	  @args{qw ( -name -id -values -labels -default -class -multiple -size -style -required -disabled)};
	my $q        = $self->{'cgi'};
	my @selected = $q->multi_param($name);
	s/"/&quot;/gx foreach @selected;
	my %default;
	if ( ref $default eq 'ARRAY' ) {
		%default = map { $_ => 1 } @$default;
	} elsif ( defined $default && $default ne q() ) {
		$default{$default} = 1;
	}
	foreach my $selected (@selected) {
		$default{$selected} = 1 if $selected ne q();
	}
	my $buffer = qq(<select name="$name");
	$buffer .= qq( class="$class")     if defined $class;
	$buffer .= qq( id="$id")           if defined $id;
	$buffer .= qq( size="$size")       if defined $size;
	$buffer .= qq( style="$style")     if defined $style;
	$buffer .= q( required="required") if defined $required;
	$buffer .= q( multiple="multiple") if ( $multiple // '' ) eq 'true';
	$buffer .= q( disabled="disabled") if ( $disabled // '' ) eq 'true';
	$buffer .= qq(>\n);

	foreach (@$values) {
		next if !defined;
		s/"/&quot;/gx;
		$labels->{$_} //= $_;
		my $select = $default{$_} ? q( selected="selected") : '';
		$buffer .= qq(<option value="$_"$select>$labels->{$_}</option>\n);
	}
	$buffer .= qq(</select>\n);
	return $buffer;
}

sub datalist {
	my ( $self, %args ) = @_;
	my ( $name, $id, $values, $labels, $class, $size, $style, $invalid_value, $datalist_name, $datalist_exists ) =
	  @args{qw ( name id values labels class size style invalid_value datalist_name datalist_exists)};
	$id //= $name;
	my $q = $self->{'cgi'};
	my $real_value = $q->param($name) // q();
	$real_value =~ s/"/\\"/gx;
	my $invalid = $invalid_value ? qq(\$("#$name").val('$invalid_value');) : q();
	$datalist_name //= "${name}_list";
	my $label_value = $q->param("${name}_label") // q();
	$label_value =~ s/"/\\"/gx;
	my $buffer = qq(<input type="text" name="${name}_label" id="${name}_label" value="$label_value" autocomplete="off");
	$buffer .= qq( class="$class") if $class;
	$buffer .= qq( style="$style") if $style;
	$buffer .= qq( size="$size")   if $size;
	$buffer .= qq( list="$datalist_name">\n);

	if ( !$datalist_exists ) {
		$buffer .= qq(<datalist id="$datalist_name">\n);
		foreach my $value (@$values) {
			my $label = $labels->{$value} // $value;
			$value =~ s/"/\\"/gx;
			$label =~ s/"/\\"/gx;
			$buffer .= qq( <option data-value="$value">$label</option>\n);
		}
		$buffer .= qq(</datalist>\n);
	}
	$buffer .= qq(<input type="hidden" name="$name" id="$id">\n);
	$buffer .= << "JS";
<script class="ajax_script">
var ${id}_options = \$('#$datalist_name' + ' option');
var input_value = \$("#${id}_label").val();
if (input_value == ''){
	var real_value = "$real_value";
	for(var i = 0; i < ${id}_options.length; i++) {
		var option = ${name}_options[i];
		if (real_value == option.getAttribute('data-value')){
			\$("#${id}_label").val(option.innerText);
			break;
		}
	}
} else {
	for(var i = 0; i < ${name}_options.length; i++) {
		var option = ${name}_options[i];
		if (input_value == option.innerText){
			\$("#$id").val(option.getAttribute('data-value'));
			break;
		}	
	}
}
\$("#${id}_label").off("change").change(function(){
	var input_value = \$('#${name}_label').val();
	if (input_value == ''){
		\$("#$id").val('');
		return;
	}
	//Start with exact case-insensitive matches
	for(var i = 0, len = ${id}_options.length; i < len; i++) {
        var option = ${id}_options[i];
		if (option.innerText.toUpperCase() === input_value.toUpperCase()){
        	\$("#$id").val(option.getAttribute('data-value'));
        	\$('#${name}_label').val(option.innerText);
        	return;
        }
    }  
    //Then any matches that start with entered term
	for(var i = 0, len = ${id}_options.length; i < len; i++) {
        var option = ${id}_options[i];
		if (option.innerText.toUpperCase().startsWith(input_value.toUpperCase())){
        	\$("#$id").val(option.getAttribute('data-value'));
        	\$('#${name}_label').val(option.innerText);
        	return;
        }
    }    
    $invalid
});

</script>
JS
	return $buffer;
}

sub print_seqbin_isolate_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( $ids, $labels ) = $self->get_isolates_with_seqbin($options);
	say q(<fieldset style="float:left"><legend>Isolates</legend>);
	if (@$ids) {
		my $size = $options->{'size'} // 8;
		my $list_box_size = $size - 0.2;
		say q(<div style="float:left">);
		if ( @$ids <= MAX_ISOLATES_DROPDOWN || !$options->{'isolate_paste_list'} ) {
			say $self->popup_menu(
				-name     => 'isolate_id',
				-id       => 'isolate_id',
				-values   => $ids,
				-labels   => $labels,
				-style    => "min-width:12em;height:${size}em",
				-multiple => 'true',
				-default  => $options->{'selected_ids'},
				-required => ( $options->{'isolate_paste_list'} || $options->{'allow_empty_list'} )
				? undef
				: 'required'
			);
			my $list_button = q();
			if ( $options->{'isolate_paste_list'} ) {
				my $show_button_display = $q->param('isolate_paste_list') ? 'none'    : 'display';
				my $hide_button_display = $q->param('isolate_paste_list') ? 'display' : 'none';
				$list_button =
				    q(<input type="button" id="isolate_list_show_button" )
				  . q(onclick='isolate_list_show()' value="Paste list" )
				  . qq(style="margin:1em 0 0 0.2em; display:$show_button_display" class="small_submit" />)
				  . q(<input type="button" id="isolate_list_hide_button" onclick='isolate_list_hide()' value="Hide list" )
				  . qq(style="margin:1em 0 0 0.2em; display:$hide_button_display" class="small_submit" />);
			}
			say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("isolate_id",true)' )
			  . q(value="All" style="margin-top:1em" class="small_submit" />)
			  . q(<input type="button" onclick='listbox_selectall("isolate_id",false)' value="None" )
			  . qq(style="margin:1em 0 0 0.2em" class="small_submit" />$list_button</div></div>);
			if ( $options->{'isolate_paste_list'} ) {
				my $display = $q->param('isolate_paste_list') ? 'block' : 'none';
				say qq(<div id="isolate_paste_list_div" style="float:left; display:$display">);
				say $q->textarea(
					-name        => 'isolate_paste_list',
					-id          => 'isolate_paste_list',
					-style       => "height:${list_box_size}em",
					-rows        => $options->{'size'} ? ( $options->{'size'} - 1 ) : 7,
					-placeholder => 'Paste list of isolate ids (one per line)...'
				);
				say q(</div>);
			}
		} else {
			local $" = qq(\n);
			my %args = (
				-name        => 'isolate_paste_list',
				-id          => 'isolate_paste_list',
				-style       => "height:${list_box_size}em",
				-default     => "@{$options->{'selected_ids'}}",
				-placeholder => 'Paste list of isolate ids (one per line)...',
			);
			$args{'-required'} = 'required' if !$options->{'allow_empty_list'};
			say $q->textarea(%args);
			say q(<div style="text-align:center"><input type="button" onclick='listbox_clear("isolate_paste_list")' )
			  . q(value="Clear" style="margin-top:1em" class="small_submit" />);
			if ( $options->{'only_genomes'} ) {
				say q(<input type="button" onclick='listbox_listgenomes("isolate_paste_list")' value="List all" )
				  . q(style="margin-top:1em" class="small_submit" /></div></div>);
			} else {
				say q(<input type="button" onclick='listbox_listall("isolate_paste_list")' value="List all" )
				  . q(style="margin-top:1em" class="small_submit" /></div></div>);
			}
		}
	} else {
		say q(No isolates available<br />for analysis);
	}
	say q(</fieldset>);
	return;
}

sub get_ids_from_pasted_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @cleaned_ids, @invalid_ids );
	if ( $q->param('isolate_paste_list') ) {
		my @list = split /\n/x, $q->param('isolate_paste_list');
		foreach my $id (@list) {
			next if $id =~ /^\s*$/x;
			$id =~ s/^\s*//x;
			$id =~ s/\s*$//x;
			if ( BIGSdb::Utils::is_int($id) && $self->isolate_exists( $id, $options ) ) {
				push @cleaned_ids, $id;
			} else {
				push @invalid_ids, $id;
			}
		}
		$q->delete('isolate_paste_list') if !@invalid_ids && !$options->{'dont_clear'};
	}
	return ( \@cleaned_ids, \@invalid_ids );
}

sub print_isolates_locus_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say q(<fieldset id="locus_fieldset" style="float:left"><legend>Loci</legend>);
	my $analysis_pref = $options->{'analysis_pref'} // 1;
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list(
		{ loci => 1, analysis_pref => $analysis_pref, query_pref => 0, sort_labels => 1 } );
	if (@$locus_list) {
		say q(<div style="float:left">);
		my $size = $options->{'size'} // 8;
		my $list_box_size = $size - 0.2;
		say $self->popup_menu(
			-name     => 'locus',
			-id       => 'locus',
			-values   => $locus_list,
			-labels   => $locus_labels,
			-style    => "height:${size}em",
			-multiple => 'true',
			-default  => $options->{'selected_loci'}
		);
		say q(</div>);
		if ( $options->{'locus_paste_list'} ) {
			my $display = $q->param('locus_paste_list') ? 'block' : 'none';
			say qq(<div id="locus_paste_list_div" style="float:left; display:$display">);
			say $q->textarea(
				-name        => 'locus_paste_list',
				-id          => 'locus_paste_list',
				-style       => "height:${list_box_size}em",
				-rows        => $options->{'size'} ? ( $options->{'size'} - 1 ) : 7,
				-placeholder => 'Paste list of locus primary names (one per line)...'
			);
			say q(</div>);
		}
		say q(<div style="clear:both"></div>);
		my $list_button = q();
		if ( $options->{'locus_paste_list'} ) {
			my $show_button_display = $q->param('locus_paste_list') ? 'none'    : 'display';
			my $hide_button_display = $q->param('locus_paste_list') ? 'display' : 'none';
			$list_button =
			    q(<input type="button" id="locus_list_show_button" onclick='locus_list_show()' value="Paste list" )
			  . qq(style="margin:1em 0 0 0.2em;display:$show_button_display" class="small_submit" />)
			  . q(<input type="button" id="locus_list_hide_button" onclick='locus_list_hide()' value="Hide list" )
			  . qq(style="margin:1em 0 0 0.2em;display:$hide_button_display" class="small_submit" />);
		}
		say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' )
		  . q(value="All" style="margin-top:1em" class="small_submit" /><input type="button" )
		  . q(onclick='listbox_selectall("locus",false)' value="None" style="margin:1em 0 0 0.2em" class="small_submit" />)
		  . qq($list_button</div>);
	} else {
		say q(No loci available<br />for analysis);
	}
	say q(</fieldset>);
	return;
}

sub get_loci_from_pasted_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @cleaned_loci, @invalid_loci );
	if ( $q->param('locus_paste_list') ) {
		my @list = split /\n/x, $q->param('locus_paste_list');
		foreach my $locus (@list) {
			next if $locus =~ /^\s*$/x;
			$locus =~ s/^\s*//x;
			$locus =~ s/\s*$//x;
			my $real_name;
			my $set_id = $self->get_set_id;
			if ($set_id) {
				$real_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
			} else {
				$real_name = $locus;
			}
			if ( $self->{'datastore'}->is_locus($real_name) ) {
				push @cleaned_loci, $real_name;
			} else {
				push @invalid_loci, $locus;
			}
		}
		$q->delete('locus_paste_list') if !@invalid_loci && !$options->{'dont_clear'};
	}
	return ( \@cleaned_loci, \@invalid_loci );
}

sub populate_submission_params {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('submission_id') && !$q->param('query_id');
	return if !$self->{'system'}->{'dbtype'} eq 'sequences';
	return if !BIGSdb::Utils::is_int( scalar $q->param('index') );
	if ( $q->param('populate_seqs') && $q->param('index') && !$q->param('sequence') ) {
		my $submission_seq =
		  $self->_get_allele_submission_sequence( scalar $q->param('submission_id'), scalar $q->param('index') );
		$q->param( sequence => $submission_seq );
		if ( $q->param('locus') ) {
			( my $locus = $q->param('locus') ) =~ s/%27/'/gx;    #Web-escaped locus
			$q->param( locus => $locus );
		}
	}
	if ( $q->param('populate_profiles') && $q->param('index') ) {
		if ( $q->param('submission_id') ) {
			my $submission_profile =
			  $self->_get_profile_submission_alleles( scalar $q->param('submission_id'), scalar $q->param('index') );
			foreach my $designation (@$submission_profile) {
				$q->param( "l_$designation->{'locus'}" => $designation->{'allele_id'} );
			}
		} elsif ( $q->param('query_id') ) {
			my $query_id = $q->param('query_id');
			eval {
				my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$query_id.json";
				my $json_ref  = BIGSdb::Utils::slurp($full_path);
				my $data      = decode_json($$json_ref);
				my $index     = $q->param('index');
				if ( defined $index && $data->{$index} ) {
					my @loci = keys %{ $data->{$index} };
					foreach my $locus (@loci) {
						$q->param( "l_$locus" => $data->{$index}->{$locus} );
					}
				}
			};
			$logger->error($@) if $@;
		}
	}
	return;
}

sub _get_allele_submission_sequence {
	my ( $self, $submission_id, $index ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	return $self->{'datastore'}
	  ->run_query( 'SELECT sequence FROM allele_submission_sequences WHERE (submission_id,index)=(?,?)',
		[ $submission_id, $index ] );
}

sub _get_profile_submission_alleles {
	my ( $self, $submission_id, $index ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	return $self->{'datastore'}->run_query(
		'SELECT locus,allele_id FROM profile_submission_designations d JOIN profile_submission_profiles p '
		  . 'ON (d.submission_id,d.profile_id)=(p.submission_id,p.profile_id) WHERE (p.submission_id,p.index)=(?,?)',
		[ $submission_id, $index ],
		{ fetch => 'all_arrayref', slice => {} }
	);
}

#Scheme list filtered to remove disabled schemes.
sub get_scheme_data {
	my ( $self, $options ) = @_;
	my $set_id = $self->get_set_id;
	my $schemes =
	  $self->{'datastore'}->get_scheme_list( { with_pk => ( $options->{'with_pk'} ? 1 : 0 ), set_id => $set_id } );
	return $schemes if $self->{'system'}->{'dbtype'} eq 'isolates';
	my @scheme_list;
	foreach my $scheme (@$schemes) {
		next if $self->{'prefs'}->{'disable_schemes'}->{ $scheme->{'id'} };
		push @scheme_list, $scheme;
	}
	return \@scheme_list;
}

sub modify_dataset_if_needed {
	my ( $self, $table, $dataset ) = @_;
	if ( $table eq 'users' ) {
		foreach my $user (@$dataset) {
			next if !defined $user->{'user_db'};
			my $remote_user = $self->{'datastore'}->get_remote_user_info( $user->{'user_name'}, $user->{'user_db'} );
			if ( $remote_user->{'user_name'} ) {
				$user->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation);
			}
		}
	}
	if ( $table eq 'geography_point_lookup' ) {
		foreach my $record (@$dataset) {
			my $location = $self->{'datastore'}->get_geography_coordinates( $record->{'location'} );
			$record->{'location'} = "$location->{'latitude'}, $location->{'longitude'}";
		}
	}
	return;
}

sub use_correct_user_database {
	my ($self) = @_;
	my $user_dbs = $self->{'config'}->{'site_user_dbs'};
	my %valid_db = map { $_->{'dbase'} => 1 } @$user_dbs;
	if ( !$valid_db{ $self->{'system'}->{'db'} } ) {
		return;
	}

	#We may be logged in to a different user database than the one containing
	#the logged in user details. Make sure the DBI object is set to correct
	#database.
	my $att = {
		dbase_name => $self->{'system'}->{'db'},
		host       => $self->{'config'}->{'dbhost'} // $self->{'system'}->{'host'},
		port       => $self->{'config'}->{'dbport'} // $self->{'system'}->{'port'},
		user       => $self->{'config'}->{'dbuser'} // $self->{'system'}->{'user'},
		password   => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'}
	};
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection($att);
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$logger->error("Cannot connect to database '$self->{'system'}->{'db'}'");
		} else {
			$logger->logdie($_);
		}
	};
	$self->{'datastore'}->change_db( $self->{'db'} );
	foreach my $config ( @{ $self->{'config'}->{'site_user_dbs'} } ) {
		if ( $config->{'dbase'} eq $self->{'system'}->{'db'} ) {
			$self->{'system'}->{'description'} = $config->{'name'};
			last;
		}
	}
	if ( $self->{'username'} ) {
		$self->{'permissions'} = $self->{'datastore'}->get_permissions( $self->{'username'} );
	}
	return;
}

sub get_user_db_name {
	my ( $self, $user_name ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'user' ) {
		return $self->{'system'}->{'db'};
	}
	my $db_name = $self->{'datastore'}->run_query(
		'SELECT user_dbases.dbase_name FROM user_dbases JOIN users '
		  . 'ON user_dbases.id=users.user_db WHERE users.user_name=?',
		$user_name
	);
	$db_name //= $self->{'system'}->{'db'};
	return $db_name;
}

sub get_tooltip {
	my ( $self, $text, $options ) = @_;
	my $id = $options->{'id'} ? qq( id="$options->{'id'}") : q();
	my $tooltip_icon = TOOLTIP;
	return qq(<a class="tooltip"$id style="margin-left:0.5em;vertical-align:top" title="$text">$tooltip_icon</a>);
}

sub get_warning_tooltip {
	my ( $self, $text, $options ) = @_;
	my $id = $options->{'id'} ? qq( id="$options->{'id'}") : q();
	my $tooltip_icon = WARNING_TOOLTIP;
	return qq(<a class="tooltip warning_tooltip"$id style="margin-left:0.5em;vertical-align:top" )
	  . qq(title="$text">$tooltip_icon</a>);
}

sub print_navigation_bar {
	my ( $self, $options ) = @_;
	my $script = $options->{'script'} // $self->{'system'}->{'script_name'};
	my ( $back, $home, $key, $more, $query_more, $upload_contigs, $link_contigs, $reload, $edit, $curate ) =
	  ( BACK, HOME, KEY, MORE, QUERY_MORE, UPLOAD_CONTIGS, LINK_CONTIGS, RELOAD, EDIT_MORE, CURATE );
	my $buffer = q();
	if ( $options->{'submission_id'} ) {
		$buffer .=
		    qq(<a href="$script?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$options->{'submission_id'}&amp;curate=1" title="Return to submission" )
		  . qq(style="margin-right:1em">$back</a>);
	} elsif ( $options->{'back_url'} || $options->{'back_page'} ) {
		my $page = $options->{'back_page'} // 'index';
		my $url  = $options->{'back_url'}  // "$script?db=$self->{'instance'}&amp;page=$page";
		$buffer .= qq(<a href="$url" title="Back" style="margin-right:1em">$back</a>);
	}
	if ( $options->{'curator_interface'} && $self->{'config'}->{'curate_script'} ) {
		$buffer .= qq(<a href="$self->{'config'}->{'curate_script'}?db=$self->{'instance'}" )
		  . qq(title="Curators' interface" style="margin-right:1em">$curate</a>);
	}
	if ( $options->{'change_password'} ) {
		$buffer .= qq(<a href="$options->{'change_password'}" title="Set password" style="margin-right:1em">$key</a>);
	}
	if ( $options->{'closed_submissions'} ) {
		$buffer .=
		    q(<a id="show_closed" style="cursor:pointer;margin-right:1em" class="small_submit">)
		  . q(<span id="show_closed_text" style="display:inline">)
		  . q(<span class="fas fa fa-eye"></span> Show closed submissions</span>)
		  . q(<span id="hide_closed_text" style="display:none">)
		  . q(<span class="fas fa fa-eye-slash"></span> Hide closed submissions</span></a>);
	}
	if ( $options->{'more_url'} ) {
		$options->{'more_text'} //= 'Add another';
		$buffer .=
		  qq(<a href="$options->{'more_url'}" title="$options->{'more_text'}" style="margin-right:1em">$more</a>);
	}
	if ( $options->{'query_more_url'} ) {
		$buffer .=
		    qq(<a href="$options->{'query_more_url'}" title="Query another" style="margin-right:1em">)
		  . qq($query_more</a>);
	}
	if ( $options->{'upload_contigs_url'} ) {
		$buffer .=
		    qq(<a href="$options->{'upload_contigs_url'}" title="Upload contigs" style="margin-right:1em">)
		  . qq($upload_contigs</a>);
	}
	if ( $options->{'link_contigs_url'} ) {
		$buffer .=
		    qq(<a href="$options->{'link_contigs_url'}" title="Link remote contigs" style="margin-right:1em">)
		  . qq($link_contigs</a>);
	}
	if ( $options->{'reload_url'} ) {
		$options->{'reload_text'} //= 'Reload scan form';
		$buffer .= qq(<a href="$options->{'reload_url'}" title="$options->{'reload_text'}" )
		  . qq(style="margin-right:1em">$reload</a>);
	}
	if ( $options->{'update_url'} ) {
		$buffer .= qq(<a href="$options->{'update_url'}" title="Update record" style="margin-right:1em">$edit</a>);
	}
	if ($buffer) {
		$buffer = qq(<div class="navigation">$buffer</div><div style="clear:both"></div>);
	}
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub print_bad_status {
	my ( $self, $options ) = @_;
	$options->{'message'} //= 'Failed!';
	my $buffer = q();
	$buffer .= q(<div class="box statusbad" style="min-height:5em">);
	$buffer .= q(<p><span class="failure fas fa-times fa-5x fa-pull-left"></span></p>);
	$buffer .= qq(<p class="outcome_message">$options->{'message'}</p>);
	if ( $options->{'detail'} ) {
		$buffer .= qq(<p class="outcome_detail">$options->{'detail'}</p>);
	}
	if ( $options->{'navbar'} ) {
		$buffer .= $self->print_navigation_bar( { get_only => 1, %$options } );
	}
	$buffer .= q(</div>);
	say $buffer if !$options->{'get_only'};
	return $buffer;
}

sub print_good_status {
	my ( $self, $options ) = @_;
	$options->{'message'} //= 'Success!';
	my $buffer = q();
	$buffer .= q(<div class="box resultsheader" style="min-height:5em">);
	$buffer .= q(<p><span class="success fas fa-check fa-5x fa-pull-left"></span></p>);
	$buffer .= qq(<p class="outcome_message">$options->{'message'}</p>);
	if ( $options->{'detail'} ) {
		$buffer .= qq(<p class="outcome_detail">$options->{'detail'}</p>);
	}
	if ( $options->{'navbar'} ) {
		$buffer .= $self->print_navigation_bar( { get_only => 1, %$options } );
	}
	$buffer .= q(</div>);
	say $buffer if !$options->{'get_only'};
	return $buffer;
}

sub print_loading_message {
	my ( $self, $options ) = @_;
	my $top_margin = $options->{'top_margin'} // 5;
	say qq(<p style="margin-top:${top_margin}em;text-align:center;line-height:3em">)
	  . q(<span class="wait_message">Loading ... Please wait.</span></p>)
	  . q(<p style="text-align:center"><span class="wait_icon fas fa-sync-alt fa-spin fa-8x"></span></p>);
	return;
}

sub print_warning {
	my ( $self, $options ) = @_;
	$options->{'message'} //= 'Warning!';
	say q(<div class="box statuswarn" style="min-height:5em");
	say q(<p><a><span class="warn fas fa-exclamation fa-5x fa-pull-left"></span></a></p>);
	say qq(<p class="outcome_message">$options->{'message'}</p>);
	if ( $options->{'detail'} ) {
		say qq(<p class="outcome_detail">$options->{'detail'}</p>);
	}
	say q(</div>);
	return;
}

sub get_list_block {
	my ( $self, $list, $options ) = @_;

	#It is not semantically correct to enclose a <dt>, <dd> pair within a span. If we don't, however, the
	#columnizer plugin can result in the title and data item appearing in different columns. All browsers
	#seem to handle this way ok.
	my ( $dt_width_clause, $dd_left_margin_clause, $id_clause );
	if ( $options->{'width'} ) {
		$dt_width_clause = qq( style="width:$options->{'width'}em");
		my $margin_width = $options->{'width'} + 1;
		$dd_left_margin_clause = qq( style="margin-left:${margin_width}em");
	}
	if ( $options->{'id'} ) {
		$id_clause = qq( id="$options->{'id'}");
	}
	$_ //= q() foreach ( $dt_width_clause, $dd_left_margin_clause, $id_clause );
	my $buffer = qq(<dl class="data"$id_clause>\n);
	foreach my $item (@$list) {
		if ( $options->{'nowrap'} ) {
			$item->{'data'} = qq(<span style="white-space:nowrap">$item->{'data'}</span>);
		}
		my $class = $item->{'class'};
		$buffer .= q(<span class="dontsplit">) if $options->{'columnize'};
		$buffer .= qq(<dt$dt_width_clause>$item->{'title'}</dt>);
		$buffer .= $class ? qq(<dd class="$class"$dd_left_margin_clause>) : qq(<dd$dd_left_margin_clause>);
		$buffer .= qq(<a href="$item->{'href'}">) if $item->{'href'};
		$buffer .= $item->{'data'};
		$buffer .= q(</a>)                        if $item->{'href'};
		$buffer .= q(</dd>);
		$buffer .= qq(</span>\n)                  if $options->{'columnize'};
	}
	$buffer .= qq(</dl>\n);
	return $buffer;
}

sub is_page_allowed {
	my ( $self, $page ) = @_;
	return 1 if !$self->{'system'}->{'kiosk'};
	return 1 if $page eq $self->{'system'}->{'kiosk'};
	my %allowed_pages;
	if ( $self->{'system'}->{'kiosk_allowed_pages'} ) {
		%allowed_pages = map { $_ => 1 } split /,/x, $self->{'system'}->{'kiosk_allowed_pages'};
	}
	return 1 if $allowed_pages{$page};
	return;
}

sub is_curator {
	my ($self) = @_;
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info || ( $user_info->{'status'} ne 'curator' && $user_info->{'status'} ne 'admin' );
	return 1;
}

sub set_level0_breadcrumbs {
	my ($self) = @_;
	my $page_name = $self->get_title( { breadcrumb => 1 } );
	$self->{'breadcrumbs'} = [];
	if ( $self->{'system'}->{'webroot'} ) {
		push @{ $self->{'breadcrumbs'} },
		  {
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href => $self->{'system'}->{'webroot'}
		  };
	}
	push @{ $self->{'breadcrumbs'} }, { label => $page_name };
	return;
}

sub set_level1_breadcrumbs {
	my ($self) = @_;
	my $page_name = $self->get_title( { breadcrumb => 1 } );
	my $breadcrumbs = [];
	if ( $self->{'system'}->{'webroot'} ) {
		push @$breadcrumbs,
		  {
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href => $self->{'system'}->{'webroot'}
		  };
	}
	if ( $self->{'instance'} ) {
		push @$breadcrumbs,
		  {
			label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'},
			href => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}"
		  };
	}
	if ( $self->{'processing'} ) {
		my $q            = $self->{'cgi'};
		my $page         = $q->param('page');
		my $table        = $q->param('table');
		my $table_clause = $table ? qq(&amp;table=$table) : q();
		push @$breadcrumbs,
		  {
			label => $page_name,
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$table_clause"
		  };
	} else {
		push @$breadcrumbs, { label => $page_name };
	}
	$self->{'breadcrumbs'} = $breadcrumbs;
	return;
}

sub print_related_dbases_button {
	my ($self) = @_;
	my $links = $self->get_related_databases;
	return if !@$links;
	say q(<span class="icon_button">);
	if ( @$links > 1 ) {
		say q(<a id="related_db_trigger" class="trigger_button">)
		  . q(<span id="related_db" class="fas fa-lg fa-database"></span>)
		  . q(<div class="icon_label">Related databases</div></a>);
	} else {
		say qq(<a id="related_db_trigger" class="trigger_button" href="$links->[0]->{'href'}">)
		  . q(<span id="related_db" class="fas fa-lg fa-database"></span>)
		  . qq(<div class="icon_label">$links->[0]->{'text'} database</div></a>);
	}
	say q(</span>);
	return;
}

sub get_related_databases {
	my ($self) = @_;
	return [] if !$self->{'system'}->{'related_databases'};
	my @dbases = split /;/x, $self->{'system'}->{'related_databases'};
	return [] if !@dbases;
	my $links = [];
	foreach my $dbase (@dbases) {
		my ( $config, $name ) = split /\|/x, $dbase;
		push @$links,
		  {
			href => "$self->{'system'}->{'script_name'}?db=$config",
			text => $name
		  };
	}
	return $links;
}

sub print_related_database_panel {
	my ($self) = @_;
	my $links = $self->get_related_databases;
	return if @$links < 2;
	say q(<div id="related_db_panel" style="display:none">);
	say q(<a class="close_trigger" id="close_related_db"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Related databases</h2>);
	say q(<div><div style="max-height:12em;overflow-y:auto;padding-right:2em"><ul style="margin-left:-1em">);
	foreach my $link (@$links) {
		say qq(<li><a href="$link->{'href'}">$link->{'text'}</a></li>);
	}
	say q(</ul></div>);
	say q(</div></div>);
	return;
}
1;
