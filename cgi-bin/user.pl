use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw(html_escape page parse_params);
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

my $method = $ENV{REQUEST_METHOD} // 'GET';
my $params;
if ($method eq 'GET') {
  $params = parse_params($ENV{QUERY_STRING} // '');
} else {
  my $len = int($ENV{CONTENT_LENGTH} // 0);
  my $raw = '';
  read(STDIN, $raw, $len) if $len > 0;
  $params = parse_params($raw);
}

my $id = $params->{id} // '';

my $t = DB::open_all();
my $cookies = parse_cookies();
my $session = $cookies->{SESSION_ID} // '';
my $current_user;
if ($session) {
  my $uid = DB::get_session_user_id($t, $session);
  $current_user = DB::get_user($t, $uid) if $uid;
}

my $user = DB::get_user($t, $id);

my $body;
if (!$user) {
  my $safe = html_escape($id);
  $body = <<"HTML";
<section class="card">
  <h1>Студент не найден</h1>
  <p>Не найден студент с id <span class="pill">$safe</span>.</p>
  <div class="anchors">
    <a href="/cgi-bin/users.pl">Назад к списку группы</a>
  </div>
</section>
HTML
  print page(
    title => 'Студент не найден',
    body  => $body,
    auth_info => { user => $current_user },
  );
  DB::close_all($t);
  exit 0;
}

my $name  = html_escape($user->{full_name});
my $role  = html_escape($user->{role});
my $email = html_escape($user->{email});
my $login = html_escape($user->{login});

$body = <<"HTML";
<section class="card">
  <h1>Личная страница студента</h1>

  <table>
    <tbody>
      <tr><th>ФИО</th><td>$name</td></tr>
      <tr><th>Роль</th><td>$role</td></tr>
      <tr><th>Email</th><td>$email</td></tr>
      <tr><th>Логин</th><td>$login</td></tr>
    </tbody>
  </table>

  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl">Назад к списку группы</a>
  </div>
</section>
HTML

print page(
  title => "Студент — $name",
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

