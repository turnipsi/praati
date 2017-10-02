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

package Praati::Model {
  use Exporter qw(import);
  BEGIN {
    our @EXPORT_OK = qw(columns
                        last_insert_id
		        one_record
		        one_value
		        query
		        records
		        rows);
  }

  use Praati;
  use Praati::Controller qw(add_ui_error check_user_session_key);
  use Praati::View::L10N qw(t);

  use CGI::Carp;
  use Crypt::SaltedHash;
  use DBI;
  use Email::Valid;
  use Errno;
  use File::Glob qw(bsd_glob);
  use Math::Trig;
  use Scalar::Util qw(blessed);

  our $Db;

  sub init {
    mkdir ${Praati::Config::DB_dir}
      or $!{EEXIST}
      or confess("Could not create ${Praati::Config::DB_dir}: $!");

    setup_database(${Praati::Config::DB_file_path});

    open_db_connection(${Praati::Config::DB_file_path});

    init_db_tables();

    return;
  }

  sub setup_database {
    my ($db_file_path) = @_;

    # perhaps this should not be done from the application itself...

    # if $db_file_path exists we presume everything is cool
    # and proceed no further
    return 1 if -e $db_file_path;

    # this will setup new database from scratch
    # (would destroy the old if it somehow could exist)
    # (of course it can, it is a classic race condition))

    my $tmpfile = "${db_file_path}.tmp";

    unlink($tmpfile);

    open_db_connection($tmpfile);
    create_db_tables();
    close_db_connection();

    rename($tmpfile, $db_file_path)
      or confess("Could not rename a database file to a new path: $!");
  }

  sub open_db_connection {
    my ($db_file_path) = @_;

    my %attrs = (
      AutoCommit                       => 1,
      PrintError                       => 0,
      RaiseError                       => 1,
      sqlite_allow_multiple_statements => 1,
      sqlite_unicode                   => 1,
    );
    $Db = DBI->connect("dbi:SQLite:dbname=$db_file_path",
                       '',
                       '',
                       \%attrs);
    $Db->do('PRAGMA foreign_keys = ON');

    Praati::Model::SQLite::register_sqlite_functions();
  }

  sub close_db_connection {
    if ($Db) { $Db->disconnect; }
  }

  sub create_db_tables {
    # XXX These tables allow song_rating_values that are not a multiple
    # XXX of 0.5.  This is otherwise okay, except it is possible to input
    # XXX these "non-supported" values into the database through the web forms,
    # XXX but these values do not show up properly in the form.

    query(q{
      create table if not exists users (
        user_id                 integer      primary key not null,
        user_email              varchar(256) unique      not null
                                check(check_user_email(user_email)),
        user_encrypted_password varchar(256)             not null,
        user_name               varchar(256) unique      not null,
        user_role               varchar(256)             not null
                                check(user_role in ('admin', 'critic'))
      );

      create table if not exists user_sessions (
        user_session_id         integer      primary key not null,
        user_session_expires_at timestamp    not null,
        user_session_key        varchar(256) unique not null
          check(check_user_session_key(user_session_key)),
        user_id                 integer      not null references users(user_id)
      );

      create table if not exists panels (
        panel_id        integer      primary key not null,
        panel_musicpath varchar(256) unique not null,
        panel_name      varchar(256) unique not null
      );

      create table if not exists songs (
        song_id       integer      primary key not null,
        song_filepath varchar(256) unique not null,
        song_name     varchar(256) not null,
        artist_id     integer      not null references artists(artist_id)
      );

      create table if not exists albums (
        album_id   integer      primary key not null,
        album_name varchar(256) unique not null,
        album_year integer      not null
      );

      create table if not exists artists (
        artist_id   integer      primary key not null,
        artist_name varchar(256) unique not null
      );

      create table if not exists songs_in_albums (
        album_id     integer not null references albums(album_id),
        song_id      integer not null references songs(song_id),
        track_number integer not null,

        primary key(album_id, song_id)
      );

      create table if not exists songs_in_panels (
        album_id integer not null references albums(album_id),
        panel_id integer not null references panels(panel_id),
        song_id  integer not null references songs(song_id),

        primary key(panel_id, song_id)
      );

      create table if not exists song_ratings (
        song_rating_id      integer       primary key not null,
        song_rating_comment varchar(4096) not null,
        panel_id            integer       not null references panels(panel_id),
        song_id             integer       not null references songs(song_id),
        user_id             integer       not null references users(user_id),

        unique(panel_id, song_id, user_id)
      );

      create table if not exists song_rating_values (
        song_rating_value_id    integer    primary key not null,
        song_rating_value_value decimal(2) not null
          check(0 <= song_rating_value_value
                 and song_rating_value_value <= 10),

        song_rating_id integer unique not null
          references song_ratings(song_rating_id)
            on delete cascade
      );

      create table if not exists song_rating_normalized_values (
        song_rating_normalized_value_id    integer    primary key not null,
        song_rating_normalized_value_value decimal(5) not null
          check(0 <= song_rating_normalized_value_value
                 and song_rating_normalized_value_value <= 10),

        song_rating_value_id integer unique not null
          references song_rating_values(song_rating_value_id)
            on delete cascade
      );

      create table if not exists listening_sessions (
        listening_session_id   integer      primary key not null,
        listening_session_name varchar(256) unique not null,
        panel_id               integer      not null references panels(panel_id)
      );

      create table if not exists listening_events (
        listening_event_id     integer primary key not null,
        listening_event_number integer not null,
        listening_event_shown  integer not null,
        listening_session_id   integer not null
          references listening_sessions(listening_session_id),
        song_position          integer not null,

        unique(listening_event_number, listening_session_id)
      );

      create table if not exists ls_song_positions (
        ls_song_position_id  integer primary key not null,
        listening_session_id integer not null references
          listening_sessions(listening_session_id),
        song_id              integer not null references songs(song_id),
        song_position        integer not null,

        unique(listening_session_id, song_position)
      );

      create table if not exists ls_song_ratings (
        ls_song_rating_id    integer primary key not null,
        listening_session_id integer not null
          references listening_sessions(listening_session_id),
        song_rating_comment varchar(4096) not null,
        song_id             integer       not null references songs(song_id),
        user_id             integer       not null references users(user_id),

        unique(listening_session_id, song_id, user_id)
      );

      create table if not exists ls_song_rating_values (
        ls_song_rating_value_id integer primary key not null,

        song_rating_value_value decimal(2) not null
          check(0 <= song_rating_value_value
                 and song_rating_value_value <= 10),

        song_rating_normalized_value_value decimal(5) not null
          check(0 <= song_rating_normalized_value_value
                 and song_rating_normalized_value_value <= 10),

        ls_song_rating_id integer unique not null
          references ls_song_ratings(ls_song_rating_id)
            on delete cascade
      );

      create table if not exists user_rating_correlations_cache (
        user_rating_correlation_cache_id integer primary key not null,
        listening_session_id integer not null
          references listening_sessions(listening_session_id),
        up_to_event_number integer not null,
        user_a_id          integer not null references users(user_id),
        user_b_id          integer not null references users(user_id),

        rating_correlation            decimal(5) not null,
        normalized_rating_correlation decimal(5) not null
      );

      -- create views

      create view if not exists songinfos
        as select * from songs
          join artists         using (artist_id)
          join songs_in_panels using (song_id)
          join songs_in_albums using (album_id, song_id)
          join albums          using (album_id);

      create view if not exists albums_in_panels
        as select distinct albums.*, songs_in_panels.panel_id
             from albums
               join songs_in_panels using (album_id);

      create view if not exists song_ratings_with_values
        as select * from song_ratings
             left outer join song_rating_values using (song_rating_id);

      create view if not exists song_ratings_with_normalized_values
        as select * from song_ratings_with_values
             left outer join song_rating_normalized_values
                               using (song_rating_value_id);

      create view if not exists user_ratings_statistics
        as select avg(song_rating_value_value)
                    as user_ratings_statistics_mean,
                  stdev(song_rating_value_value)
                    as user_ratings_statistics_stdev,
                  song_ratings_with_values.panel_id,
                  song_ratings_with_values.user_id
             from song_ratings_with_values
               where song_rating_value_value is not null
               group by panel_id, user_id;

      create view if not exists ls_song_ratings_with_sessions
        as select * from ls_song_ratings
             join listening_sessions using (listening_session_id);

      create view if not exists ls_song_ratings_with_values
        as select * from ls_song_ratings
             left outer join ls_song_rating_values using (ls_song_rating_id);

      create view if not exists ls_song_ratings_with_set_values
        as select * from ls_song_ratings_with_values
             where song_rating_value_value is not null
               and song_rating_normalized_value_value is not null;

      create view if not exists ls_song_rating_results
        as select avg(song_rating_value_value)
                    as song_rating_value_avg,
                  avg(song_rating_normalized_value_value)
                    as song_normalized_rating_value_avg,
                  stdev(song_rating_value_value)
                    as song_rating_value_stdev,
                  stdev(song_rating_normalized_value_value)
                    as song_normalized_rating_value_stdev,
                  listening_session_id,
                  song_id
             from ls_song_ratings_with_set_values
               group by listening_session_id, song_id
               order by song_normalized_rating_value_avg desc,
                        song_rating_value_avg desc,
                        song_normalized_rating_value_stdev asc,
                        song_rating_value_stdev asc;

      create view if not exists ls_song_ratings_with_set_values_and_sessions
        as select * from ls_song_ratings_with_set_values
             join listening_sessions using (listening_session_id);

      create view if not exists listening_events_up_to_event_number
        as select a.*, b.listening_event_number as up_to_event_number
             from listening_events as a
               cross join listening_events as b
             where a.listening_event_number <= b.listening_event_number
               and a.listening_session_id = b.listening_session_id;

      create view if not exists listening_events_and_ratings_up_to_event_number
        as select *
             from listening_events_up_to_event_number
               join ls_song_positions using (listening_session_id, song_position)
               join ls_song_ratings_with_set_values
                      using (listening_session_id, song_id);

      create view if not exists user_rating_comparisons
        as select
             a.listening_session_id,
             a.song_id,
             a.up_to_event_number,
             a.user_id as user_a_id,
             b.user_id as user_b_id,
             a.song_rating_value_value as user_a_rating,
             b.song_rating_value_value as user_b_rating,
             a.song_rating_normalized_value_value as user_a_normalized_rating,
             b.song_rating_normalized_value_value as user_b_normalized_rating
               from listening_events_and_ratings_up_to_event_number as a
                 cross join listening_events_and_ratings_up_to_event_number as b
             where              a.song_id = b.song_id
               and a.listening_session_id = b.listening_session_id
               and   a.up_to_event_number = b.up_to_event_number
               and             a.user_id != b.user_id;

      create view if not exists user_rating_correlations
        as select listening_session_id,
                  up_to_event_number,
                  user_a_id,
                  user_b_id,
                  corr(user_a_rating, user_b_rating)
                    as rating_correlation,
                  corr(user_a_normalized_rating, user_b_normalized_rating)
                    as normalized_rating_correlation
             from user_rating_comparisons
               group by listening_session_id,
                        up_to_event_number,
                        user_a_id,
                        user_b_id;

      create view if not exists user_rating_correlations_with_users
        as select user_rating_correlations_cache.*,
                  users_a.user_name as user_a_user_name,
                  users_b.user_name as user_b_user_name
             from user_rating_correlations_cache
               join users as users_a
                 cross join users as users_b
               where user_a_id = users_a.user_id
                 and user_b_id = users_b.user_id;

      -- create triggers

      create trigger if not exists insert_songinfos
        instead of insert on songinfos
          begin
            insert or ignore into artists (artist_name)
              values (new.artist_name);

            insert or ignore into albums (album_name, album_year)
              values (new.album_name, new.album_year);

            -- album_name is unique
            update albums
              set album_year = max(album_year, new.album_year)
                where album_name = new.album_name;

            -- artist_name is unique
            insert into songs (song_filepath, song_name, artist_id)
              select new.song_filepath, new.song_name, artist_id
                from artists where artist_name = new.artist_name;

            -- album_name and song_filepath are unique
            insert into songs_in_albums (album_id, song_id, track_number)
              select album_id, song_id, new.track_number
                from albums join songs
                  where    album_name = new.album_name
                    and song_filepath = new.song_filepath;

            -- album_name and song_filepath are unique
            insert into songs_in_panels (album_id, panel_id, song_id)
              select album_id, new.panel_id, song_id
                from albums join songs
                  where    album_name = new.album_name
                    and song_filepath = new.song_filepath;
          end;

      create trigger if not exists insert_song_ratings_with_values
        instead of insert on song_ratings_with_values
          begin
            insert or replace into song_ratings (song_rating_comment,
                                                 panel_id,
                                                 song_id,
                                                 user_id)
              values (new.song_rating_comment,
                      new.panel_id,
                      new.song_id,
                      new.user_id);

            insert or replace into song_rating_values (song_rating_value_value,
                                                       song_rating_id)
              select new.song_rating_value_value, song_ratings.song_rating_id
                from song_ratings
                  where new.song_rating_value_value is not null
                    and song_ratings.panel_id = new.panel_id
                    and song_ratings.song_id  = new.song_id
                    and song_ratings.user_id  = new.user_id;
          end;

      create trigger if not exists delete_normalized_song_ratings
        after insert on song_rating_values
          begin
            delete from song_rating_normalized_values
              where song_rating_value_id in (
                select b.song_rating_value_id
                  from song_ratings_with_values as a
                    cross join song_ratings_with_values as b
                  where a.song_rating_id = new.song_rating_id
                    and a.panel_id       = b.panel_id
                    and a.user_id        = b.user_id
              );
          end;

    });
  }

  sub init_db_tables {
    my @musicdirs = bsd_glob("${Praati::Config::Music_path}/*");

    foreach my $musicdir (@musicdirs) {
      transaction(sub {
        my $panels
          = records(q{ select * from panels where panel_musicpath = ?; },
                    $musicdir);

        if (@$panels == 0) {
          Praati::Model::Musicscan::init_panel($musicdir);
        }
      });
    }
  }

  # DBI helpers

  sub columns {
    my ($sql, @bind_values) = @_;
    $Db->selectcol_arrayref($sql, {}, @bind_values);
  }

  sub last_insert_id { $Db->last_insert_id('', '', '', ''); }

  sub one_exactly {
    my ($values) = @_;
    my $count = scalar(@$values);

    if ($count != 1) { Praati::Error::not_exactly_one($count); }

    $values->[0];
  }

  sub one_record { one_exactly( records(@_) ); }
  sub one_value  { one_exactly( columns(@_) ); }

  sub query {
    my ($sql, @bind_values) = @_;
    $Db->do($sql, undef, @bind_values);
  }

  sub records {
    my ($sql, @bind_values) = @_;
    $Db->selectall_arrayref($sql, { Slice => {} }, @bind_values);
  }

  sub rows {
    my ($sql, @bind_values) = @_;
    $Db->selectall_arrayref($sql, undef, @bind_values);
  }

  sub test { @{ records(@_) }  >  0; }

  sub transaction {
    my ($fn) = @_;

    $Db->begin_work;

    eval {
      $fn->();
      $Db->commit;
    };
    my $db_error = $@;

    if ($db_error) {
      eval { $Db->rollback; };
      my $rollback_error = $@;

      eval {
        if ($rollback_error) {
          warn "Could not do a database rollback: $rollback_error";
        };
      };

      confess($db_error);
    }
  }

  #
  # user handling
  #

  sub add_new_user {
    my ($errors, $user_email, $user_name, $user_password) = @_;

    my $user_encrypted_password = crypt_password($user_password);
    my $user_role               = new_user_role();

    if (not check_user_email($user_email)) {
      add_ui_error($errors, 'user_email', t('User email address is not valid.'));
    }

    transaction(sub {
      if (test(q{ select user_id from users where user_email = ?; },
                $user_email)) {
        add_ui_error($errors,
                     'user_email',
                     t('Email address is already reserved.'));
      }

      if (test(q{ select user_id from users where user_name = ?; },
                $user_name)) {
        add_ui_error($errors, 'user_name', t('Username is already reserved.'));
      }

      if (not %$errors) {
        query(q{ insert into users (user_email,
                                    user_encrypted_password,
                                    user_name,
                                    user_role)
                   values (?, ?, ?, ?); },
              $user_email,
              $user_encrypted_password,
              $user_name,
              $user_role);
      }
    });
  }

  sub check_user_email {
    my ($user_email) = @_;
    Email::Valid->address($user_email) ? 1 : 0;
  }

  # XXX should you just use crypt instead?
  # XXX are blowfish passwords portable?
  # XXX how to generate salt for those?
  sub crypt_password {
    my ($password) = @_;
    my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
    $csh->add($password);
    $csh->generate;
  }

  sub new_user_role {
    # the first user created will be admin, the rest of them are merely critics
    one_value(q{ select count(user_id) from users; }) == 0
      ? 'admin'
      : 'critic';
  }

  sub verify_user_password {
    my ($errors, $user_email, $user_password) = @_;

    my $salted_hash;
    eval {
      $salted_hash = one_value(q{ select user_encrypted_password from users
                                     where user_email = ?; },
                                $user_email);
    };
    my $err = $@;

    if ((blessed($err) && $err->type eq 'not exactly one')
          or not Crypt::SaltedHash->validate($salted_hash, $user_password)) {
      add_ui_error($errors, '*', t('Wrong username or password.'));
    }
  }

  #
  # user sessions handling
  #

  sub add_user_session {
    my ($user_email, $user_session_key) = @_;

    my $sql_hours = "+${Praati::Config::User_session_hours} hours";

    query(q{ insert into user_sessions (user_session_expires_at,
                                        user_session_key,
                                        user_id)
               select datetime('now', ?),
                      ?,
                      user_id
                 from users where user_email = ?; },
          $sql_hours,
          $user_session_key,
          $user_email);
  }

  sub expire_old_user_sessions {
    query(q{ delete from user_sessions
               where user_session_expires_at < datetime('now'); });
  }

  sub find_session_user {
    my ($user_session_key) = @_;

    return if not defined($user_session_key);

    my $user_id = eval {
                    one_value(q{ select user_id from user_sessions
                                   where user_session_key = ?; },
                              $user_session_key);
                  };
    my $error = $@;

    return $user_id if not $error;

    return if blessed($error) && $error->type eq 'not exactly one';

    warn "Unknown error in find_session_user: $error";

    return;
  }

  sub remove_user_session {
    my ($user_session_key) = @_;
    query(q{ delete from user_sessions where user_session_key = ?; },
          $user_session_key);
  }

  #
  # user ratings handling
  #

  sub cdf_normal {
    my ($mean, $stdev, $rating_value) = @_;

    $stdev = defined($stdev) && $stdev > 0  ?  $stdev  :  0.00001;

    my $sum = my $value = my $x = ($rating_value - $mean) / $stdev;

    for (my $i = 1; $i <= 100; $i++) {
      $value = $value * $x * $x / (2 * $i + 1);
      $sum += $value;
    }

    0.5 + ($sum / sqrt(2 * pi)) * exp(- ($x * $x) / 2);
  }

  sub normalized_rating {
    my ($mean, $stdev, $rating_value) = @_;

    Praati::Constants::MAX_SONG_RATING
      * cdf_normal($mean, $stdev, $rating_value);
  }

  sub update_user_ratings {
    my ($panel_id, $user_id, $song_ratings) = @_;

    transaction(sub {
      my $sth = $Db->prepare(q{ insert or replace into song_ratings_with_values
                                    (song_rating_comment,
                                     song_rating_value_value,
                                     panel_id,
                                     song_id,
                                     user_id)
                                  values (?, ?, ?, ?, ?); });

      while (my ($song_id, $song_rating) = each(%$song_ratings)) {
        $sth->execute($song_rating->{rating_comment},
                      $song_rating->{rating_value},
                      $panel_id,
                      $song_id,
                      $user_id);
      }

      query(q{
              insert into song_rating_normalized_values
                  (song_rating_normalized_value_value,
                   song_rating_value_id)
                select normalized_rating(user_ratings_statistics_mean,
                                         user_ratings_statistics_stdev,
                                         song_rating_value_value),
                       song_rating_value_id
                  from song_ratings_with_normalized_values
                    join user_ratings_statistics using (panel_id, user_id)
                  where panel_id = ?
                    and user_id  = ?
                    and song_rating_value_value is not null
                    and song_rating_normalized_value_value is null; },
            $panel_id,
            $user_id);
    });
  }

  #
  # listening sessions handling
  #

  sub find_listening_events_by_song_positions {
    my ($song_ids, $ls_type, $turning_point_song_position) = @_;

    my $songcount = scalar(@$song_ids);

    my @song_positions_by_listening_events = (
      $ls_type eq 'asc'
        ? (undef, reverse(1 .. $songcount))
        :

      ($ls_type eq 'desc_asc')
        ? do {
            Praati::Error::bad_turning_point()
              unless 1 <= $turning_point_song_position
                       && $turning_point_song_position <= $songcount;

            (undef, $turning_point_song_position .. $songcount,
                    reverse(1 .. ($turning_point_song_position - 1)));
          }
        :

      confess("Invalid listening_session type: '$ls_type'")
    );

    # makes a hash
    map { $song_positions_by_listening_events[$_] => $_ }
      (1 .. $#song_positions_by_listening_events);
  }

  sub new_listening_session {
    my ($panel, $ls_name, $ls_type, $turning_point_song_position) = @_;

    my $listening_session_id;

    transaction(sub {
      query(q{ insert into listening_sessions (listening_session_name, panel_id)
               values (?, ?); },
            $ls_name,
            $panel->{panel_id});

      $listening_session_id = last_insert_id();

      query(q{
              insert into ls_song_ratings (listening_session_id,
                                           song_rating_comment,
                                           song_id,
                                           user_id)
                select ?, song_rating_comment, song_id, user_id
                  from song_ratings
                    where panel_id = ?; },
            $listening_session_id,
            $panel->{panel_id});

      query(q{
              insert into ls_song_rating_values
                  (song_rating_value_value,
                   song_rating_normalized_value_value,
                   ls_song_rating_id)
                select srwnv.song_rating_value_value,
                       srwnv.song_rating_normalized_value_value,
                       ls_song_ratings_with_sessions.ls_song_rating_id
                  from song_ratings_with_normalized_values as srwnv
                    cross join ls_song_ratings_with_sessions
                where srwnv.song_rating_value_value is not null
                  and srwnv.song_rating_normalized_value_value is not null
                  and ls_song_ratings_with_sessions.panel_id = srwnv.panel_id
                  and ls_song_ratings_with_sessions.song_id  = srwnv.song_id
                  and ls_song_ratings_with_sessions.user_id  = srwnv.user_id
                  and ls_song_ratings_with_sessions.listening_session_id = ?; },
            $listening_session_id);

      my $song_ids = columns(q{ select song_id from ls_song_rating_results
                                  where listening_session_id = ?; },
                             $listening_session_id);

      my $add_song_positions_sth = $Db->prepare(q{
        insert into ls_song_positions
            (listening_session_id, song_id, song_position)
          values (?, ?, ?);
      });

      my $add_listening_events_sth = $Db->prepare(q{
        insert into listening_events (listening_event_number,
                                      listening_event_shown,
                                      listening_session_id,
                                      song_position)
          values (?, ?, ?, ?);
      });

      my %listening_events_by_song_positions
        = find_listening_events_by_song_positions($song_ids,
                                                  $ls_type,
                                                  $turning_point_song_position);

      for (my $song_pos = 1;
           defined($song_ids->[ $song_pos - 1 ]);
           $song_pos++) {
        $add_song_positions_sth->execute($listening_session_id,
                                         $song_ids->[ $song_pos - 1 ],
                                         $song_pos);

        my $ls_song_position_id = last_insert_id();

        $add_listening_events_sth
          ->execute($listening_events_by_song_positions{$song_pos},
                    0,
                    $listening_session_id,
                    $song_pos);

      }

      query(q{
              insert into user_rating_correlations_cache
                  (listening_session_id,
                   up_to_event_number,
                   user_a_id,
                   user_b_id,
                   rating_correlation,
                   normalized_rating_correlation)
                select listening_session_id,
                       up_to_event_number,
                       user_a_id,
                       user_b_id,
                       rating_correlation,
                       normalized_rating_correlation
                  from user_rating_correlations
                    where listening_session_id = ?; },
            $listening_session_id);
    });

    $listening_session_id;
  }
}

package Praati::Model::Musicscan {
  use Praati::Model qw(last_insert_id query);

  use CGI::Carp;
  use Encode;
  use File::Basename;
  use File::Find;
  use MP3::Tag;

  sub init_panel {
    my ($panel_musicpath) = @_;
    my $panel_name = fileparse($panel_musicpath);

    query(q{ insert into panels (panel_musicpath, panel_name) values (?, ?); },
          $panel_musicpath,
          $panel_name);

    my $panel_id = last_insert_id();
    my @mp3_filepaths = find_files(sub { /\.mp3$/ }, $panel_musicpath);

    my $sth
      = $Praati::Model::Db->prepare(q{
          insert into songinfos (artist_name,
                                 album_name,
                                 album_year,
                                 song_filepath,
                                 song_name,
                                 track_number,
                                 panel_id)
            values (?, ?, ?, ?, ?, ?, ?); });

    MP3::Tag->config(decode_encoding_v1 => 'utf-8');
    MP3::Tag->config(decode_encoding_v2 => 'utf-8');

    foreach my $mp3_filepath (@mp3_filepaths) {
      my $mp3_filepath_utf8;
      eval {
        $mp3_filepath_utf8 = Encode::decode_utf8($mp3_filepath,
                                                 Encode::FB_CROAK);
      };
      if ($@) {
        croak("MP3 filename '$mp3_filepath' is not a valid utf8-string: $@");
      }

      my $mp3tag = MP3::Tag->new($mp3_filepath_utf8);
      add_song($sth, $panel_id, $mp3_filepath_utf8, $mp3tag);
    }
  }

  sub find_files {
    my ($check_fn, $dir) = @_;
    my @files;
    find({ no_chdir => 1,
           wanted   => sub { push @files, $_ if $check_fn->(); } },
         $dir);
    @files;
  }

  sub add_song {
    my ($sth, $panel_id, $mp3_filepath, $mp3tag) = @_;

    foreach my $field (qw(album artist title track1 year)) {
      unless ($mp3tag->$field) {
        confess("The mp3 file $mp3_filepath is missing $field");
      }
    }

    $sth->execute($mp3tag->artist,
                  $mp3tag->album,
                  $mp3tag->year,
                  $mp3_filepath,
                  $mp3tag->title,
                  $mp3tag->track1,
                  $panel_id);
  }
}

package Praati::Model::SQLite {
  sub register_sqlite_functions {
    my $db = ${Praati::Model::Db};

    $db->sqlite_create_function('check_user_email',
                                1,
                               \&Praati::Model::check_user_email);

    $db->sqlite_create_function('check_user_session_key',
                                1,
                                \&Praati::Model::check_user_session_key);

    $db->sqlite_create_function('normalized_rating',
                                3,
                                \&Praati::Model::normalized_rating);

    $db->sqlite_create_aggregate('stdev',
                                 1,
                                 'Praati::Model::SQLite::StandardDeviation');

    $db->sqlite_create_aggregate('corr',
                                 2,
                                 'Praati::Model::SQLite::Correlation');
  }
}

package Praati::Model::SQLite::Correlation {
  use List::MoreUtils qw(pairwise);
  use List::Util qw(sum);

  sub new {
    my ($class) = @_;
    bless { a => [], b => [] } => $class;
  }

  sub step {
    my ($self, $value_a, $value_b) = @_;
    push @{ $self->{a} }, $value_a;
    push @{ $self->{b} }, $value_b;
  }

  sub finalize {
    my ($self) = @_;

    my @a = @{ $self->{a} };
    my @b = @{ $self->{b} };

    confess('Different number of elements in correlation calculation')
      unless scalar(@a) == scalar(@b);

    my $count = scalar(@a);

    confess('No elements in correlation calculation') unless $count > 0;

    my $sum_a = sum(@a);
    my $sum_b = sum(@b);

    my $sum_a_sq = sum(map { $_ ** 2 } @a);
    my $sum_b_sq = sum(map { $_ ** 2 } @b);

    my $sum_a_b_prod = sum(pairwise { $a * $b } @a, @b);

    my $numerator = $count * $sum_a_b_prod - $sum_a * $sum_b;
    my $denom_1   = sqrt($count * $sum_a_sq - $sum_a ** 2);
    my $denom_2   = sqrt($count * $sum_b_sq - $sum_b ** 2);

    ($denom_1 != 0 && $denom_2 != 0)
      ? $numerator / ($denom_1 * $denom_2)
      :
    ($denom_1 != 0 || $denom_2 != 0)
      ? 0.0
      :
    1.0;
  }
}

package Praati::Model::SQLite::StandardDeviation {
  use Statistics::Descriptive;

  sub new { bless [] => $_[0]; }

  sub step {
    my ($self, $value) = @_;
    push @$self, $value;
  }

  sub finalize {
    my ($self) = @_;
    my $stat = Statistics::Descriptive::Sparse->new();
    $stat->add_data(@$self);
    $stat->standard_deviation();
  }
}

1;
