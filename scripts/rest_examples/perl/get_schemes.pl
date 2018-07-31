#!/usr/bin/env perl
#Example script to list names and URIs of scheme definitions using the
#PubMLST RESTful API.
#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
use strict;
use warnings;
use 5.010;
use REST::Client;
use JSON;
use Getopt::Long qw(:config no_ignore_case);
use constant BASE_URI => 'http://rest.pubmlst.org';

#Term::Cap and POSIX are just used for formatting help page
use Term::Cap;
use POSIX;
my %opts;
GetOptions(
	'exclude=s' => \$opts{'exclude'},
	'help'      => \$opts{'help'},
	'match=s'   => \$opts{'match'}
) or die("Error in command line arguments\n");
if ( $opts{'help'} ) {
	show_help();
	exit;
}
my $client = REST::Client->new();
$client->request( 'GET', BASE_URI );
my $resources = from_json( $client->responseContent );
foreach my $resource (@$resources) {
	if ( $resource->{'databases'} ) {
		foreach my $db ( @{ $resource->{'databases'} } ) {
			get_matching_schemes($db);
		}
	}
}

sub get_matching_schemes {
	my ($db) = @_;
	if ( $db->{'description'} =~ /definitions/x ) {
		$client->request( 'GET', $db->{'href'} );
		my $db_attributes = from_json( $client->responseContent );
		return if !$db_attributes->{'schemes'};
		$client->request( 'GET', $db_attributes->{'schemes'} );
		my $schemes = from_json( $client->responseContent );
		foreach my $scheme ( @{ $schemes->{'schemes'} } ) {
			##no critic (RequireExtendedFormatting)
			next if $opts{'match'}   && $scheme->{'description'} !~ /$opts{'match'}/;
			next if $opts{'exclude'} && $scheme->{'description'} =~ /$opts{'exclude'}/;
			say "$db->{'description'}\t$scheme->{'description'}\t$scheme->{'scheme'}";
		}
	}
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
${bold}get_schemes.pl$norm - Return list of scheme definitions from PubMLST

${bold}SYNOPSIS$norm
    ${bold}get_schemes.pl$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--exclude$norm ${under}STRING$norm
    Scheme name must not include provided term. 

${bold}--help$norm
    This help page.

${bold}--match$norm ${under}STRING$norm
    Scheme name must include provided term. 

HELP
	return;
}
