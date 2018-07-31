#!/usr/bin/env perl
#Example script to download alleles from a sequence definition database
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
use File::Path qw(make_path);
use Getopt::Long qw(:config no_ignore_case);
use constant BASE_URI => 'http://rest.pubmlst.org';

#Term::Cap and POSIX are just used for formatting help page
use Term::Cap;
use POSIX;
my %opts;
GetOptions(
	'database=s'  => \$opts{'database'},
	'dir=s'       => \$opts{'dir'},
	'scheme_id=i' => \$opts{'scheme_id'},
	'help'        => \$opts{'help'},
) or die("Error in command line arguments\n");
if ( $opts{'help'} || !$opts{'database'} ) {
	show_help();
	exit;
}
if ( $opts{'dir'} ) {
	eval { make_path( $opts{'dir'} ) };
	die "Cannot create directory $opts{'dir'}.\n" if $@;
}
my $dir    = $opts{'dir'} // './';
my $client = REST::Client->new();
my $url    = BASE_URI . "/db/$opts{'database'}";
$client->request( 'GET', $url );
my $resources = from_json( $client->responseContent );
if ( ( $resources->{'status'} // 200 ) == 404 ) {
	die "Database $opts{'database'} is not available.\n";
}
my $loci = [];
if ( $opts{'scheme_id'} ) {
	$url = BASE_URI . "/db/$opts{'database'}/schemes/$opts{'scheme_id'}";
	$client->request( 'GET', $url );
	my $response = from_json( $client->responseContent );
	if ( ( $response->{'status'} // 200 ) == 404 ) {
		die "Scheme $opts{'scheme_id'} does not exist.\n";
	}
	$loci = $response->{'loci'} if $response->{'loci'};
} else {
	$url = BASE_URI . "/db/$opts{'database'}/loci?return_all=1";
	$client->request( 'GET', $url );
	my $response = from_json( $client->responseContent );
	$loci = $response->{'loci'} if $response->{'loci'};
}
foreach my $locus_path (@$loci) {
	$client->request( 'GET', $locus_path );
	my $response = from_json( $client->responseContent );
	my $locus    = $response->{'id'};
	if ( $response->{'alleles_fasta'} ) {
		$client->request( 'GET', $response->{'alleles_fasta'} );
		open( my $fh, '>', "$dir/$locus.fas" ) || die "Cannot open $dir/$locus.fas for writing.\n";
		print $fh $client->responseContent;
		close $fh;
	}
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
${bold}download_alleles.pl$norm - Download alleles from a sequence definition database

${bold}SYNOPSIS$norm
    ${bold}download_alleles.pl$norm --database$norm ${under}NAME$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE$norm
    Database configuration name. 
    
${bold}--dir$norm ${under}DIR$norm
    Output directory

${bold}--help$norm
    This help page.
    
${bold}--scheme_id$norm ${under}SCHEME_ID$norm
    Only return loci belonging to scheme. If this option is not used then all
    loci from the database will be downloaded.

HELP
	return;
}
