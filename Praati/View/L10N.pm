# -*- mode: perl; coding: utf-8; -*-
# $Id: L10N.pm,v 1.1 2014/05/08 19:03:17 je Exp $

use strict;

# XXX Problems with Locale::Maketext with this!
# XXX (with Finnish locale, with _1 and \d+ regular expression test)
# XXX Perhaps related to OpenBSD chroot?
# use utf8;

use warnings FATAL => qw(all);

use Locale::Maketext;

package Praati::View::L10N {
  use base qw(Locale::Maketext);
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

    'Play songs from worst to best'
      => 'Soita laulut huonoimmasta parhaimpaan.',
    'Play to the worst, then to the best from position:'
      => 'Soita huonoimpaan, sitten parhaimpaan sijoituksesta:',


    'New listening session'   => 'Uusi kuuntelusessio',
    'Listening session name:' => 'Kuuntelusession nimi:',
    'Select session type:'    => 'Valitse session tyyppi:',
    'Create'                  => 'Luo',

    'Play song at position [_1]' => 'Soita laulu, jolla on sijoitus [_1]',

    'Song rating statistics'   => 'Laulun arvostelujen tilastotietoa',
    'Ratings for song'         => 'Laulun arvostelut',
    'User rating correlations' => 'Käyttäjien arvostelujen korrelaatiot',

    'Listening event for [_1]' => 'Kuuntelusessio laululle [_1]',

    'User rating counts' => 'Käyttäjien arvostelujen lukumäärä',
    'Playback events'    => 'Soittotapahtumat',

    'play' => 'soita',

    'normalized rating average' => 'normalisoitujen arvostelujen keskiarvo',
    'rating average'            => 'arvostelujen keskiarvo',
    'normalized rating standard deviation'
       => 'normalisoitujen arvostelujen keskihajonta',
    'rating standard deviation' => 'arvostelujen keskihajonta',
    'user'                      => 'käyttäjä',
    'rating count'              => 'arvostelujen lukumäärä',

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

    'Password is missing.'    => 'Salasana puuttuu.',
    'Passwords do not match.' => 'Salasanat eivät täsmää.',

    'username'          => 'käyttäjänimi',
    'rating'            => 'arvostelu',
    'normalized rating' => 'normalisoitu arvostelu',
    'comment'           => 'kommentti',

    'previous' => 'edellinen',
    'next'     => 'seuraava',
  );
}

1;
