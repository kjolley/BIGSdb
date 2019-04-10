#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::CurateGeocodingPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Constants qw(COUNTRIES);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Geocoding setup - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Setup geocoding</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{
				message => 'This function can only be used for isolate databases.',
				navbar  => 1
			}
		);
		return;
	}
	if ( !$self->is_admin ) {
		$self->print_bad_status(
			{
				message => 'This is an admin only function.',
				navbar  => 1
			}
		);
		return;
	}
	say q(<div class="box" id="resultspanel">);
	say q(<h2>Standardized country names</h2>);
	say q(<p>In order to use tools that export to maps you need to ensure that you are storing isolate country )
	  . q(information in a standardized way.</p>);
	if ( $self->{'xmlHandler'}->is_field('country')
		&& ( $self->{'xmlHandler'}->get_field_attributes('country')->{'values'} // q() ) eq 'COUNTRIES' )
	{
		say q(<p><span class="success fas fa-check fa-5x fa-pull-left"></span>)
		  . q(You have successfully set up the country field in the config.xml file to include standard names.</p>);
	} else {
		say q(<p>BIGSdb has a pre-defined list of countries, linked to continent and ISO 3166-1 3 letter codes used )
		  . q(for visualization libraries. )
		  . q(You can use these by creating a field called 'country' in the config.xml database description file )
		  . q(as below.</p>);
		say q(<p class="code" style="color:blue">&lt;field type="text" required="yes" maindisplay="yes" )
		  . q(comments="country where )
		  . q(strain was isolated" optlist="yes" values="COUNTRIES" sort="no"&gt;country<br />)
		  . q(&nbsp;&nbsp;&lt;optlist&gt;<br />)
		  . q(&nbsp;&nbsp;&nbsp;&nbsp;&lt;option&gt;Unknown&lt;/option&gt;<br />)
		  . q(&nbsp;&nbsp;&lt;/optlist&gt<br />)
		  . q(&lt;/field&gt;</p>);
		say q(<p>This is set as a compulsory field with an additional option 'Unknown'. Add any additional values )
		  . q(as options in the same way. Setting the sort option to 'no' will add these options to the end of the )
		  . q(list - set it to 'yes' to sort your additonal options in with the standard country codes.</p>);
		say q(<div style="clear:both">);
		return;
	}
	say q(<div style="clear:both">);
	if ( $q->param('continent') ) {
		$self->_setup_continent;
	}
	say q(<h2>Extended attribute for continent</h2>);
	say q(<p>Extended attributes allow you to define additional properties for provenance metadata fields that can be )
	  . q(searched and displayed independently. A good example of this is linking country to continent.</p>);
	if (
		$self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (attribute,isolate_field)=(?,?))',
			[ 'continent', 'country' ]
		)
	  )
	{
		say q(<p><span class="success fas fa-check fa-5x fa-pull-left"></span>)
		  . q(An extended attribute called 'continent' has been defined for the 'country' field.</p>);
	} else {
		say q(<p style="margin-top:2em;margin-bottom:2em">)
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=geocoding&amp;continent=1" )
		  . q(class="launchbutton">Set up continent attribute</a> );
		say q(<div style="clear:both">);
		return;
	}
	say q(<div style="clear:both">);
	$self->_refresh_continents;
	say q(<h2>Linked continent information</h2>);
	my $countries_with_continent = $self->{'datastore'}->run_query(
		'SELECT field_value FROM isolate_value_extended_attributes WHERE (attribute,isolate_field)=(?,?)',
		[ 'continent', 'country' ],
		{ fetch => 'col_arrayref' }
	);
	my %countries_with_continent = map { $_ => 1 } @$countries_with_continent;
	my $countries                = $self->{'xmlHandler'}->get_field_option_list('country');
	my $linked                   = 0;
	my $unlinked                 = [];

	foreach my $country (@$countries) {
		if ( $countries_with_continent{$country} ) {
			$linked++;
		} else {
			push @$unlinked, $country;
		}
	}
	@$unlinked = sort @$unlinked;
	my $total = $linked + @$unlinked;
	say qq(<p>There are $total country values in your allowed list. How many are linked to continent?</p>);
	say $self->get_list_block(
		[ { title => 'Linked', data => $linked }, { title => 'Unlinked', data => scalar @$unlinked } ] );
	if (@$unlinked) {
		say q(<h3>Country values not linked to continent</h3>);
		local $" = qq(</li>\n<li>);
		say qq(<ul><li>@$unlinked</li></ul>);
		say q(<p>You can add continent links by editing the extended attributes table.</p>);
	}
	say q(</div>);
	return;
}

sub _setup_continent {
	my ($self) = @_;
	return
	  if $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (attribute,isolate_field) = (?,?))',
		[ 'continent', 'country' ] );
	eval {
		$self->{'db'}->do(
			'INSERT INTO isolate_field_extended_attributes (attribute,isolate_field,value_format,curator,datestamp) '
			  . 'VALUES (?,?,?,?,?)',
			undef, 'continent', 'country', 'text', $self->get_curator_id, 'now'
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	$self->{'db'}->commit;
	$self->_refresh_continents;
	return;
}

sub _refresh_continents {
	my ($self) = @_;
	my $country_continents = $self->{'datastore'}->run_query(
'SELECT field_value AS country,value AS continent FROM isolate_value_extended_attributes WHERE (attribute,isolate_field)=(?,?)',
		[ 'continent', 'country' ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %existing   = map { $_->{'country'} => $_->{'continent'} } @$country_continents;
	my $countries  = COUNTRIES;
	my $curator_id = $self->get_curator_id;
	eval {
		foreach my $country ( keys %$countries ) {
			next if !$countries->{$country}->{'continent'};
			next if ( $existing{$country} // q() ) eq $countries->{$country}->{'continent'};
			if ( $existing{$country} ) {
				$self->{'db'}->do(
					'UPDATE isolate_value_extended_attributes SET value=? WHERE '
					  . '(attribute,isolate_field,field_value)=(?,?,?)',
					undef, $countries->{$country}->{'continent'}, 'continent', 'country', $country
				);
			} else {
				$self->{'db'}->do(
					'INSERT INTO isolate_value_extended_attributes (attribute,isolate_field,field_value,'
					  . 'value,datestamp,curator) VALUES (?,?,?,?,?,?)',
					undef,
					'continent',
					'country',
					$country,
					$countries->{$country}->{'continent'},
					'now',
					$curator_id
				);
			}
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}
1;
