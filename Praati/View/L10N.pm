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

use feature qw(unicode_strings);
use strict;
use utf8;
use warnings FATAL => qw(all);

use CGI (-utf8);
use Locale::Maketext;

package Praati::View::L10N {
  use base qw(Locale::Maketext);

  use Exporter qw(import);
  BEGIN { our @EXPORT_OK = qw(t); }

  our $Lh;

  sub init_praati_l10n {
    # XXX other languages that Finnish should be supported as well
    $Lh = Praati::View::L10N->get_handle('fi')
      or confess('Could not get a localization handle');
  }

  sub t { $Lh->maketext(@_); }
}

package Praati::View::L10N::fi {
  use base qw(Praati::View::L10N);

  our %Lexicon = (
    'Access unauthorized.' => 'Pääsy kielletty.',
    'Unauthorized access'  => 'Pääsy kielletty',
    'No such page'         => 'Etsimääsi sivua ei löydy',
    'No such page.'        => 'Etsimääsi sivua ei löydy.',

    'Login'    => 'Kirjaudu sisään',
    'Logout'   => 'Kirjaudu ulos',
    'Main'     => 'Pääsivu',
    'New user' => 'Uusi käyttäjä',
    'Panels'   => 'Raadit',

    'The main page.' => 'Pääsivu.',

    'Not logged in'           => 'Ei sisäänkirjautuneena',
    'You are not logged in.'  => 'Et ole sisäänkirjautuneena.',
    'Logged out'              => 'Kirjauduttu ulos',
    'You are now logged out.' => 'Olet nyt kirjautunut ulos.',
    'Logout error'            => 'Uloskirjautumisvirhe',
    'Could not log out for some reason.'
       => 'Uloskirjautuminen ei onnistunut jostain syystä.',

    'Logged in as "[_1]" ([_2])'
       => 'Olet kirjautuneena käyttäjänä [_1] ([_2])',

    'email address:'  => 'sähköpostiosoite:',
    'name:'           => 'nimi:',
    'password:'       => 'salasana:',
    'password again:' => 'salasana uudestaan:',
    'Create new user' => 'Luo uusi käyttäjä',

    'Available panels'      => 'Valittavissa olevat raadit',
    'Available panels are:' => 'Valittavissa olevat raadit ovat:',

    'This panel is "[_1]".' => 'Tämä raati on "[_1]".',

    'User email address is not valid.' => 'Sähköpostiosoite ei ole kelvollinen.',
    'Email address is already reserved.' => 'Sähköpostiosoite on jo varattu.',
    'Username is already reserved.'      => 'Käyttäjänimi on jo varattu.',

    'Wrong username or password.' => 'Väärä käyttäjänimi tai salasana.',

    'Rate songs for "[_1]"' => 'Arvostele laulut raadissa "[_1]"',
    'Unrated song count:' => 'Arvostelemattomien laulujen määrä:',

    'Play songs from worst to best'
      => 'Soita laulut huonoimmasta parhaimpaan.',
    'Play to the worst, then to the best from position:'
      => 'Soita huonoimpaan, sitten parhaimpaan sijoituksesta:',


    'New listening session'   => 'Uusi kuuntelusessio',
    'Listening session name:' => 'Kuuntelusession nimi:',
    'Select session type:'    => 'Valitse session tyyppi:',
    'Create'                  => 'Luo',

    'Play song at position [_1]' => 'Soita laulu, jolla on sijoitus [_1]',

    'Listening event for [_1]' => 'Kuuntelusessio laululle [_1]',

    'User rating counts' => 'Käyttäjien arvostelujen lukumäärä',
    'Playback events'    => 'Soittotapahtumat',

    'Save all' => 'Tallenna kaikki',
    'play'     => 'soita',

    'user'         => 'käyttäjä',
    'rating count' => 'arvostelujen lukumäärä',

    'create a new listening session' => 'luo uusi kuuntelusessio',
    'rate'                           => 'arvostele',

    'To login, cookies must be accepted by the browser.'
      => 'Kirjautuaksesi "keksien" täytyy olla selaimessasi hyväksyttyjä.',

    'Listening session name is missing.' => 'Kuuntelusession nimi puuttuu.',
    'Session type is missing.'           => 'Kuuntelusession tyyppi puuttuu.',
    'Song position is not valid' => 'Laulun sijoitus ei ole kelvollinen.',

    'Create a new listening session for panel "[_1]":'
      => 'Luo uusi kuuntelusessio raadille "[_1]":',

    'Listening session overview for "[_1]".'
       => 'Kuuntelusession yleiskatsaus sessiolle "[_1]".',

    'Rating correlations' => 'Arvostelukorrelaatiot',

    'Password is missing.'    => 'Salasana puuttuu.',
    'Passwords do not match.' => 'Salasanat eivät täsmää.',
  );
}

1;
