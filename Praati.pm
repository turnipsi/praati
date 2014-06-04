# -*- mode: perl; coding: iso-8859-1; -*-
# $Id: Praati.pm,v 1.32 2014/06/04 19:21:58 je Exp $

# use diagnostics;
use strict;
use warnings FATAL => qw(all);

use Praati::View::L10N;

#
# configurations
#

package Praati::Config {
  our $WWW_dir = '/'; # XXX in OpenBSD Apache chroot only...

  our $DB_dir       = 'db';
  our $DB_file_path = "${WWW_dir}/${DB_dir}/praati.sqlite3";

  our $Music_path = "${WWW_dir}/${DB_dir}/music";

  our $User_session_hours = 12;
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
  use Class::Struct __PACKAGE__, { message => '$', type => '$' };

  use overload q{""} => sub { $_[0]->message; };

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


#
# declarations (when imported into other namespaces)
#

package Praati::Controller {
  use Exporter qw(import);
  our @EXPORT = qw(add_ui_error
                   check_user_session_key
                   get_session_user_role
                   query_method
                   response
                   session_user);

  sub add_ui_error;
  sub check_user_session_key;
  sub get_session_user_role;
  sub query_method;
  sub response;
  sub session_user;
}

package Praati::Model {
  use Exporter qw(import);
  our @EXPORT = qw(last_insert_id
                   one_record
                   one_value
                   query
                   records
                   records_by_key
                   rows);

  sub last_insert_id;
  sub one_record;
  sub one_value;
  sub query;
  sub records;
  sub records_by_key;
  sub rows;
}

#
# model
#

package Praati::Model {
  Praati::Controller->import;
  Praati::View::L10N->import;

  use CGI::Carp;
  use Crypt::SaltedHash;
  use DBI;
  use Email::Valid;
  use File::Glob qw(bsd_glob);
  use Math::Trig;
  use Scalar::Util qw(blessed);

  our $Db;

  sub init {
    setup_database(${Praati::Config::DB_file_path});

    open_db_connection(${Praati::Config::DB_file_path});

    init_db_tables();
    debug_query();
    expire_old_user_sessions();

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
        as select user_rating_correlations.*,
                  users_a.user_name as user_a_user_name,
                  users_b.user_name as user_b_user_name
             from user_rating_correlations
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

  sub records_by_key {
    my ($key, $sql, @bind_values) = @_;
    $Db->selectall_hashref($sql, $key, undef, @bind_values);
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

  sub debug_query {
    # use Data::Dumper;
    # warn Dumper(
    #        records(q{ select * from user_rating_correlations
    #                     order by up_to_event_number; }));
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
    });
  }

  sub update_user_normalized_ratings {
    my ($panel_id, $user_id) = @_;

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
    });

    $listening_session_id;
  }
}

package Praati::Model::Musicscan {
  Praati::Model->import;

  use CGI::Carp;
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

    foreach my $mp3_filepath (@mp3_filepaths) {
      my $mp3tag = MP3::Tag->new($mp3_filepath);
      add_song($sth, $panel_id, $mp3_filepath, $mp3tag);
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


#
# view
#

package Praati::View {
  Praati::Controller->import;
  Praati::Model->import;
  Praati::View::L10N->import;

  use CGI::Carp qw(cluck);
  use List::MoreUtils qw(uniq);
  use Scalar::Util qw(blessed);
  use Text::Abbrev;
  use URI::Escape;

  our $Lh;

  BEGIN {
    my @query_methods = qw(a
                           audio
                           div
                           embed
                           end_html
                           escapeHTML
                           form
                           h1
                           h2
                           li
                           meta
                           option
                           p
                           path_info
                           password_field
                           radio_group
                           Select
                           source
                           start_html
                           submit
                           table
                           td
                           textfield
                           th
                           Tr
                           ul);

    foreach my $method (@query_methods) {
      no strict 'refs';
      *$method = sub { query_method($method, @_); };
    }
  }

  sub init { Praati::View::L10N::init_praati_l10n(); }

  sub concat { join('' => @_); }

  sub e { escapeHTML(@_); }

  sub link_if_not_this_page {
    my ($target) = @_;

    my $page_descriptions = {
      login    => t('Login'),
      logout   => t('Logout'),
      main     => t('Main'),
      new_user => t('New user'),
      panels   => t('Panels'),
    };

    my $description = $page_descriptions->{ $target };
    confess("No page description found for $target") unless $description;

    "/$target" eq path_info()
      ? $description
      : a({ -href => link_to($target) },
          $description);
  }

  sub link_to {
    my ($target) = @_;
    my $path_depth = scalar(split(m|/|, path_info())) - 2;
    my $target_prefix = '../' x $path_depth;
    "${target_prefix}${target}";
  }

  sub make_form_id {
    my ($table, $id, $field) = @_;
    "${table}[${id}].${field}";
  }

  sub menu {
    my $user_role = get_session_user_role();

    my $pages_by_role = {
      admin     => [ qw(main          panels       logout) ],
      anonymous => [ qw(main new_user        login       ) ],
      critic    => [ qw(main          panels       logout) ],
    };

    my $pagelist = $pages_by_role->{ $user_role };
    confess("No pagelist found for $user_role") unless $pagelist;

    table(
      Tr(
        td([ map { link_if_not_this_page($_) } @$pagelist ])));
  }

  sub page { response(page => standard_page(@_)); }

  sub standard_page {
    my ($title, $content, %opts) = @_;

    confess('No title set for page') unless $title;

    my @start_html_opts = (
                            $opts{-start_html} ? @{ $opts{-start_html} } : (),
                            -title => "Praati - $title",
                          );

    start_html(@start_html_opts)
    . logged_as()
    . menu()
    . $content
    . end_html()
    . "\n";
  }

  sub maybe_error {
    my ($name, $errors, $fn) = @_;

    defined($errors->{ $name })
      ? $fn->(@{ $errors->{ $name } })
      : ();
  }

  #
  # forms
  #

  sub form_new_listening_session {
    my ($errors) = @_;

    my $default_session_name = localtime();;

    my %types = (
      asc      => t('Play songs from worst to best'),
      desc_asc => t('Play to the worst, then to the best from position:'),
    );

    my $song_position_error
      = maybe_error(turning_point_song_position => $errors,
                    sub { '(' . concat(@_) . ')'; })
          // '';

    my $type_choice
      = table(
          Tr([
               td(radio_group(listening_session_type => [ qw(asc) ],
                              'asc', '', \%types)),
               td(radio_group(listening_session_type => [ qw(desc_asc) ],
                              '', '', \%types)
                  . textfield('turning_point_song_position')
                  . $song_position_error)]));

    my $error_fn = sub { td({ -colspan => 2 }, join(' ' => @_)) };

    form({ -method => 'post' },
         table(
           Tr([
                maybe_error('*' => $errors, $error_fn),
                maybe_error(listening_session_name => $errors, $error_fn),
                td([ t('Listening session name:'),
                     textfield('listening_session_name',
                               $default_session_name) ]),

                maybe_error(listening_session_type => $errors, $error_fn),
                td([ t('Select session type:'), $type_choice ]),
                td({ -colspan => 2 },
                   [ submit('new_listening_session', t('Create')) ])])));
  }

  sub form_panel_ratings_by_user {
    my ($panel_id, $user_id) = @_;

    my $albums = records(q{ select * from albums_in_panels where panel_id = ?
                              order by album_year; },
                         $panel_id);

    Praati::Model::update_user_normalized_ratings($panel_id, $user_id);

    my @album_rating_tables
      = map { h1(e($_->{album_name}))
              . table_album_ratings_by_user($_, $panel_id, $user_id) }
          @$albums;

    form({ -method => 'post' },
         concat(@album_rating_tables));
  }

  #
  # pages
  #

  sub page_listening_event {
    my ($event_and_song) = @_;

    my $event_number         = $event_and_song->{listening_session_id};
    my $listening_session_id = $event_and_song->{listening_session_id};
    my $song_id              = $event_and_song->{song_id};

    my $title = song_title_for_listening_event($event_and_song,
                                               $event_number,
                                               $listening_session_id);

    my $rating_stats = table_song_rating_stats($listening_session_id,
                                               $song_id);

    my $ratings_for_song = table_ratings_for_song($listening_session_id,
                                                  $song_id);

    my $user_rating_correlations
      = table_user_rating_correlations($listening_session_id, $event_number);

    my $page = audio_player($song_id)
               . h1($title)
               . div({ -style => 'float: left;' }, $rating_stats    )
               . div({ -style => 'float: left;' }, $ratings_for_song)
               . $user_rating_correlations;

    query(q{ update listening_events
               set listening_event_shown = listening_event_shown + 1
                 where listening_event_id = ? },
          $event_and_song->{listening_event_id});

    page(t('Listening event for [_1]', $title),
         $page);
  }

  sub page_listening_session_overview {
    my ($listening_session) = @_;
    my $title = t('Listening session overview for "[_1]".',
                  e($listening_session->{listening_session_name}));

    my $content = p($title)
                  . h2( t('User rating counts') )
                  . table_user_rating_counts($listening_session)
                  . h2( t('Playback events') )
                  . table_listening_events($listening_session);

    page($title, $content);
  }

  sub page_login {
    my ($errors, $cookie) = @_;

    my $table_width = 2;
    my $error_wrapper = sub { td({ -colspan => $table_width },
                                 join(' ' => @_)); };

    my $tablerows = [
      maybe_error('*' => $errors, $error_wrapper),

      td([ t('email address:'), textfield('user_email')         ]),
      td([ t('password:'),      password_field('user_password') ]),

      td({ -colspan => $table_width },
         submit(submit_login => t('Login'))),
    ];

    my $login_refresh_seconds
      = int($Praati::Config::User_session_hours * 60 * 60 / 2);

    # refresh every $login_refresh_seconds to get a new session cookie
    # (wipes the form as a side effect)
    my $start_html_options = [
      -head => meta({ -http_equiv => 'refresh',
                      -content    => $login_refresh_seconds }),
    ];

    my $page
      = form({ -method => 'post' },
          table(
            Tr($tablerows)));

    response(cookie => $cookie,
             page   => standard_page(t('Login'),
                                     $page,
                                     -start_html => $start_html_options));
  }

  sub page_logged_out {
    my ($cookie) = @_;
    response(cookie => $cookie,
             page   => standard_page(t('Logged out'),
                                     p( t('You are now logged out.') )));
  }

  sub page_logout_error {
    my ($errors) = @_;
    warn("Could not log out: " . $errors->{'*'});
    page(t('Logout error'),
         p( t('Could not log out for some reason.') ));
  }

  sub page_main {
    page(t('Main'),
         p( t('The main page.') ));
  }

  sub page_new_user {
    my ($errors) = @_;

    my $table_width = 2;

    my $error_wrapper = sub { td({ -colspan => $table_width },
                                 join(' ' => @_)); };

    my $tablerows = [
      maybe_error('*' => $errors, $error_wrapper),

      maybe_error(user_email => $errors, $error_wrapper),
      td([ t('email address:'),  textfield('user_email')               ]),

      maybe_error(user_name => $errors, $error_wrapper),
      td([ t('name:'),           textfield('user_name')                ]),

      maybe_error(user_password => $errors, $error_wrapper),
      td([ t('password:'),       password_field('user_password')       ]),

      maybe_error(user_password_again => $errors, $error_wrapper),
      td([ t('password again:'), password_field('user_password_again') ]),

      td({ -colspan => $table_width },
         submit(submit_new_user => t('Create new user'))),
    ];

    # XXX repetition
    my $form
      = form({ -method => 'post' },
             table(
               Tr($tablerows)));

    page( t('Create new user'), $form);
  }

  sub page_new_listening_session {
    my ($errors, $panel) = @_;

    my $content
      = p(t('Create a new listening session for panel "[_1]":',
            $panel->{panel_name}))
        . form_new_listening_session($errors);

    page(t('New listening session'),
         $content);
  }

  sub page_no_such_page {
    standard_page(t('No such page'),
                  p( t('No such page.') ));
  }

  sub page_not_logged_in {
    page(t('Not logged in'),
         p( t('You are not logged in.') ));
  }

  sub page_panel_ratings_by_user {
    my ($errors, $panel) = @_;

    my $panel_ratings_form = form_panel_ratings_by_user($panel->{panel_id},
                                                        session_user());

    my $content
      = p(t('This panel is "[_1]".', e($panel->{panel_name}))
          . (maybe_error('*', $errors, sub { p(concat(@_)); }) // '')
          . $panel_ratings_form);

    page(t('Rate songs for "[_1]"', e($panel->{panel_name})),
         $content);
  }

  sub page_panels {
    my $panels = records(q{ select * from panels order by panel_name; });

    my @panel_action_items = map { panel_action_list_item($_) } @$panels;
    page(t('Available panels'),
         p( t('Available panels are:') ) . ul( li(\@panel_action_items) ));
  }

  sub page_unauthorized_access {
    standard_page(t('Unauthorized access'),
                  p( t('Access unauthorized.') ));
  }

  #
  # tables
  #

  sub table_album_ratings_by_user {
    my ($album, $panel_id, $user_id) = @_;

    my $songs = records(q{select * from songinfos

                            cross join users
                            left outer join song_ratings_with_normalized_values
                              using (panel_id, song_id, user_id)
                            where album_id = ?
                              and panel_id = ?
                              and  user_id = ?
                            order by track_number; },
                        $album->{album_id},
                        $panel_id,
                        $user_id);

    my @tablerows = map { tablerow_edit_song_rating_by_user($_) } @$songs;

    concat( table( Tr(\@tablerows) ) );
  }

  sub table_listening_events {
    my ($listening_session) = @_;

    my $listening_events
      = records(q{ select * from listening_events
                     join ls_song_positions using (listening_session_id,
                                                   song_position)
                   where listening_session_id = ?
                   order by listening_event_number; },
                $listening_session->{listening_session_id});

    my $first_event_done = 0;

    my @listening_events_html;

    foreach my $event (@$listening_events) {
      my $show_link;
      if (!$first_event_done) {
        $show_link        = 1;
        $first_event_done = 1;
      }
      else {
        $show_link = $event->{listening_event_shown} > 0;
      }

      # XXX should you use the listening_event_id here?
      my $link = link_to(sprintf('listening_events?listening_event_id=%d',
                                 uri_escape( $event->{listening_event_id} )));

      my $title = t('Play song at position [_1]', $event->{song_position});
      my $html = $show_link
                   ? a({ -href => $link }, $title)
                   : $title;

      push @listening_events_html, $html;
    }

    table(
      Tr([ map { td($_) } @listening_events_html ]));
  }

  sub table_ratings_for_song {
    my ($listening_session_id, $song_id) = @_;

    my $song_ratings
      = records(q{ select user_name,
                          song_rating_value_value,
                          song_rating_normalized_value_value,
                          song_rating_comment
                     from ls_song_ratings_with_set_values_and_sessions
                       join users using (user_id)
                   where listening_session_id = ?
                     and song_id = ?
                   order by song_rating_normalized_value_value desc,
                            song_rating_value_value desc; },
                $listening_session_id,
                $song_id);

    table(
      Tr([ map { tablerow_song_rating_by_user($_) }
             @$song_ratings ]));

  }

  sub tablerow_edit_song_rating_by_user {
    my ($song_with_rating) = @_;

    my ($rating_form_id, $comment_form_id)
      = map { make_form_id(songs => $song_with_rating->{song_id}, $_) }
          qw(rating_value rating_comment);

    my $rating_choice
      = song_rating_choice($rating_form_id,
                           $song_with_rating->{song_rating_value_value});
    my $comment
      = textfield($comment_form_id,
                  $song_with_rating->{song_rating_comment} // '');

    my $normalized_value
      = $song_with_rating->{song_rating_normalized_value_value};

    my $color_for_normalized_value = color_for_rating_value($normalized_value);
    my $normalized_value_string
      = $normalized_value ? sprintf('%.1f', $normalized_value)
          : '&mdash;';

    my $song_playback_link
      = a({ -href => link_to_song_playback($song_with_rating->{song_id}) },
          t('play'));

    td([ e($song_with_rating->{artist_name}),
         div({ -style => 'padding-left: 0.7em; padding-right: 0.7em;' },
             e($song_with_rating->{song_name})),
         $song_playback_link,
         $rating_choice,
         div({ -style => "background-color: $color_for_normalized_value; "
                         . "padding: 0.3em;" },
             $normalized_value_string),
         $comment,
         submit(send_ratings => t('Save all')) ]);
  }

  sub tablerow_song_rating_by_user {
    my ($song_rating) = @_;

    my $normalized_value = $song_rating->{song_rating_normalized_value_value};
    my $color_for_normalized_value = color_for_rating_value($normalized_value);

    my $normalized_rating_html
      = div({ -class => 'song_rating_normalized',
              -style => "background-color: $color_for_normalized_value;" },
            sprintf('%.1f',
                    $song_rating->{song_rating_normalized_value_value}));

    my $rating_html
      = div(sprintf('(%s)', $song_rating->{song_rating_value_value}));

    my $user_name_html = div({ -class => 'user_name' },
                             $song_rating->{user_name});

    my $song_rating_comment_html
      = div({ -class => 'comment' },
            $song_rating->{song_rating_comment});

    td($normalized_rating_html,
       $rating_html)
    . td($user_name_html,
         $song_rating_comment_html);
  }

  sub table_song_rating_stats {
    my ($listening_session_id, $song_id) = @_;

    my $stats
      = one_record(q{ select * from ls_song_rating_results
                        where listening_session_id = ?
                          and song_id = ?; },
                   $listening_session_id,
                   $song_id);

    my $color_for_normalized_value
      = color_for_rating_value($stats->{song_normalized_rating_value_avg});

    table(
      Tr([ td({ -class => 'song_normalized_rating_value_avg',
                -style => "background-color: $color_for_normalized_value;" },
              sprintf('%.3f', $stats->{song_normalized_rating_value_avg})),

           td(sprintf('(%.3f)', $stats->{song_rating_value_avg})),

           td(sprintf('norm. &sigma; = %.3f',
                      $stats->{song_normalized_rating_value_stdev})),

           td(sprintf('(&sigma; = %.3f)',
                      $stats->{song_rating_value_stdev})) ]));
  }

  sub table_user_rating_correlations {
    my ($listening_session_id, $event_number) = @_;
    my $correlations
      = records(q{ select * from user_rating_correlations_with_users
                     where listening_session_id = ?
                       and up_to_event_number = ?; },
                $listening_session_id,
                $event_number);

    my @userlist = get_userlist_for_correlations($correlations);
    my %username_short_forms = make_username_short_forms(@userlist);

    my %user_rownumber = map { $userlist[$_] => ($_ + 1) } (0 .. $#userlist);

    my @table;

    foreach (0 .. $#userlist) {
      $table[ 0      ][ $_ + 1 ] = $username_short_forms{ $userlist[$_] };
      $table[ $_ + 1 ][ 0      ] = $username_short_forms{ $userlist[$_] };
    }

    foreach my $correlation (@$correlations) {
      my $i = $user_rownumber{ $correlation->{ user_a_user_name } };
      my $j = $user_rownumber{ $correlation->{ user_b_user_name } };

      my $correlation_color
        = color_for_an_interval($correlation->{normalized_rating_correlation},
                                -1.0,
                                1.0);

      $table[ $i ][ $j ]
        = div({ -style => "background-color: $correlation_color;" },
              sprintf('%.2f', $correlation->{normalized_rating_correlation}));
    }

    table(Tr([ map {
                 my $i = $_;
                 td([ map { $table[$i][$_] } (0 .. scalar(@userlist)) ])
               } (0 .. scalar(@userlist))]));
  }

  sub table_user_rating_counts {
    my ($listening_session) = @_;

    my $user_rating_counts
      = rows(q{ select user_name, count(ls_song_rating_id) as rating_count
                  from ls_song_ratings_with_set_values
                    join users using (user_id)
                  where listening_session_id = ?
                  group by user_name
                  order by rating_count desc, user_name; },
             $listening_session->{listening_session_id});

    table(
      Tr([ th([ t('user'), t('rating count') ]),
           map { td($_) } @$user_rating_counts]));
  }

  #
  # other
  #

  sub audio_player {
    my ($song_id) = @_;
    my $playback_link = link_to_song_playback($song_id);

    div(
      audio({ -autoplay => undef, -controls => undef },
            source({ -src  => $playback_link,
                     -type => 'audio/mpeg' }),
            embed({ -src => $playback_link }))
      . sprintf('(%s)', a({ -href => link_to_song_playback($song_id) },
                          'mp3')));
  }

  sub color_for_an_interval {
    my ($value, $min, $max) = @_;

    confess('minimum and maximum are the same') if $min == $max;

    if ($value > $max) {
      cluck('Got a value that is higher than maximum, setting to maximum.');
      $value = $max;
    }

    if ($value < $min) {
      cluck('Got a value that is lower than minimum, setting to minimum.');
      $value = $min;
    }

    my $green = int(255.0 * (($value - $min) / ($max - $min)));

    my $red  = int(255.0 - $green);
    my $blue = 96;

    sprintf('#%02x%02x%02x', $red, $green, $blue);
  }

  sub color_for_rating_value {
    my ($rating_value) = @_;
    return '#808080' unless defined $rating_value;

    color_for_an_interval($rating_value,
                          0,
                          Praati::Constants::MAX_SONG_RATING);
  }

  sub get_userlist_for_correlations {
    my ($correlations) = @_;
    sort(uniq(map { $_->{user_a_user_name}, $_->{user_b_user_name} }
                @$correlations));
  }

  sub link_to_song_playback {
    my ($song_id) = @_;
    link_to(sprintf('song/play?song_id=%d', $song_id));
  }

  sub link_uri_if_event_exists {
    my ($event_number, $listening_session_id) = @_;

    my $events = records(q{ select * from listening_events
                              where listening_event_number = ?
                                and listening_session_id = ?; },
                         $event_number,
                         $listening_session_id);

    return if scalar(@$events) == 0;

    my $event = $events->[0];

    link_to(sprintf('listening_events?listening_event_id=%d',
                    uri_escape( $event->{listening_event_id} )));
  }

  sub listening_session_link {
    my ($listening_session) = @_;
    my $url_format = 'listening_sessions/overview?listening_session_id=%d';
    my $id         = uri_escape( $listening_session->{listening_session_id} );

    a({ -href => link_to(sprintf($url_format, $id)) },
      $listening_session->{listening_session_name});
  }

  sub logged_as {
    my $user_id = session_user();

    return '' unless $user_id;

    my $user = one_record(q{ select * from users where user_id = ?; },
                          $user_id);
    $user
      ? t('Logged in as "[_1]" ([_2])',
          e($user->{user_name}),
          e($user->{user_role}))
      : '';
  }

  sub make_username_short_forms {
    my (@userlist) = @_;
    my %user_abbreviations = abbrev(@userlist);
    my %short_forms;

    foreach my $username (@userlist) {
      foreach (1 .. length($username)) {
        my $possible_abbreviation_for_username = substr($username, 0, $_);
        if ($user_abbreviations{ $possible_abbreviation_for_username }) {
          $short_forms{ $username } = $possible_abbreviation_for_username;
          last;
        }
      }
    }

    %short_forms;
  }

  sub panel_action_list_item {
    my ($panel) = @_;
    my $user_role = get_session_user_role();

    my $panel_id_escaped = uri_escape($panel->{panel_id});

    my $rate_panel_uri = link_to(sprintf('panels/rate?panel_id=%d',
                                         $panel_id_escaped));

    $user_role eq 'admin'
      ? do {
          my $listening_session_uri
            = link_to(sprintf('listening_sessions/new?panel_id=%d',
                              $panel_id_escaped));
          my $all_results_uri
            = link_to(sprintf('panels/results?panel_id=%d',
                              $panel_id_escaped));

          my $listening_sessions
            = records(q{ select * from listening_sessions where panel_id = ?
                          order by listening_session_name; },
                      $panel->{panel_id});

          sprintf('%s [%s][%s]',
                  e($panel->{panel_name}),
                  a({ -href => $rate_panel_uri }, t('rate')),
                  a({ -href => $listening_session_uri },
                    t('create a new listening session')))
          . ul(
              li([ map { listening_session_link($_) }
                     @$listening_sessions ]));
        }
      :

    $user_role eq 'critic'
      ? a({ -href => $rate_panel_uri }, e($panel->{panel_name}))
      :

    confess('Asking panel_action_list_item() for an unsupported role');
  }

  sub play_song {
    my ($song) = @_;

    response(filepath => $song->{song_filepath},
             type     => 'audio/mpeg');
  }

  sub song_rating_choice {
    my ($rating_form_id, $song_rating_value_value) = @_;
    my $value = defined($song_rating_value_value)
                 ? sprintf('%.1f', $song_rating_value_value)
                 : Praati::Constants::NO_SONG_RATING_MARKER;

    Select({ name => $rating_form_id },
           map {
             sprintf('<option%s value="%s">%s</option>',
                     (($value eq $_) ? q{ selected="selected"} : ''),
                     $_,
                     $_)
           } song_rating_values());
  }

  sub song_rating_values {
    my $step_size =  0.5;

    (
      Praati::Constants::NO_SONG_RATING_MARKER,
      reverse(
        map { sprintf('%.1f', $_ * $step_size) }
          0 .. (Praati::Constants::MAX_SONG_RATING / $step_size))
    );
  }

  sub song_title_for_listening_event {
    my ($event_and_song, $event_number, $listening_session_id) = @_;

    my $previous_link = link_uri_if_event_exists($event_number - 1,
                                                 $listening_session_id);
    my $next_link     = link_uri_if_event_exists($event_number + 1,
                                                 $listening_session_id);

    my $previous_link_html
      = $previous_link
          ? a({ -href => $previous_link, -style => 'padding-right: 1em;' }, '<')
          : '';

    my $next_link_html
      = $next_link
          ? a({ -href => $next_link, -style => 'padding-left: 1em;' }, '>')
          : '';

    sprintf('%s%d. %s: %s%s',
            $previous_link_html,
            e($event_and_song->{song_position}),
            e($event_and_song->{artist_name}),
            e($event_and_song->{song_name}),
            $next_link_html);
  }
}


#
# controller
#

package Praati::Controller {
  Praati::Model->import;
  Praati::View::L10N->import;

  use BSD::arc4random qw(arc4random_bytes);
  use CGI qw(-any);
  use CGI::Carp;
  use List::MoreUtils qw(any);
  use Scalar::Util qw(blessed);

  if ($ENV{PRAATI_DEBUG}) {
    $CGI::Pretty::INDENT = ' ' x 2;
  }

  our ($Q, $Session_user);

  sub main {
    $ENV{PRAATI_DEBUG}
      ? debugging_wrapper(\&handle_query)
      : handle_query();
  }

  sub handle_query {
    $Q = CGI->new;

    eval {
      Praati::Model::init();
      Praati::View::init();

      my $user_session_key = $Q->cookie('user_session_key');
      $Session_user = Praati::Model::find_session_user($user_session_key);

      my $response = url_dispatch( $Q->path_info );
      $response->printout($Q);
    };
    my $error = $@;

    Praati::Model::close_db_connection();

    if ($error) {
      confess($error);
    }
  }

  sub debugging_wrapper {
    my ($fn) = @_;

    warn 'Debugging has been turned on, stacktraces end up to the browser';

    eval { $fn->() };
    my $err = $@;
    if ($err) {
      my $q = CGI->new;
      print $q->header(),
            $q->pre($err);
    }
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

  sub no_such_page_controller {
    response(page   => Praati::View::page_no_such_page(),
             status => 404);
  }

  sub panel_ratings_by_user_controller {
    my $panel = one_record_or_no_such_page(q{ select * from panels
                                                where panel_id = ?; },
                                           $Q->url_param('panel_id'));

    my %p = $Q->Vars;
    my $errors = {};

    if ($p{send_ratings}) {
      my $song_ratings = parse_form_ids_for_table(songs => \%p);
      while (my ($song_id, $rating) = each %$song_ratings) {
        if ($rating->{ rating_value }
              eq Praati::Constants::NO_SONG_RATING_MARKER) {
          $song_ratings->{ $song_id }{ rating_value } = undef;
        }
      }

      eval {
        Praati::Model::update_user_ratings($panel->{panel_id},
                                           session_user(),
                                           $song_ratings);
      };
      if ($@) {
        add_unknown_ui_error($errors, '*', $@);
      }
    }

    Praati::View::page_panel_ratings_by_user($errors, $panel);
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

    print $content;
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
