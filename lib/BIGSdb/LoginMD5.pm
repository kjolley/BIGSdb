########################################################################
#
# perl-md5-login: a Perl/CGI + JavaScript user authorization
#
########################################################################
# This software is provided 'as-is' and without warranty. Use it at
# your own risk.
#
# SourceForge project: http://perl-md5-login.sourceforge.net/
#
# Perl/CGI interface Copyright 2003 Alan Raetz <alanraetz@chicodigital.com>
#
# Released under the LGPL license (see http://www.fsf.org)
#
# JavaScript MD5 code by Paul Johnston <paj@pajhome.org.uk>
#
# * Version 1.1 Copyright (C) Paul Johnston 1999 - 2002.
# * Code also contributed by Greg Holt
# * See http://pajhome.org.uk/site/legal.html for details.
#
# The original Digest::MD5 Perl Module interface was written by
# Neil Winton <N.Winton@axion.bt.co.uk> and is maintained by
# Gisle Aas <gisle@ActiveState.com>
#
# Modified extensively by Keith Jolley for use in BIGSdb, 2009-2011
# Uses DBI rather than DB_FILE
# IP address set in sub initiate rather than at head of file as
# this wasn't being seen after the first mod_perl iteration.
#########################################################################
#
# The MD5 algorithm is defined in RFC 1321. The basic C code implementing
# the algorithm is derived from that in the RFC and is covered by the
# following copyright:
#
# Copyright (C) 1991-2, RSA Data Security, Inc. Created 1991. All rights
# reserved. License to copy and use this software is granted provided that
# it is identified as the "RSA Data Security, Inc. MD5 Message-Digest
# Algorithm" in all material mentioning or referencing this software or
# this function.
#
# License is also granted to make and use derivative works provided that
# such works are identified as "derived from the RSA Data Security, Inc.
# MD5 Message-Digest Algorithm" in all material mentioning or referencing
# the derived work.
#
#########################################################################
package BIGSdb::LoginMD5;
use Digest::MD5;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
my $logger       = get_logger('BIGSdb.Application_Authentication');
my $uniqueString = 'bigsdbJolley';
############################################################################
#
# Cookie timeout parameter, default is 1 day
#
my $cookie_timeout = '+1d';    # or '+12h' for 12 hours, etc.

# When a CGI response is received, the sessionID
# is used to retrieve the time of the request. If the sessionID
# does not index a timestamp, or if the timestamp is older than
# $screen_timeout, the password login fails and exits.
my $screen_timeout = 600;

# Each CGI call has it's own seed, using Perl's built-in seed generator.
# This is psuedo-random, but only controls the sessionID value, which
# is also hashed with the ip address and your $uniqueString
my $randomNumber = int( rand(4294967296) );

#
# The names of your cookies for this application
#
my $passString     = 'cdAuth';
my $userCookieName = 'wtUser';

sub get_javascript {
	return <<END_OF_JAVASCRIPT;
/*
 * A JavaScript implementation of the RSA Data Security, Inc. MD5 Message
 * Digest Algorithm, as defined in RFC 1321.
 * Version 1.1 Copyright (C) Paul Johnston 1999 - 2002.
 * Code also contributed by Greg Holt
 * See http://pajhome.org.uk/site/legal.html for details.
 */

/*
 * Add integers, wrapping at 2^32. This uses 16-bit operations internally
 * to work around bugs in some JS interpreters.
 */
function safe_add(x, y)
{
  var lsw = (x & 0xFFFF) + (y & 0xFFFF)
  var msw = (x >> 16) + (y >> 16) + (lsw >> 16)
  return (msw << 16) | (lsw & 0xFFFF)
}

/*
 * Bitwise rotate a 32-bit number to the left.
 */
function rol(num, cnt)
{
  return (num << cnt) | (num >>> (32 - cnt))
}

/*
 * These functions implement the four basic operations the algorithm uses.
 */
function cmn(q, a, b, x, s, t)
{
  return safe_add(rol(safe_add(safe_add(a, q), safe_add(x, t)), s), b)
}
function ff(a, b, c, d, x, s, t)
{
  return cmn((b & c) | ((~b) & d), a, b, x, s, t)
}
function gg(a, b, c, d, x, s, t)
{
  return cmn((b & d) | (c & (~d)), a, b, x, s, t)
}
function hh(a, b, c, d, x, s, t)
{
  return cmn(b ^ c ^ d, a, b, x, s, t)
}
function ii(a, b, c, d, x, s, t)
{
  return cmn(c ^ (b | (~d)), a, b, x, s, t)
}

/*
 * Calculate the MD5 of an array of little-endian words, producing an array
 * of little-endian words.
 */
function coreMD5(x)
{
  var a =  1732584193
  var b = -271733879
  var c = -1732584194
  var d =  271733878

  for(i = 0; i < x.length; i += 16)
  {
    var olda = a
    var oldb = b
    var oldc = c
    var oldd = d

    a = ff(a, b, c, d, x[i+ 0], 7 , -680876936)
    d = ff(d, a, b, c, x[i+ 1], 12, -389564586)
    c = ff(c, d, a, b, x[i+ 2], 17,  606105819)
    b = ff(b, c, d, a, x[i+ 3], 22, -1044525330)
    a = ff(a, b, c, d, x[i+ 4], 7 , -176418897)
    d = ff(d, a, b, c, x[i+ 5], 12,  1200080426)
    c = ff(c, d, a, b, x[i+ 6], 17, -1473231341)
    b = ff(b, c, d, a, x[i+ 7], 22, -45705983)
    a = ff(a, b, c, d, x[i+ 8], 7 ,  1770035416)
    d = ff(d, a, b, c, x[i+ 9], 12, -1958414417)
    c = ff(c, d, a, b, x[i+10], 17, -42063)
    b = ff(b, c, d, a, x[i+11], 22, -1990404162)
    a = ff(a, b, c, d, x[i+12], 7 ,  1804603682)
    d = ff(d, a, b, c, x[i+13], 12, -40341101)
    c = ff(c, d, a, b, x[i+14], 17, -1502002290)
    b = ff(b, c, d, a, x[i+15], 22,  1236535329)

    a = gg(a, b, c, d, x[i+ 1], 5 , -165796510)
    d = gg(d, a, b, c, x[i+ 6], 9 , -1069501632)
    c = gg(c, d, a, b, x[i+11], 14,  643717713)
    b = gg(b, c, d, a, x[i+ 0], 20, -373897302)
    a = gg(a, b, c, d, x[i+ 5], 5 , -701558691)
    d = gg(d, a, b, c, x[i+10], 9 ,  38016083)
    c = gg(c, d, a, b, x[i+15], 14, -660478335)
    b = gg(b, c, d, a, x[i+ 4], 20, -405537848)
    a = gg(a, b, c, d, x[i+ 9], 5 ,  568446438)
    d = gg(d, a, b, c, x[i+14], 9 , -1019803690)
    c = gg(c, d, a, b, x[i+ 3], 14, -187363961)
    b = gg(b, c, d, a, x[i+ 8], 20,  1163531501)
    a = gg(a, b, c, d, x[i+13], 5 , -1444681467)
    d = gg(d, a, b, c, x[i+ 2], 9 , -51403784)
    c = gg(c, d, a, b, x[i+ 7], 14,  1735328473)
    b = gg(b, c, d, a, x[i+12], 20, -1926607734)

    a = hh(a, b, c, d, x[i+ 5], 4 , -378558)
    d = hh(d, a, b, c, x[i+ 8], 11, -2022574463)
    c = hh(c, d, a, b, x[i+11], 16,  1839030562)
    b = hh(b, c, d, a, x[i+14], 23, -35309556)
    a = hh(a, b, c, d, x[i+ 1], 4 , -1530992060)
    d = hh(d, a, b, c, x[i+ 4], 11,  1272893353)
    c = hh(c, d, a, b, x[i+ 7], 16, -155497632)
    b = hh(b, c, d, a, x[i+10], 23, -1094730640)
    a = hh(a, b, c, d, x[i+13], 4 ,  681279174)
    d = hh(d, a, b, c, x[i+ 0], 11, -358537222)
    c = hh(c, d, a, b, x[i+ 3], 16, -722521979)
    b = hh(b, c, d, a, x[i+ 6], 23,  76029189)
    a = hh(a, b, c, d, x[i+ 9], 4 , -640364487)
    d = hh(d, a, b, c, x[i+12], 11, -421815835)
    c = hh(c, d, a, b, x[i+15], 16,  530742520)
    b = hh(b, c, d, a, x[i+ 2], 23, -995338651)

    a = ii(a, b, c, d, x[i+ 0], 6 , -198630844)
    d = ii(d, a, b, c, x[i+ 7], 10,  1126891415)
    c = ii(c, d, a, b, x[i+14], 15, -1416354905)
    b = ii(b, c, d, a, x[i+ 5], 21, -57434055)
    a = ii(a, b, c, d, x[i+12], 6 ,  1700485571)
    d = ii(d, a, b, c, x[i+ 3], 10, -1894986606)
    c = ii(c, d, a, b, x[i+10], 15, -1051523)
    b = ii(b, c, d, a, x[i+ 1], 21, -2054922799)
    a = ii(a, b, c, d, x[i+ 8], 6 ,  1873313359)
    d = ii(d, a, b, c, x[i+15], 10, -30611744)
    c = ii(c, d, a, b, x[i+ 6], 15, -1560198380)
    b = ii(b, c, d, a, x[i+13], 21,  1309151649)
    a = ii(a, b, c, d, x[i+ 4], 6 , -145523070)
    d = ii(d, a, b, c, x[i+11], 10, -1120210379)
    c = ii(c, d, a, b, x[i+ 2], 15,  718787259)
    b = ii(b, c, d, a, x[i+ 9], 21, -343485551)

    a = safe_add(a, olda)
    b = safe_add(b, oldb)
    c = safe_add(c, oldc)
    d = safe_add(d, oldd)
  }
  return [a, b, c, d]
}

/*
 * Convert an array of little-endian words to a hex string.
 */
function binl2hex(binarray)
{
  var hex_tab = "0123456789abcdef"
  var str = ""
  for(var i = 0; i < binarray.length * 4; i++)
  {
    str += hex_tab.charAt((binarray[i>>2] >> ((i%4)*8+4)) & 0xF) +
           hex_tab.charAt((binarray[i>>2] >> ((i%4)*8)) & 0xF)
  }
  return str
}

/*
 * Convert an array of little-endian words to a base64 encoded string.
 */
function binl2b64(binarray)
{
  var tab = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  var str = ""
  for(var i = 0; i < binarray.length * 32; i += 6)
  {
    str += tab.charAt(((binarray[i>>5] << (i%32)) & 0x3F) |
                      ((binarray[i>>5+1] >> (32-i%32)) & 0x3F))
  }
  return str
}

/*
 * Convert an 8-bit character string to a sequence of 16-word blocks, stored
 * as an array, and append appropriate padding for MD4/5 calculation.
 * If any of the characters are >255, the high byte is silently ignored.
 */
function str2binl(str)
{
  var nblk = ((str.length + 8) >> 6) + 1 // number of 16-word blocks
  var blks = new Array(nblk * 16)
  for(var i = 0; i < nblk * 16; i++) blks[i] = 0
  for(var i = 0; i < str.length; i++)
    blks[i>>2] |= (str.charCodeAt(i) & 0xFF) << ((i%4) * 8)
  blks[i>>2] |= 0x80 << ((i%4) * 8)
  blks[nblk*16-2] = str.length * 8
  return blks
}

/*
 * Convert a wide-character string to a sequence of 16-word blocks, stored as
 * an array, and append appropriate padding for MD4/5 calculation.
 */
function strw2binl(str)
{
  var nblk = ((str.length + 4) >> 5) + 1 // number of 16-word blocks
  var blks = new Array(nblk * 16)
  for(var i = 0; i < nblk * 16; i++) blks[i] = 0
  for(var i = 0; i < str.length; i++)
    blks[i>>1] |= str.charCodeAt(i) << ((i%2) * 16)
  blks[i>>1] |= 0x80 << ((i%2) * 16)
  blks[nblk*16-2] = str.length * 16
  return blks
}

/*
 * External interface
 */
function hexMD5 (str) { return binl2hex(coreMD5( str2binl(str))) }
function hexMD5w(str) { return binl2hex(coreMD5(strw2binl(str))) }
function b64MD5 (str) { return binl2b64(coreMD5( str2binl(str))) }
function b64MD5w(str) { return binl2b64(coreMD5(strw2binl(str))) }
/* Backward compatibility */
function calcMD5(str) { return binl2hex(coreMD5( str2binl(str))) }

END_OF_JAVASCRIPT
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	print "<h1>Please log in";
	print " - $self->{'system'}->{'description'} database" if $self->{'system'}->{'description'};
	print "</h1>";
	$self->print_banner;
	if ( $self->{'authenticate_error'} ) {
		print "<div class=\"box\" id=\"statusbad\"><p>$self->{'authenticate_error'}</p></div>\n";
	}
	$self->_print_entry_form;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Log in - $desc";
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache);

	# Cookies reference and verify a matching IP address
	my $ip_addr = $ENV{'REMOTE_ADDR'};
	$ip_addr =~ s/\.\d+$//;

	#don't use last part of IP address - due to problems with load-balancing proxies
	$self->{'ip_addr'} = $ip_addr;
	return;
}

sub secure_login {
	( my $self ) = @_;
	my ( $user, $passwordHash ) = $self->_MD5_login;
	######################################################
	# If they've gotten to this point, they have been
	# authorized against the database (they
	# correctly filled in the name/password field)
	# so store their current IP address in the database
	######################################################
	$self->_set_current_user_IP_address( $user, $self->{'ip_addr'} );
	######################################################
	# Set Cookie information with a session timeout
	######################################################
	my $setCookieString = Digest::MD5::md5_hex( $self->{'ip_addr'} . $passwordHash . $uniqueString );
	my @cookies         = ( $passString, $setCookieString, $userCookieName, $user );
	my $cookies_ref     = $self->_set_cookies( \@cookies, $cookie_timeout );
	return ( $user, $cookies_ref );    # SUCCESS, w/cookie header
}

sub login_from_cookie {
	( my $self ) = @_;
	throw BIGSdb::AuthenticationException("No valid session") if $self->{'logged_out'};
	my %Cookies = $self->_get_cookies( $passString, $userCookieName );
	foreach ( keys %Cookies ) {
		$logger->debug("cookie $_ = $Cookies{$_}") if defined $Cookies{$_};
	}
	my $savedPasswordHash = $self->_get_password_hash( $Cookies{$userCookieName} ) || '';
	my $saved_IP_address  = $self->_get_IP_address( $Cookies{$userCookieName} );
	my $cookieString      = Digest::MD5::md5_hex( $self->{'ip_addr'} . $savedPasswordHash . $uniqueString );
	##############################################################
	# Test the cookies against the current database
	##############################################################
	# If the current IP address matches the saved IP address
	# and the current cookie hash matches the saved cookie hash
	# we allow access.
	##############################################################
	if (   $savedPasswordHash
		&& $Cookies{$passString}
		&& $saved_IP_address
		&& $saved_IP_address eq $self->{'ip_addr'}
		&& $Cookies{$passString} eq $cookieString )
	{
		$logger->debug("User cookie validated, allowing access.");

		# good cookie, allow access
		return $Cookies{$userCookieName};
	}
	$Cookies{$passString} ||= '';
	$logger->debug("Cookie not validated. cookie:$Cookies{$passString} string:$cookieString");
	throw BIGSdb::AuthenticationException("No valid session");
}

sub _MD5_login {
	my ($self) = @_;
	$self->_clean_session_database();    # remove entries older than current_time + $timeout
	$self->{'$sessionID'} = Digest::MD5::md5_hex( $self->{'ip_addr'} . $randomNumber . $uniqueString );
	my $current_time = time();
	$self->_create_session( $self->{'$sessionID'}, $current_time );
	if ( $self->{'vars'}->{'Submit'} ) {
		my $log_buffer;
		foreach my $key ( keys %{ $self->{'vars'} } ) {
			$log_buffer .= ' | ' . $key . "=" . $self->{'vars'}->{$key} if $key ne 'password_field' && $key ne 'Submit';
		}
		$logger->info($log_buffer);
		if ( my $session = $self->_check_password() ) {
			$logger->info("User $self->{'vars'}->{'user'} logged in successfully");
			return ( $self->{'vars'}->{'user'}, $session );    # return user name and session
		}
	}

	# This sessionID will be valid for only $screen_timeout seconds
	$self->print_page_content;
	throw BIGSdb::AuthenticationException;
}
####################  END OF MAIN PROGRAM  #######################
sub _check_password {
	my ($self) = @_;
	if ( !$self->{'vars'}->{'user'} )     { $self->_error_exit("The name field was missing."); }
	if ( !$self->{'vars'}->{'password'} ) { $self->_error_exit("The password field was missing."); }
	my $savedPasswordHash = $self->_get_password_hash( $self->{'vars'}->{'user'} ) || '';
	my $hashedPassSession = Digest::MD5::md5_hex( $savedPasswordHash . $self->{'vars'}->{'session'} );
	$logger->debug("using session ID = $self->{'vars'}->{'session'}");
	$logger->debug("Saved password hash for $self->{'vars'}->{'user'} = $savedPasswordHash");
	$logger->debug("Submitted password hash for $self->{'vars'}->{'user'} = $self->{'vars'}->{'password'}");
	$logger->debug("hashed stored pass + session string = $hashedPassSession");
	$logger->debug("hashed submitted pass + session string = $self->{'vars'}->{'hash'}");

	# Compare the calculated hash based on the saved password to
	# the hash returned by the CGI form submission: they must match
	if ( $hashedPassSession ne $self->{'vars'}->{'hash'} ) {
		$self->_error_exit("Invalid username or password entered.  Please try again.");
	} else {
		return $savedPasswordHash;
	}
	return;
}

sub _print_entry_form {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\">\n";
	my $reg_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/registration.html";
	$self->print_file($reg_file) if -e $reg_file;
	print <<"HTML";
<p>Please enter your log-in details.  Part of your IP address is used along with your username to set up your session. 
If you have a session opened on a different computer, where the first three parts of the IP address vary, it will be 
closed when you log in here. </p>
<noscript><p class="highlight">Please note that Javascript must be enabled in order to login.  Passwords are encrypted 
using Javascript prior to transmitting to the server.</p></noscript>
HTML
	print $q->start_form( -onSubmit => "password.value=password_field.value; password_field.value=''; "
		  . "password.value=calcMD5(password.value+user.value); hash.value=calcMD5(password.value+session.value); return true" );
	print "<fieldset><legend>Log in details</legend>\n";
	print "<ul><li><label for=\"user\" class=\"display\">Username: </label>\n";
	print $q->textfield( -name => 'user', -id => 'user', -size => 20, -maxlength => 20, -style => 'width:12em' );
	print "</li><li><label for=\"password_field\" class=\"display\">Password: </label>\n";
	print $q->password_field( -name => 'password_field', -id => 'password_field', -size => 20, -maxlength => 20, -style => 'width:12em' );
	print "</li><li><span style=\"float:right\">";
	print $q->submit( -name => 'Submit', value => 'Log in', -label => 'Log in', -class => 'submit' );
	print "</span></li></ul></fieldset>\n";
	$q->param( 'session',  $self->{'$sessionID'} );
	$q->param( 'hash',     '' );
	$q->param( 'password', '' );

	#Pass all parameters in case page has timed out from an internal page
	my @params = $q->param;
	foreach my $param (@params) {
		next if any { $param eq $_ } qw(password_field user Submit);
		print $q->hidden($param);
	}
	print $q->end_form;
	print "</div>\n";
	return;
}

sub _error_exit {
	my ( $self, $msg ) = @_;
	$self->{'cgi'}->param( 'password', '' );
	$self->{'authenticate_error'} = $msg;
	$self->print_page_content;
	throw BIGSdb::AuthenticationException($msg);
}
#############################################################################
# Authentication Database Code
#############################################################################
sub _get_password_hash {
	my ( $self, $name ) = @_;
	return if !$name;
	my $sql = $self->{'auth_db'}->prepare("SELECT password FROM users WHERE dbase=? AND name=?");
	eval { $sql->execute( $self->{'system'}->{'db'}, $name ) };
	$logger->error($@) if $@;
	my ($password) = $sql->fetchrow_array;
	return $password;
}

sub _set_password_hash {
	my ( $self, $name, $hash ) = @_;
	return if !$name;

	#check if named record already exists
	my $sql = $self->{'auth_db'}->prepare("SELECT COUNT(*) FROM users WHERE dbase=? AND name=?");
	eval { $sql->execute( $self->{'system'}->{'db'}, $name ) };
	$logger->error($@) if $@;
	my ($exists) = $sql->fetchrow_array;
	if ( !$exists ) {
		$sql = $self->{'auth_db'}->prepare("INSERT INTO users (password,dbase,name) VALUES (?,?,?)");
	} else {
		$sql = $self->{'auth_db'}->prepare("UPDATE users SET password=? WHERE dbase=? AND name=?");
	}
	eval { $sql->execute( $hash, $self->{'system'}->{'db'}, $name ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
		return 0;
	} else {
		$self->{'auth_db'}->commit;
		return 1;
	}
}

sub _get_IP_address {
	my ( $self, $name ) = @_;
	return if !$name;
	my $sql = $self->{'auth_db'}->prepare("SELECT ip_address FROM users WHERE dbase=? AND name=?");
	eval { $sql->execute( $self->{'system'}->{'db'}, $name ) };
	$logger->error($@) if $@;
	my ($ip_address) = $sql->fetchrow_array;
	return $ip_address;
}

sub _set_current_user_IP_address {
	my ( $self, $userName, $ip_address ) = @_;
	my $sql = $self->{'auth_db'}->prepare("UPDATE users SET ip_address=? WHERE dbase=? AND name=?");
	eval { $sql->execute( $ip_address, $self->{'system'}->{'db'}, $userName ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$logger->debug("Set IP address for $userName: $ip_address");
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _create_session {
	my ( $self, $session, $time ) = @_;
	my $sql = $self->{'auth_db'}->prepare("SELECT COUNT(*) FROM sessions WHERE dbase=? AND session=?");
	eval { $sql->execute( $self->{'system'}->{'db'}, $session ) };
	$logger->error($@) if $@;
	my ($exists) = $sql->fetchrow_array;
	return if $exists;
	$sql = $self->{'auth_db'}->prepare("INSERT INTO sessions (dbase,session,start_time) VALUES (?,?,?)");
	eval { $sql->execute( $self->{'system'}->{'db'}, $session, $time ) };

	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$logger->debug("Session created: $session");
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _get_session_start_time {
	my ( $self, $session ) = @_;
	return if !$session;
	my $sql = $self->{'auth_db'}->prepare("SELECT start_time FROM sessions WHERE dbase=? AND session=?");
	eval { $sql->execute( $self->{'system'}->{'db'}, $session ) };
	$logger->error($@) if $@;
	my ($start_time) = $sql->fetchrow_array;
	return $start_time;
}

sub _clean_session_database {
	my ($self) = @_;
	my $sql = $self->{'auth_db'}->prepare("DELETE FROM sessions WHERE dbase=? AND start_time<?");
	eval { $sql->execute( $self->{'system'}->{'db'}, ( time - $screen_timeout ) ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$logger->debug("Session database cleaned");
		$self->{'auth_db'}->commit;
	}
	return;
}
#############################################################################
# Cookies Code
#############################################################################
sub logout {
	( my $self ) = @_;
	my $cookies_ref = $self->_clear_cookies( $passString, $userCookieName );
	$self->{'logged_out'} = 1;
	return $cookies_ref;
}

sub _get_cookies {
	my ( $self, @cookieList ) = @_;
	my $query = $self->{'cgi'};
	my %Cookies;
	foreach my $name (@cookieList) {
		$Cookies{$name} = $query->cookie($name);
	}
	return %Cookies;
}

sub _clear_cookies {
	my $self = shift;
	my @cookies;
	foreach my $entry (@_) {
		push( @cookies, $entry );
		push( @cookies, 'x' );
	}
	return $self->_set_cookies( [@cookies], '+0s' );
}

sub _set_cookies {
	my ( $self, $cookieRef, $expires ) = @_;
	my @Cookie_objects;
	my $query = CGI->new;
	while ( my ( $cookie, $value ) = _shift2($cookieRef) ) {
		push( @Cookie_objects, $self->_make_cookie( $query, $cookie, $value, $expires ) );
	}
	return \@Cookie_objects;
}

sub _shift2 { return splice( @{ $_[0] }, 0, 2 ); }

sub _make_cookie {
	my ( $self, $query, $cookie, $value, $expires ) = @_;
	return $query->cookie( -name => $cookie, -value => $value, -expires => $expires, -path => '/', );
}
1;
