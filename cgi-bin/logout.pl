use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw(page);
use DB qw();

sub parse_cookies {
  my $raw = $ENV{HTTP_COOKIE} // '';
  my %c;
  for my $pair (split /;\s*/, $raw) {
    next unless $pair;
    my ($k, $v) = split /=/, $pair, 2;
    $c{$k} = $v // '';
  }
  return \%c;
}

my $t = DB::open_all();
my $cookies = parse_cookies();
my $session = $cookies->{SESSION_ID} // '';
my $current_user;
if ($session) {
  my $uid = DB::get_session_user_id($t, $session);
  $current_user = DB::get_user($t, $uid) if $uid;
  DB::add_log($t, $current_user->{id}, 'logout', '') if $current_user;
  DB::delete_session($t, $session);
}

my $extra_headers = "Set-Cookie: SESSION_ID=deleted; Path=/; Max-Age=0\r\n";

my $body = <<"HTML";
<section class="card">
  <h1>Вы вышли из системы</h1>
  <div class="anchors" style="margin-top:12px">
    <a href="/">На главную</a>
    <a href="/login.html">Авторизация</a>
  </div>
</section>
HTML

print page(
  title => 'Выход',
  body  => $body,
  auth_info => { user => undef },
  extra_headers => $extra_headers,
);

DB::close_all($t);

