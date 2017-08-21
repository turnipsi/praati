# -*- mode: perl; coding: iso-8859-1; -*-
#
# Copyright (c) 2014, 2017 Juha Erkkilä <je@turnipsi.no-ip.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# this code will run as root!

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
use Text::Abbrev            ();
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

CGI->compile(@cgi_methods);

1;
