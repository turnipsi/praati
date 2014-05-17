#!/usr/bin/perl

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

1;
