# -*- mode: perl; coding: iso-8859-1; -*-
# $Id: L10N.pm,v 1.12 2014/06/21 08:08:12 je Exp $
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

use strict;
use warnings FATAL => qw(all);

use CGI;
use Locale::Maketext;

package Praati::View::L10N {
  use base qw(Locale::Maketext);

  use Exporter qw(import);
  our @EXPORT = qw(t);

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
    'Access unauthorized.' => 'P��sy kielletty.',
    'Unauthorized access'  => 'P��sy kielletty',
    'No such page'         => 'Etsim��si sivua ei l�ydy',
    'No such page.'        => 'Etsim��si sivua ei l�ydy.',

    'Login'    => 'Kirjaudu sis��n',
    'Logout'   => 'Kirjaudu ulos',
    'Main'     => 'P��sivu',
    'New user' => 'Uusi k�ytt�j�',
    'Panels'   => 'Raadit',

    'The main page.' => 'P��sivu.',

    'Not logged in'           => 'Ei sis��nkirjautuneena',
    'You are not logged in.'  => 'Et ole sis��nkirjautuneena.',
    'Logged out'              => 'Kirjauduttu ulos',
    'You are now logged out.' => 'Olet nyt kirjautunut ulos.',
    'Logout error'            => 'Uloskirjautumisvirhe',
    'Could not log out for some reason.'
       => 'Uloskirjautuminen ei onnistunut jostain syyst�.',

    'Logged in as "[_1]" ([_2])'
       => 'Olet kirjautuneena k�ytt�j�n� [_1] ([_2])',

    'email address:'  => 's�hk�postiosoite:',
    'name:'           => 'nimi:',
    'password:'       => 'salasana:',
    'password again:' => 'salasana uudestaan:',
    'Create new user' => 'Luo uusi k�ytt�j�',

    'Available panels'      => 'Valittavissa olevat raadit',
    'Available panels are:' => 'Valittavissa olevat raadit ovat:',

    'This panel is "[_1]".' => 'T�m� raati on "[_1]".',

    'User email address is not valid.' => 'S�hk�postiosoite ei ole kelvollinen.',
    'Email address is already reserved.' => 'S�hk�postiosoite on jo varattu.',
    'Username is already reserved.'      => 'K�ytt�j�nimi on jo varattu.',

    'Wrong username or password.' => 'V��r� k�ytt�j�nimi tai salasana.',

    'Rate songs for "[_1]"' => 'Arvostele laulut raadissa "[_1]"',

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

    'User rating counts' => 'K�ytt�jien arvostelujen lukum��r�',
    'Playback events'    => 'Soittotapahtumat',

    'Save all' => 'Tallenna kaikki',
    'play'     => 'soita',

    'user'         => 'k�ytt�j�',
    'rating count' => 'arvostelujen lukum��r�',

    'create a new listening session' => 'luo uusi kuuntelusessio',
    'rate'                           => 'arvostele',

    'To login, cookies must be accepted by the browser.'
      => 'Kirjautuaksesi "keksien" t�ytyy olla selaimessasi hyv�ksyttyj�.',

    'Listening session name is missing.' => 'Kuuntelusession nimi puuttuu.',
    'Session type is missing.'           => 'Kuuntelusession tyyppi puuttuu.',
    'Song position is not valid' => 'Laulun sijoitus ei ole kelvollinen.',

    'Create a new listening session for panel "[_1]":'
      => 'Luo uusi kuuntelusessio raadille "[_1]":',

    'Listening session overview for "[_1]".'
       => 'Kuuntelusession yleiskatsaus sessiolle "[_1]".',

    'Password is missing.'    => 'Salasana puuttuu.',
    'Passwords do not match.' => 'Salasanat eiv�t t�sm��.',
  );
}

1;
