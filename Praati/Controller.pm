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

use Encode;

package Praati::Controller {
  use Exporter qw(import);
  BEGIN {
    our @EXPORT_OK = qw(add_ui_error
                        check_user_session_key
                        get_session_user_role
                        query_method
                        response
                        session_user);
  }

  use Praati;
  use Praati::Model qw(one_record one_value);
  use Praati::View;
  use Praati::View::L10N qw(t);

  use BSD::arc4random qw(arc4random_bytes);
  use CGI::Carp;
  use CGI::Fast (-utf8,
                socket_path => ${Praati::Config::FCGI_socket_path},
                socket_perm => 0777);
  use CGI::HTML::Functions;
  use JSON::XS;
  use List::MoreUtils qw(any);
  use Scalar::Util qw(blessed);

  $CGI::Pretty::INDENT = ' ' x 2;

  our ($Q, $Session_user);

  sub main {
    Praati::Model::init();
    Praati::View::init();

    while ($Q = CGI::Fast->new) {
      eval {
        Praati::Model::expire_old_user_sessions();
        handle_query();
      };
      if ($@) { warn($@); }
    }

    Praati::Model::close_db_connection();
  }

  sub handle_query {
    my $user_session_key = $Q->cookie('user_session_key');
    $Session_user = Praati::Model::find_session_user($user_session_key);

    my $response = url_dispatch( $Q->path_info );
    $response->printout($Q);
  }

  sub query_method {
    my $method = shift;
    $Q->$method(@_);
  }

  sub redirect {
    my ($path) = @_;
    response(redirect_uri => ($Q->url . $path),
             status       => 301);
  }

  sub response { Praati::Controller::Response->new(@_); }

  sub url_dispatch {
    my ($path_info) = @_;

    local $_ = $path_info;

    # XXX perhaps, instead of restrict_to_roles(),
    # XXX allow_roles() should be used instead (deny everything by default)
    # XXX note that code should not be evaluated at all if no permission
    # XXX is granted.

    my $page = eval {
      m|^$|
        ? redirect('/main')
        :
      m|^/$|
        ? redirect('/main')
        :
      m|^/listening_events$|
        ? do {
            restrict_to_roles( qw(admin) );
            listening_event_controller();
          }
        :
      m|^/listening_sessions/analysis$|
        ? do {
            restrict_to_roles( qw(admin) );
            listening_session_analysis_controller();
          }
        :
      m|^/listening_sessions/new$|
        ? do {
            restrict_to_roles( qw(admin) );
            new_listening_session_controller();
          }
        :
      m|^/listening_sessions/overview$|
        ? do {
            restrict_to_roles( qw(admin) );
            listening_session_overview_controller();
          }
        :
      m|^/login$|
        ? login_controller()
        :
      m|^/logout$|
        ? logout_controller()
        :
      m|^/main$|
        ? main_controller() # XXX do we need this at all?
        :
      m|^/new_user$|
        ? new_user_controller()
        :
      m|^/panels$|
        ? do {
            restrict_to_roles( qw(admin critic) );
            panels_controller();
          }
        :
      m|^/panels/rate$|
        ? do {
            restrict_to_roles( qw(admin critic) );
            panel_ratings_by_user_controller();
          }
        :
      m|^/panels/send_ratings$|
        ? do {
            restrict_to_roles( qw(admin critic) );
            my $p = eval { panel_async_update_panel_ratings(); };
            if ($@) { Praati::Error::async_request_error($@); }
            $p;
          }
        :
      m|^/song/play$|
        ? do {
            restrict_to_roles( qw(admin critic) );
            play_song_controller();
          }
        :
      Praati::Error::no_such_page()
    };
    my $err = $@;

    if ($err) {
      if (blessed($err)) {
        return async_request_error_controller($err)
          if $err->type eq 'async request error';

        return no_such_page_controller()
          if $err->type eq 'no such page';

        return unauthorized_access_controller()
          if $err->type eq 'unauthorized access';
      }
      confess($err);
    }

    $page;
  }

  sub parse_form_ids_for_table {
    my ($table, $params) = @_;
    my %hash;

    while (my ($key, $value) = each %$params) {
      if ($key =~ /^ \Q$table\E \[(?<id>\d+)\] \. (?<field>.*) $/x) {
        $hash{ $+{id} }{ $+{field} } = $value;
      }
    }

    \%hash;
  }

  sub add_ui_error {
    my ($errors, $field, $error_message) = @_;
    push @{ $errors->{ $field } }, $error_message;
  }

  # we do not want to show unknown error messages to users,
  # but we should log those.

  sub add_unknown_ui_error {
    my ($errors, $field, $message) = @_;
    warn "Unknown error: $message";
    add_ui_error($errors, $field, 'Unknown error');
    return;
  }

  sub check_user_session_key {
    my ($user_session_key) = @_;
    $user_session_key && $user_session_key =~ /^[0-9a-f]{40}$/;
  }

  sub one_record_or_no_such_page {
    my @one_record_params = @_;
    my $result = eval { one_record(@one_record_params); };
    my $err = $@;
    if ($err) {
      Praati::Error::no_such_page()
        if blessed($err) && $err->type eq 'not exactly one';
      confess($err);
    }

    $result;
  }

  sub get_session_user_role {
    session_user()
      ? one_value(q{ select user_role from users where user_id = ?; },
                  session_user())
      : 'anonymous';
  }

  sub restrict_to_roles {
    my @roles = @_;
    my $session_user_role = get_session_user_role();

    return 1 if any(sub { $session_user_role eq $_ }, @roles);

    Praati::Error::unauthorized_access();
  }


  sub session_user { $Session_user; }

  #
  # controllers for pages
  #

  sub listening_event_controller {
    # XXX this could perhaps use listening_events_and_songs_up_to_event_number?
    my $event_and_song
      = one_record_or_no_such_page(
          q{ select * from listening_events
               join ls_song_positions using (listening_session_id, song_position)
               join songinfos using (song_id)
             where listening_event_id = ?; },
          $Q->url_param('listening_event_id'));

    Praati::View::page_listening_event($event_and_song);
  }

  sub listening_session_analysis_controller {
    my $listening_session
      = one_record_or_no_such_page(q{ select * from listening_sessions
                                        where listening_session_id = ?; },
                                   $Q->url_param('listening_session_id'));
    Praati::View::page_listening_session_analysis($listening_session);
  }

  sub listening_session_overview_controller {
    my $listening_session
      = one_record_or_no_such_page(q{ select * from listening_sessions
                                        where listening_session_id = ?; },
                                   $Q->url_param('listening_session_id'));
    Praati::View::page_listening_session_overview($listening_session);
  }

  sub login_controller {
    my %p = $Q->Vars;
    my $errors = {};

    return redirect('/main') if session_user();

    my $user_session_key = $Q->cookie('user_session_key');

    if ($p{submit_login}) {
      if (not check_user_session_key($user_session_key)) {
        add_ui_error($errors,
                     '*',
                     # XXX should use t() but it is *not* available here.
                     'To login, cookies must be accepted by the browser.');
      }

      eval {
        if (not %$errors) {
          Praati::Model::verify_user_password($errors,
                                              @p{ qw(user_email
                                                     user_password) });
        }
        if (not %$errors) {
          Praati::Model::add_user_session($p{user_email}, $user_session_key);
        }
      };
      if ($@) { add_unknown_ui_error($errors, '*', $@); }

      if (not %$errors) {
        return redirect('/main');
      }
    }

    my $new_user_session_key = unpack('h*', arc4random_bytes(20));

    my $expire_hours = "+${Praati::Config::User_session_hours}h";
    my $cookie = $Q->cookie(-expires => $expire_hours,
                            -name    => 'user_session_key',
                            -value   => $new_user_session_key);

    Praati::View::page_login($errors, $cookie);
  }

  sub logout_controller {
    my $user_session_key = $Q->cookie('user_session_key');

    return Praati::View::page_not_logged_in() if not $user_session_key;

    my $errors = {};

    eval { Praati::Model::remove_user_session($user_session_key); };
    my $error = $@;

    if ($error) { add_unknown_ui_error($errors, '*', $error); }

    return Praati::View::page_logout_error($errors) if %$errors;

    # expire cookie
    my $cookie = $Q->cookie(-expires => '-1d',
                            -name    => 'user_session_key',
                            -value   => $user_session_key);

    # must set this so that view (menu generation code specifically)
    # will not think user is logged in now
    $Session_user = undef;

    Praati::View::page_logged_out($cookie);
  }

  sub main_controller {
    Praati::View::page_main();
  }

  sub new_listening_session_controller {
    my $panel = one_record_or_no_such_page(q{ select * from panels
                                                where panel_id = ?; },
                                           $Q->url_param('panel_id'));

    my %p = $Q->Vars;
    my $errors = {};

    if ($p{new_listening_session}) {
      if (!$p{listening_session_name}) {
        add_ui_error($errors,
                     listening_session_name
                       => t('Listening session name is missing.'));
      }

      if (!$p{listening_session_type}) {
        add_ui_error($errors,
                     listening_session_type => t('Session type is missing.'));
      } elsif ($p{listening_session_type} eq 'desc_asc'
                 && (!$p{turning_point_song_position}
                       || $p{turning_point_song_position} !~ /^(\d+)$/)) {
        add_ui_error($errors, turning_point_song_position
                                => t('Song position is not valid'));
      }

      if (not %$errors) {
        my $listening_session_id
          = eval {
              Praati::Model::new_listening_session(
                $panel,
                @p{ qw(listening_session_name
                       listening_session_type
                       turning_point_song_position) });
            };
        my $err = $@;
        if ($err) {
          if (blessed($err) && $err->type eq 'bad turning point') {
            add_ui_error($errors,
                         turning_point_song_position
                           => t('Song position is not valid'));
          }
          else { add_unknown_ui_error($errors, '*', $@); }
        }

        if (!%$errors && $listening_session_id) {
          return redirect('/listening_sessions/overview'
                          . "?listening_session_id=$listening_session_id");
        }
      }
    }

    Praati::View::page_new_listening_session($errors, $panel);
  }

  sub new_user_controller {
    my %p = $Q->Vars;
    my $errors = {};

    if ($p{submit_new_user}) {
      if (not $p{user_password}) {
        add_ui_error($errors, user_password => t('Password is missing.'));
      }
      if (not $p{user_password_again}) {
        add_ui_error($errors, user_password_again => t('Password is missing.'));
      }
      if ($p{user_password} && $p{user_password_again}
            && $p{user_password} ne $p{user_password_again}) {
        add_ui_error($errors, '*', t('Passwords do not match.'));
      }

      eval {
        Praati::Model::add_new_user($errors,
                                    @p{ qw(user_email
                                           user_name
                                           user_password) });
      };
      if ($@) { add_unknown_ui_error($errors, '*', $@); }

      return redirect('/login') unless %$errors;
    }

    Praati::View::page_new_user($errors);
  }

  sub async_request_error_controller {
    my ($err) = @_;
    warn("async request error: $err");
    my $json = encode_json({ errors => [ 'async error' ]});
    response(page => $json, status => 500);
  }

  sub no_such_page_controller {
    response(page   => Praati::View::page_no_such_page(),
             status => 404);
  }

  sub update_panel_ratings_by_user {
    my ($errors, $p, $panel_id, $update) = @_;
    my $panel = one_record_or_no_such_page(q{ select * from panels
                                                where panel_id = ?; },
                                           $panel_id);
    my $user_id = session_user();

    if ($update) {
      my $song_ratings = parse_form_ids_for_table(songs => $p);
      while (my ($song_id, $rating) = each %$song_ratings) {
        if ($rating->{ rating_value }
              eq Praati::Constants::NO_SONG_RATING_MARKER) {
          $song_ratings->{ $song_id }{ rating_value } = undef;
        }
      }

      eval {
        Praati::Model::update_user_ratings($panel->{panel_id},
                                           $user_id,
                                           $song_ratings);
      };
      if ($@) {
        add_unknown_ui_error($errors, '*', $@);
      }
    }

    (panel => $panel, user_id => $user_id);
  }

  sub panel_ratings_by_user_controller {
    my %p = $Q->Vars;
    my $panel_id = $Q->url_param('panel_id');
    my $errors = {};
    my %r = update_panel_ratings_by_user($errors,
                                         \%p,
                                         $panel_id,
                                         $p{send_ratings});
    Praati::View::page_panel_ratings_by_user($errors,
                                             $r{panel},
                                             $r{user_id});
  }

  sub panel_async_update_panel_ratings {
    my %p = $Q->Vars;
    my $panel_id = $p{panel_id};

    my $errors = {};
    my %r;
    eval { %r = update_panel_ratings_by_user($errors, \%p, $panel_id, 1); };
    if ($@) {
      add_unknown_ui_error($errors, '*', "Problem updating user ratings: $@");
    }

    Praati::View::JS::panel_ratings_json($errors, $r{panel}, $r{user_id});
  }

  sub panels_controller {
    Praati::View::page_panels();
  }

  sub play_song_controller {
    my $song = one_record_or_no_such_page(q{ select * from songs
                                               where song_id = ?; },
                                          $Q->url_param('song_id'));

    Praati::View::play_song($song);
  }

  sub unauthorized_access_controller {
    response(page   => Praati::View::page_unauthorized_access(),
             status => 403);
  }
}

package Praati::Controller::Response {
  use Class::Struct __PACKAGE__, {
    cookie       => '$',
    filepath     => '$',
    page         => '$',
    redirect_uri => '$',
    status       => '$',
    type         => '$',
  };

  sub page_header {
    my ($self, $q) = @_;

    my @header_args = (
      -charset => 'UTF-8',
      defined($self->cookie) ? (-cookie => $self->cookie) : (),
      defined($self->status) ? (-status => $self->status) : (),
      defined($self->type  ) ? (-type   => $self->type  ) : (),
    );

    $q->header(@header_args);
  }

  sub printout {
    my ($self, $q) = @_;

    if (defined($self->filepath) && defined($self->type)) {
      return $self->send_file($q);
    }

    my $content
      = defined($self->redirect_uri)
          ? $q->redirect(-status => $self->status,
                         -uri    => $self->redirect_uri)
          :
        defined($self->page)
          ? ($self->page_header($q) . $self->page)
          : undef;

    confess('Not a sensible response object') unless defined $content;

    # FastCGI is not unicode aware
    my $utf8 = Encode::find_encoding('UTF-8');
    print $utf8->encode($content, Encode::FB_DEFAULT);
  }

  # send file in chunks so that sending starts quickly
  # and not much memory is wasted
  sub send_file {
    my ($self, $q) = @_;

    my $filepath = $self->filepath;
    open(my $fd, '<', $filepath)
      or confess("Could not open $filepath for reading: $!");

    print $self->page_header($q);

    my $data;

    for (;;) {
      my $bytes_read = read($fd, $data, 65536); # read 64k chunks
      if (!defined($bytes_read)) {
        warn "Problem reading file: $!";
        last;
      }
      last if $bytes_read == 0;
      print $data;
    }

    close($fd);
  }
}

1;
