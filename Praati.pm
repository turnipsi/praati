# -*- mode: perl; coding: utf-8; -*-
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

# use diagnostics;
use feature qw(unicode_strings);
use strict;
use utf8;
use warnings FATAL => qw(all);

#
# configurations
#

BEGIN {
  package Praati::Config {
    # XXX should maybe read some configuration file?
    my ($home) = ($ENV{HOME} =~ /(.*)/);        # cleanup data for -T

    our $DB_dir             = "${home}/praati-db";
    our $DB_file_path       = "${DB_dir}/praati.sqlite3";
    our $FCGI_socket_path   = '/var/www/run/praati/praati.sock';
    our $Music_path         = "${DB_dir}/music";
    our $User_session_hours = 12;
  }
}

#
# constants
#

package Praati::Constants {
  # XXX database checks could also use this
  use constant MAX_SONG_RATING       => 10.0;

  use constant NO_SONG_RATING_MARKER => '-';
}

#
# errors
#

package Praati::Error {
  use CGI::Carp;
  use Class::Struct __PACKAGE__, { message => '$', type => '$' };

  use overload q{""} => sub { $_[0]->message; };

  sub async_request_error {
    my ($err) = @_;
    confess(
      __PACKAGE__->new(message => "$err",
                       type    => 'async request error'));
  }

  sub bad_turning_point {
    confess(
      __PACKAGE__->new(message => 'Song position is not a valid turning point',
                       type    => 'bad turning point'));
  }

  sub no_such_page {
    confess(
      __PACKAGE__->new(message => 'No such page',
                       type    => 'no such page'));
  }

  sub not_exactly_one {
    my ($count) = @_;
    confess(
      __PACKAGE__->new(
        message => "Would be returning not exactly one value, but $count values",
        type    => 'not exactly one'));
  }

  sub unauthorized_access {
    confess(
      __PACKAGE__->new(message => 'User is not allowed to access this resource',
                       type    => 'unauthorized access'));
  }
}

1;
