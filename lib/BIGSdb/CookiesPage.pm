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
package BIGSdb::CookiesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);

sub get_title {
	return 'Cookies';
}

sub print_content {
	my ($self) = @_;
	say q(<h1>BIGSdb cookies</h1>);
	say q(<div class="box" id="resultspanel" style="padding-bottom:5em">);
	say q(<h2>What are cookies?</h2>);
	say q(<p>As is common practice with almost all professional websites this site uses cookies, )
	  . q(which are tiny files that are downloaded to your computer, to improve your experience. )
	  . q(This page describes what information they gather, how we use it and why we sometimes need )
	  . q(to store these cookies. We will also share how you can prevent these cookies from being stored, )
	  . q(although this may downgrade or 'break' certain elements of the site's functionality.</p>);
	say q(<p>Please see <a href="https://cookiesandyou.com/">https://cookiesandyou.com/</a> for more general )
	  . q(information about cookies.</p>);
	say q(<h2>How we use cookies</h2>);
	say q(<p>We use cookies for a variety of reasons detailed below. Unfortunately in most cases there are )
	  . q(no industry standard options for disabling cookies without completely disabling the functionality )
	  . q(and features they add to this site. It is recommended that you leave on all cookies if you are not )
	  . q(sure whether you need them or not in case they are used to provide a service that you use.<p>);
	say q(<h2>Disabling cookies</h2>);
	say q(<p>You can prevent the setting of cookies by adjusting the settings on your browser )
	  . q((see your browser Help for how to do this). Be aware that disabling cookies will affect the functionality )
	  . q(of this and many other websites that you visit. Therefore it is recommended that you do not disable )
	  . q(cookies.</p>);
	say q(<h2>The cookies we set</h2>);
	say q(<h3>Login related cookies</h3>);
	say q(<p>We use cookies when you are logged in so that we can remember this fact. This prevents you from )
	  . q(having to log in every time you visit a new page. These cookies are typically removed or cleared )
	  . q(when you log out, or after 12 hours, to ensure that you can only access restricted features and )
	  . q(areas when logged in.</p>);
	say q(<h3>Site preferences cookies</h3>);
	say q(<p>In order to improve your experience on this site we provide the functionality to set your preferences )
	  . q(for how this site runs when you use it. In order to remember your preferences we need to set cookies so that )
	  . q(this information can be called whenever you interact with a page that is affected by your preferences.</p>);
	say q(</div>);
	return;
}
1;
