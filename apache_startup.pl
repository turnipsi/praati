# -*- mode: perl; coding: iso-8859-1; -*-
# $Id: apache_startup.pl,v 1.3 2014/05/17 19:01:37 je Exp $

# this code will run as root!

use autodie                 ();
use autodie::hints          ();
use constant                ();
use diagnostics             ();
use overload                ();
use strict                  ();
use warnings                ();
use BSD::arc4random         ();
use CGI                     ();
use CGI::Carp               ();
use CGI::Cookie             ();
use Class::Struct           ();
use Crypt::SaltedHash       ();
use Data::Dumper            ();
use DBD::SQLite             ();
use DBI                     ();
use Digest::SHA             ();
use Email::Valid            ();
use Encode                  ();
use Encode::Unicode         ();
use Exporter                ();
use File::Basename          ();
use File::Find              ();
use File::Glob              ();
use List::MoreUtils         ();
use List::Util              ();
use Locale::Maketext        ();
use Math::Trig              ();
use MP3::Tag                ();
use POSIX                   ();
use Scalar::Util            ();
use Statistics::Descriptive ();
use Tie::Hash::NamedCapture ();
use URI::Escape             ();

# XXX this list now lives in two places
my @cgi_methods = qw(a
                     div
                     embed
                     end_html
                     escapeHTML
                     form
                     h1
                     h2
                     li
                     meta
                     p
                     path_info
                     password_field
                     popup_menu
                     radio_group
                     start_html
                     submit
                     table
                     td
                     textfield
                     th
                     Tr
                     ul);

CGI->compile(':all', @cgi_methods);

1;
