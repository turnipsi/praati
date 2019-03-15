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

package Praati::View {
  use Exporter qw(import);
  BEGIN {
    our @EXPORT_OK = qw(count_unrated_songs get_normalized_value_info);
  }

  use Praati;
  use Praati::Controller qw(get_session_user_role query_method response
                              session_user);
  use Praati::Model qw(one_record one_value query records rows);
  use Praati::View::L10N qw(t);

  use CGI (-utf8);
  use CGI::Carp qw(cluck);
  use List::MoreUtils qw(uniq);
  use Scalar::Util qw(blessed);
  use Text::Abbrev;
  use URI::Escape;

  our $Lh;

  BEGIN {
    my @html_funcs = qw(audio
                        form
                        source);
    my @query_methods = qw(a
                           div
                           embed
                           end_html
                           escapeHTML
                           h1
                           h2
                           hidden
                           li
                           meta
                           option
                           p
                           path_info
                           password_field
                           radio_group
                           Select
                           span
                           start_html
                           submit
                           table
                           td
                           textfield
                           th
                           Tr
                           ul);

    foreach my $tag (@html_funcs) {
      no strict 'refs';
      # XXX this uses a private interface in CGI.pm...
      # XXX should probably migrate to HTML::Tiny some day...
      *$tag = sub { CGI::_tag_func($tag, @_); };
    }

    foreach my $method (@query_methods) {
      no strict 'refs';
      *$method = sub { query_method($method, @_); };
    }
  }

  sub init { Praati::View::L10N::init_praati_l10n(); }

  sub concat { join('' => @_); }

  sub css {
    <<'EOF';
/*
 * styles for editing ratings
 */

.normalized_rating_in_edit_song_rating {
  padding: 0.3em;
}

.song_name_in_edit_song_rating {
  padding-left:  0.7em;
  padding-right: 0.7em;
}

.playback_song {
  background-color: lightgreen;
}

/*
 * listening event styles
 */

/* general */

.audio_player_div {
  position:	fixed;
  right:	10px;
  top:		10px;
}

#ratings_info {
  display: flex;
}

.rating_stats {
  float:         left;
  padding-right: 1em;
}

.rating_stats td {
  text-align: center;
}

.song_normalized_rating_value_avg {
  border-style: solid;
  border-width: 0.1em;
  font-size:    3em;
}

.song_rating_value_avg {
  font-size: 1.5em;
}

/* song ratings by users */

div.ratings_for_song {
  float:         left;
  padding-right: 1em;
  min-width:     40em;
}

table.ratings_for_song {
  border-collapse: collapse;
  width:           100%;
}

.user_song_rating {
  border-style: solid;

  margin:  0;
  padding: 0;
}

.user_song_rating_value_and_name {
  margin: 0;
  padding-left:  0.1em;
  padding-right: 0.1em;
}

.song_rating_normalized_value_value {
  font-size: 2.2em;
}

.song_rating_value_value {
  font-size:  1.5em;
  text-align: center;
}

.user_name {
  font-size: 1.2em;
  float: right;
}

.comment {
  margin:  0;

  padding-bottom: 0.2em;
  padding-left:   1em;
  padding-right:  1em;
  padding-top:    0.2em;
}

#album_chart_table td {
  border-style: solid;
  border-width: 0.1em;
  padding:      0.2em;
}

#album_chart_table {
  border-collapse: collapse;
}

#user_rating_correlations_table {
  border-collapse: collapse;
}

.user_rating_correlations td {
  border-style: solid;
  border-width: 0.1em;
  padding:      0.2em;
  text-align:   center;
}

.no_correlation { background-color: #808080; }
EOF
  }

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
    my ($title, $content, @opts) = @_;

    confess('No title set for page') unless $title;

    my @start_html_opts = (-style => { -code => css(), },
                           -title => "Praati - $title",
                           @opts);

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
                              order by album_year, album_name; },
                         $panel_id);

    my @album_rating_tables
      = map { h1(e($_->{album_name}))
              . table_album_ratings_by_user($_, $panel_id, $user_id) }
          @$albums;

    my $audio_player = audio_player(undef);

    my $unrated_song_count = count_unrated_songs($panel_id, $user_id);

    $audio_player
    . p(t('Unrated song count:')
        . ' '
        . span({ -id => 'unrated_song_count' }, $unrated_song_count)
        . '.')
    . form({ -id => 'song ratings', -method => 'post', },
           concat(@album_rating_tables)
           . hidden('panel_id', $panel_id));
  }

  #
  # pages
  #

  sub page_listening_event {
    my ($event_and_song) = @_;

    my $event_number         = $event_and_song->{listening_event_number};
    my $listening_session_id = $event_and_song->{listening_session_id};
    my $song_id              = $event_and_song->{song_id};

    my $title = song_title_for_listening_event($event_and_song,
                                               $listening_session_id);

    my $rating_stats = table_song_rating_stats($listening_session_id,
					       $event_number,
                                               $song_id);

    my $ratings_for_song = table_ratings_for_song($listening_session_id,
                                                  $song_id);

    my $user_rating_correlations
      = table_user_rating_correlations($listening_session_id, $event_number);

    my $album_chart
      = table_album_chart($listening_session_id, $event_number);

    my $header_title = t('Listening event for [_1]',
			 $event_and_song->{song_name});
    my $js = Praati::View::JS::panel_listening_event_js();
    my @start_html_opts = (-script => $js,
			   -style  => { -code => css(), },
                           -title  => "Praati - $header_title");

    my $stats_div = div({ -id => 'cumulative_panel_statistics' },
			$user_rating_correlations
			. $album_chart);

    query(q{ update listening_events
               set listening_event_shown = listening_event_shown + 1
                 where listening_event_id = ? },
          $event_and_song->{listening_event_id});

    my $page = start_html(@start_html_opts)
               . audio_player($song_id)
               . h1($title)
               . div({ -id => 'ratings_info' },
                     $rating_stats
                     . $ratings_for_song
                     . $stats_div)
               . end_html()
               . "\n";

    response(page => $page);
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
    my @start_html_options = (
      -head => meta({ -http_equiv => 'refresh',
                      -content    => $login_refresh_seconds }),
    );

    my $page
      = form({ -method => 'post' },
          table(
            Tr($tablerows)));

    response(cookie => $cookie,
             page   => standard_page(t('Login'), $page, @start_html_options));
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
    my ($errors, $panel, $user_id) = @_;
    my $panel_id = $panel->{panel_id};

    my $panel_ratings_form = form_panel_ratings_by_user($panel_id, $user_id);

    my $content
      = p(t('This panel is "[_1]".', e($panel->{panel_name}))
          . (maybe_error('*', $errors, sub { p(concat(@_)); }) // '')
          . $panel_ratings_form);

    my $js = Praati::View::JS::panel_ratings_by_user_js($panel_id, $user_id);
    page(t('Rate songs for "[_1]"', e($panel->{panel_name})),
         $content,
         -script => $js);
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

    my $show_artist_name = !is_panel_single_artist($panel_id);
    my @tablerows = map {
      tablerow_edit_song_rating_by_user($_, $show_artist_name)
    } @$songs;

    concat( table(@tablerows) );
  }

  sub is_panel_single_artist {
    # XXX treat all panels as single artist panels for now... remove later
    return 1;

    my ($panel_id) = @_;
    my $artist_count
      = one_value(q{ select count(distinct artist_id) from songs_in_panels
                       join songs using (song_id)
                     where panel_id = ?; },
                  $panel_id);

    ($artist_count == 1);
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

    div({ -class => 'ratings_for_song' },
        table({ -class => 'ratings_for_song' },
              Tr([ map { tablerow_song_rating_by_user($_) }
                     @$song_ratings ])));
  }

  sub tablerow_edit_song_rating_by_user {
    my ($song_with_rating, $show_artist_name) = @_;

    my $song_id = $song_with_rating->{song_id};
    my ($song_form_id, $playback_link_id, $rating_form_id, $comment_form_id,
      $normalized_rating_form_id)
        = map { make_form_id(songs => $song_id, $_) }
            qw(song playback_link rating_value rating_comment
               normalized_rating);

    my $rating_choice
      = song_rating_choice($rating_form_id,
                           $song_with_rating->{song_rating_value_value});
    my $comment
      = textfield(-name      => $comment_form_id,
                  -size      => 80,
                  -maxlength => 900,
                  -value     => $song_with_rating->{song_rating_comment} // '');

    my $normalized_value
      = $song_with_rating->{song_rating_normalized_value_value};
    my $nv_info = get_normalized_value_info($normalized_value);

    my $song_playback_link
      = a({ -class => 'playback_link',
            -href  => link_to_song_playback($song_id),
            -id    => $playback_link_id },
          t('play'));

    Tr({ -class => 'not_playback_song', -id => $song_form_id, },
       td([ $show_artist_name ? e($song_with_rating->{artist_name}) : (),
            div({ -class => 'song_name_in_edit_song_rating' },
                e($song_with_rating->{song_name})),
            $song_playback_link,
            $rating_choice,
            div({ -class => 'normalized_rating_in_edit_song_rating',
                  -id    => $normalized_rating_form_id,
                  -style => $nv_info->{color_style} },
                $nv_info->{html_string}),
            $comment,
            submit(send_ratings => t('Save all')) ]));
  }

  sub get_normalized_value_info {
    my ($normalized_value) = @_;
    my $color_for_normalized_value = color_for_rating_value($normalized_value,
                                                            1.0);
    {
      color_style => "background-color: $color_for_normalized_value;",
      html_string => $normalized_value
                       ? sprintf('%.1f', $normalized_value)
                       : '&mdash;',
      value       => $normalized_value, # may be undefined, which is good
    };
  }

  sub tablerow_song_rating_by_user {
    my ($song_rating) = @_;

    my $normalized_value = $song_rating->{song_rating_normalized_value_value};
    my $color_for_normalized_value = color_for_rating_value($normalized_value,
                                                            1.0);

    my $light_color_for_normalized_value
      = color_for_rating_value($normalized_value, 0.5);

    my $normalized_rating_html
      = span({ -class => 'song_rating_normalized_value_value' },
             sprintf('%.1f',
                     $song_rating->{song_rating_normalized_value_value}));

    my $rating_html
      = span({ -class => 'song_rating_value_value' },
             sprintf('(%.1f)', $song_rating->{song_rating_value_value}));

    my $user_name_html = span({ -class => 'user_name' },
                              e($song_rating->{user_name}));

    my $comment_div
      = $song_rating->{song_rating_comment} =~ /\S+/
          ? div({ -class => 'comment',
                  -style =>
                    "background-color: $light_color_for_normalized_value;" },
                e($song_rating->{song_rating_comment}))
          : '';

    td({ -class => 'user_song_rating' },
       div({ -class => 'user_song_rating_value_and_name',
             -style => "background-color: $color_for_normalized_value;" },
           $normalized_rating_html,
           $rating_html,
           $user_name_html),
       $comment_div);
  }

  sub table_song_rating_stats {
    my ($listening_session_id, $event_number, $song_id) = @_;

    my $stats
      = one_record(q{ select * from ls_song_rating_results
                        where listening_session_id = ?
                          and              song_id = ?; },
                   $listening_session_id,
                   $song_id);

    my $color_for_normalized_value
      = color_for_rating_value($stats->{song_normalized_rating_value_avg},
                               1.0);

    my $previous_link = link_uri_if_event_exists($event_number - 1,
                                                 $listening_session_id);
    my $next_link     = link_uri_if_event_exists($event_number + 1,
                                                 $listening_session_id);

    my $previous_link_html
      = $previous_link
          ? a({ -id    => 'previous_song_link',
                -href  => $previous_link },
              e('<-- '))
          : '';

    my $next_link_html
      = $next_link
          ? a({ -id    => 'next_song_link',
                -href  => $next_link },
              e(' -->'))
          : '';

    table({ -class => 'rating_stats' },
          Tr([ td({ -class => 'song_normalized_rating_value_avg',
                    -style => "background-color: $color_for_normalized_value;" },
                  sprintf('%.2f', $stats->{song_normalized_rating_value_avg})),

               td({ -class => 'song_rating_value_avg' },
                  sprintf('(%.2f)', $stats->{song_rating_value_avg})),

               td(sprintf('norm. &sigma; = %.2f',
                          $stats->{song_normalized_rating_value_stdev})),

               td(sprintf('(&sigma; = %.2f)',
                          $stats->{song_rating_value_stdev})),

	       td(sprintf('%s%s', $previous_link_html, $next_link_html)) ]));
  }

  sub table_user_rating_correlations {
    my ($listening_session_id, $event_number) = @_;
    my $correlations
      = records(q{ select * from user_rating_correlations_with_users
                     where listening_session_id = ?
                       and   up_to_event_number = ?; },
                $listening_session_id,
                $event_number);

    my @userlist = get_userlist_for_correlations($correlations);
    my %username_short_forms = make_username_short_forms(@userlist);

    my %user_rownumber = map { $userlist[$_] => ($_ + 1) } (0 .. $#userlist);

    my @table;

    foreach (0 .. $#userlist) {
      $table[ 0      ][ $_ + 1 ] = td($username_short_forms{ $userlist[$_] });
      $table[ $_ + 1 ][ 0      ] = td($username_short_forms{ $userlist[$_] });
    }

    foreach my $correlation (@$correlations) {
      my $i = $user_rownumber{ $correlation->{ user_a_user_name } };
      my $j = $user_rownumber{ $correlation->{ user_b_user_name } };

      my $correlation_color
        = color_for_an_interval($correlation->{normalized_rating_correlation},
                                -1.0,
                                1.0,
                                1.0);

      $table[ $i ][ $j ]
        = td({ -style => "background-color: $correlation_color;" },
             sprintf('%.2f', $correlation->{normalized_rating_correlation}));
    }

    my $empty_cell = td({ -class => 'no_correlation' },
                        '&mdash;');

    div({ -class => 'user_rating_correlations' },
        a({ -href => '#', -id => 'user_rating_correlations_toggle' },
          t('Rating correlations')),
	table({ -id => 'user_rating_correlations_table' },
	      Tr([ map {
		     my $i = $_;
		     concat(map { $table[$i][$_] // $empty_cell }
			      (0 .. scalar(@userlist)));
		   } (0 .. scalar(@userlist))])));
  }

  sub table_album_chart {
    my ($listening_session_id, $event_number) = @_;

    my $user_rating_counts
      = records(q{ select album_name, album_year,
                     avg(song_normalized_rating_value_avg) as album_rating
                       from listening_events_up_to_event_number
                         join ls_song_positions
                           using (listening_session_id, song_position)
                         join ls_song_rating_results
                           using (listening_session_id, song_id)
                         join songs_in_albums using (song_id)
                         join albums using (album_id)
		   where listening_session_id = ?
                     and up_to_event_number = ?
		   group by album_id
                   order by album_rating desc, album_year, album_name; },
	     $listening_session_id,
	     $event_number);

    div({ -class => 'album_chart' },
        a({ -href => '#', -id => 'album_chart_toggle' },
          t('Album chart')),
        table({ -id => 'album_chart_table' },
              map {
                my $rating_color
		  = color_for_rating_value($_->{album_rating}, 1.0);
                Tr({ -style => "background-color: $rating_color;" },
                   td([ e($_->{album_year}),
			e($_->{album_name}),
			sprintf('%.2f', $_->{album_rating}) ]));
              } @$user_rating_counts));
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
    my $playback_link = $song_id ? link_to_song_playback($song_id) : undef;

    my @audio_opts  = $song_id ? (-autoplay => undef)     : ();
    my @source_opts = $song_id ? (-src => $playback_link) : ();

    # XXX if !$song_id, this should only show up if javascript is turned on
    div({ -class => 'audio_player_div' },
        audio({ @audio_opts, -controls => undef, -id => 'audio_player'},
              source({ @source_opts,
                       -id   => 'audio_player_source',
                       -type => 'audio/mpeg' })));

    # XXX I'd like to provide a direct link, but maybe not now...
    #   div({ -style => 'text-align: right;' },
    #       sprintf('(%s)', a({ -href => $playback_link },
    #                         'mp3'))));
  }

  sub color_for_an_interval {
    my ($value, $min, $max, $tint) = @_;

    confess('minimum and maximum are the same') if $min == $max;

    if ($value > $max) {
      cluck('Got a value that is higher than maximum, setting to maximum.');
      $value = $max;
    }

    if ($value < $min) {
      cluck('Got a value that is lower than minimum, setting to minimum.');
      $value = $min;
    }

    my $green = 255.0 * (($value - $min) / ($max - $min));

    my $red  = 255.0 - $green;
    my $blue = 96.0;

    ($red, $green, $blue) = map { 255.0 - $tint * (255.0 - $_) }
                              ($red, $green, $blue);

    sprintf('#%02x%02x%02x', int($red), int($green), int($blue));
  }

  sub color_for_rating_value {
    my ($rating_value, $tint) = @_;
    return '#808080' unless defined $rating_value;

    color_for_an_interval($rating_value,
                          0,
                          Praati::Constants::MAX_SONG_RATING,
                          $tint);
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
                                and   listening_session_id = ?; },
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
    my ($event_and_song, $listening_session_id) = @_;

    my $panel_id
      = one_value(q{ select panel_id from listening_sessions where
                       listening_session_id = ?; },
                  $listening_session_id);
    my $show_artist_name = !is_panel_single_artist($panel_id);

    sprintf('%d. %s %s',
            e($event_and_song->{song_position}),
            ($show_artist_name
               ? e($event_and_song->{artist_name}).':'
               : ''),
            e($event_and_song->{song_name}));
  }

  sub count_unrated_songs {
    # XXX a view for this kind of query might be nice?
    my ($panel_id, $user_id) = @_;

    one_value(q{ select count(song_id)
                   from songs_in_panels
                     cross join users
                     left outer join song_ratings_with_normalized_values
                       using (panel_id, song_id, user_id)
                     where song_rating_normalized_value_value is null
                       and panel_id = ?
                       and user_id  = ?; },
              $panel_id,
              $user_id);
  }
}

package Praati::View::JS {
  use JSON::XS;
  use Praati::Controller qw(response);
  use Praati::Model qw(columns one_value rows);
  use Praati::View qw(count_unrated_songs get_normalized_value_info);

  sub get_normalized_ratings_by_song_id {
    my ($panel_id, $user_id) = @_;

    my $normalized_ratings
      = rows(q{ select song_id, song_rating_normalized_value_value
                  from songs_in_panels
                    cross join users
                    left outer join song_ratings_with_normalized_values
                       using (panel_id, song_id, user_id)
                    where panel_id = ?
                      and user_id  = ?; },
                 $panel_id,
                 $user_id);

    my %normalized_ratings_by_song_id
      = map {
          my ($song_id, $value) = @$_;
          $song_id => get_normalized_value_info($value);
        } @$normalized_ratings;

    \%normalized_ratings_by_song_id;
  }

  sub panel_ratings_json {
    my ($errors, $panel, $user_id) = @_;

    my $normalized_ratings_by_song_id
      = get_normalized_ratings_by_song_id($panel->{panel_id}, $user_id);

    my $unrated_song_count = count_unrated_songs($panel->{panel_id}, $user_id);
    my $response_struct = {
      errors             => [ map { @$_ } values %$errors ],
      normalized_ratings => $normalized_ratings_by_song_id,
      unrated_song_count => $unrated_song_count,
    };

    my $json = encode_json($response_struct);
    response(page => $json, type => 'application/json');
  }

  sub make_playlist {
    my ($panel_id) = @_;
    columns(q{ select song_id from songinfos
                 where panel_id = ?
               order by album_year, album_name, track_number; },
            $panel_id);
  }

  sub panel_listening_event_js {
    <<'EOF';
window.addEventListener('load', function () {
  var audio_player = document.getElementById('audio_player');
  var corr_link = document.getElementById('user_rating_correlations_toggle');
  var album_chart_link = document.getElementById('album_chart_toggle');
  var urc_table = document.getElementById("user_rating_correlations_table");
  var ac_table = document.getElementById("album_chart_table");
  var show_album_chart, show_correlations;

  // XXX functionality relating to show_album_chart and show_correlations
  // XXX are mostly copy-and-paste

  function getQueryVariable(variable) {
    try {
      var query = window.location.search.substring(1);
      var vars = query.split('&');
      for (var i = 0; i < vars.length; i++) {
        var pair = vars[i].split('=');
        if (pair[0] === variable) { return pair[1]; }
      }
    } catch (ex) {
      alert('error looking up query variable ' + variable + ' : ' + ex);
    }

    return false;
  }

  function set_element_visibility(element, visible) {
    if (visible) {
      element.style.display = 'block';
    } else {
      element.style.display = 'none';
    }
  }

  function set_album_chart_visibility(visible) {
    if (visible) {
      show_album_chart = '1';
      set_element_visibility(ac_table, true);
    } else {
      show_album_chart = '0';
      set_element_visibility(ac_table, false);
    }
  }

  function set_correlations_visibility(visible) {
    if (visible) {
      show_correlations = '1';
      set_element_visibility(urc_table, true);
    } else {
      show_correlations = '0';
      set_element_visibility(urc_table, false);
    }
  }

  if (getQueryVariable('show_correlations') === '0') {
    set_correlations_visibility(false);
  } else {
    set_correlations_visibility(true);
  }

  if (getQueryVariable('show_album_chart') === '0') {
    set_album_chart_visibility(false);
  } else {
    set_album_chart_visibility(true);
  }

  var previous_song_link = document.getElementById('previous_song_link');
  var next_song_link = document.getElementById('next_song_link');

  if (previous_song_link) {
    previous_song_link.addEventListener('click', function(event) {
      var link_target = previous_song_link.getAttribute('href');
      var url_params = "&show_correlations=" + show_correlations
                         + "&show_album_chart=" + show_album_chart;
      previous_song_link.setAttribute('href', link_target + url_params);
    });
  }
  if (next_song_link) {
    next_song_link.addEventListener('click', function(event) {
      var link_target = next_song_link.getAttribute('href');
      var url_params = "&show_correlations=" + show_correlations
                         + "&show_album_chart=" + show_album_chart;
      next_song_link.setAttribute('href', link_target + url_params);
    });
  }

  if (!audio_player) {
    alert('Could not find the audio player!');
  } else {
    if (next_song_link) {
      audio_player.addEventListener('ended', function (event) {
        // Use a timeout here, in case something was wrong and the
        // "ended"-signal happened prematurely, so we would not immediately
        // hop to the winning song, giving some time to react.
        setTimeout(function() { next_song_link.click(); }, 1000);
      });
    }
  }

  if (!corr_link) {
    alert('Could not find the user rating correlations table link!');
  } else if (!urc_table) {
    alert('Could not find the user rating correlations table!');
  } else {
    corr_link.addEventListener('click', function(event) {
      // this should toggle the correlations visibility
      event.preventDefault();
      if (show_correlations === '0') {
        set_correlations_visibility(true);
      } else {
        set_correlations_visibility(false);
      }
    });
  }

  if (!album_chart_link) {
    alert('Could not find the album chart table link!');
  } else if (!ac_table) {
    alert('Could not find the album chart table!');
  } else {
    album_chart_link.addEventListener('click', function(event) {
      // this should toggle the album chart visibility
      event.preventDefault();
      if (show_album_chart === '0') {
        set_album_chart_visibility(true);
      } else {
        set_album_chart_visibility(false);
      }
    });
  }
});
EOF
  }

  sub panel_ratings_by_user_js {
    my ($panel_id, $user_id) = @_;
    my $playlist = make_playlist($panel_id);
    my $playlist_json = encode_json($playlist);

    my $normalized_ratings_by_song_id
      = get_normalized_ratings_by_song_id($panel_id, $user_id);
    my $normalized_ratings_json = encode_json($normalized_ratings_by_song_id);

    <<"EOF"
window.addEventListener('load', function () {
  var ratings_form = document.getElementById('song ratings');
  var playlist_song_ids = ${playlist_json};
  var normalized_ratings = ${normalized_ratings_json};
  var current_playback_song_index = null;
  var audio_player = document.getElementById('audio_player');
  var unrated_song_count_html = document.getElementById('unrated_song_count');
  var submitbuttons_state = null;

  function addSonglinkEventListener(html_song_link, song_id) {
    html_song_link.addEventListener('click', function(event) {
      event.preventDefault();
      changePlaybackSong(song_id);
    });
  }

  function changeSubmitButtonsState(enable_or_disable) {
    if (submitbuttons_state === enable_or_disable) {
      return;
    }

    var submit_buttons = document.getElementsByName('send_ratings');
    for (var i = 0; i < submit_buttons.length; i++) {
      var button = submit_buttons[i];
      if (enable_or_disable) {
        button.disabled = false;
      } else {
        button.disabled = true;
      }
    }

    submitbuttons_state = enable_or_disable;
  }

  function getNextPlaybackSongId() {
    if (playlist_song_ids.length === 0) { return null; }

    var next_index = 0;
    if (current_playback_song_index !== null) {
      next_index = (current_playback_song_index + 1)
                     % playlist_song_ids.length;
    }
    first_next_index = next_index;

    var rating_value
      = normalized_ratings[ playlist_song_ids[next_index] ].value;

    // find the next song in playlist that user has not rated yet
    while (rating_value !== null) {
      next_index = (next_index + 1) % playlist_song_ids.length;
      if (first_next_index === next_index) {
        // if we are back to the first index we tried, user has probably
        // rated all songs and just move on to this one
        break;
      }
      rating_value = normalized_ratings[ playlist_song_ids[next_index] ].value;
    }

    return playlist_song_ids[next_index];
  }

  function changePlaybackSong(song_id) {
    var playback_song_id;
    if (song_id === null) {
      playback_song_id = getNextPlaybackSongId();
    } else {
      playback_song_id = song_id;
    }

    if (playback_song_id === null) {
      return;
    }

    var ap_source = document.getElementById('audio_player_source');
    var link = '../song/play?song_id=' + playback_song_id;
    ap_source.src = link;

    audio_player.load();
    audio_player.play();

    if (current_playback_song_index !== null) {
      var old_playback_song_id
        = playlist_song_ids[ current_playback_song_index ];
      var html_old_song_id = 'songs[' + old_playback_song_id + '].song';
      var old_song_id_element = document.getElementById(html_old_song_id);
      if (old_song_id_element !== null) {
        old_song_id_element.className = 'not_playback_song';
      }
    }

    var html_new_song_id = 'songs[' + playback_song_id + '].song';
    var new_song_id_element = document.getElementById(html_new_song_id);
    if (new_song_id_element !== null) {
      new_song_id_element.className = 'playback_song';
    }

    for (var i = 0; i < playlist_song_ids.length; i++) {
      if (playback_song_id === playlist_song_ids[i]) {
        current_playback_song_index = i;
        break;
      }
    }
  }

  function sendData() {
    var xhr = new XMLHttpRequest();
    var fd  = new FormData(ratings_form);

    xhr.addEventListener('load', function(event) {
      try {
        var text = event.target.responseText;
        var response_struct = JSON.parse(text);
        var errors = response_struct.errors;
        var error_message = null;

        if (!errors || typeof(errors) !== 'object') {
          throw('invalid response from server (missing errors)');
        }
        for (key in errors) {
          if (typeof(errors[key]) !== 'string') {
            throw('invalid error type');
          }
          if (!error_message) {
            error_message = errors[key];
          } else {
            error_message = (error_message + ' / ' + errors[key]);
          }
        }
        if (error_message) { throw(error_message); }

        var tmp_normalized = response_struct.normalized_ratings;
        if (!tmp_normalized || typeof(tmp_normalized) !== "object") {
          throw('invalid response from server (missing normalized ratings)');
        }
        normalized_ratings = tmp_normalized;

        var unrated_song_count = response_struct.unrated_song_count;
        if (unrated_song_count === null) {
          throw('invalid response from server (missing unrated_song_count)');
        }

        for (song_id in normalized_ratings) {
          var element_id = 'songs[' + song_id + '].normalized_rating';
          var normalized_rating = document.getElementById(element_id);
          if (!normalized_rating) {
            throw('could not find normalized rating element');
          }

          var nv_info = normalized_ratings[song_id];
          if (!nv_info || typeof(nv_info) !== 'object') {
            throw('normalized value info is not a valid object');
          }

          if (typeof(nv_info.html_string) !== 'string') {
            throw('normalized value info does not contain html string');
          }
          if (typeof(nv_info.color_style) !== 'string') {
            throw('normalized value info does not contain color style');
          }

          normalized_rating.innerHTML = nv_info.html_string;
          normalized_rating.style = nv_info.color_style;
        }

        if (unrated_song_count_html) {
          unrated_song_count_html.innerText = unrated_song_count;
        }

        changeSubmitButtonsState(false);
      } catch (err) {
        alert('Problems: ' + err);
      }
    });

    xhr.addEventListener('error', function(event) {
      alert('Async request error!  Oh noes!  This may be BAAAD!');
    });

    // Set up our request
    xhr.open('POST', 'send_ratings');

    xhr.send(fd);
  }

  if (!ratings_form) {
    alert('Could not find the ratings form!');
  } else {
    ratings_form.addEventListener('submit', function (event) {
      event.preventDefault();
      sendData();
    });

    var select_inputs = ratings_form.getElementsByTagName('select');
    for (var i = 0; i < select_inputs.length; i++) {
      var input = select_inputs[i];
      input.addEventListener('change', function(event) {
        changeSubmitButtonsState(true);
      });
    }

    var form_inputs = ratings_form.getElementsByTagName('input');
    for (var i = 0; i < form_inputs.length; i++) {
      var input = form_inputs[i];
      if (input.type !== 'text') { continue; }
      input.addEventListener('input', function(event) {
        changeSubmitButtonsState(true);
      });
    }

    changeSubmitButtonsState(false);
  }

  if (!audio_player) {
    alert('Could not find the audio player!');
  } else {
    changePlaybackSong(null);
    audio_player.addEventListener('ended', function (event) {
      changePlaybackSong(null);
    });

    if (ratings_form) {
      for (var i = 0; i < playlist_song_ids.length; i++) {
        var song_id = playlist_song_ids[i];
        var song_link_id = 'songs[' + song_id + '].playback_link';
        var html_song_link = document.getElementById(song_link_id);
        addSonglinkEventListener(html_song_link, song_id);
      }
    }
  }
});
EOF
  }
}

1;
