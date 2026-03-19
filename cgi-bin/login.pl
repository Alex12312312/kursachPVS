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

sub gen_token {
  my $rand = rand();
  my $now  = time();
  return sprintf("%x%x", $now, int($rand * 1_000_000));
}

my $t = DB::open_all();
my $cookies = parse_cookies();
my $session = $cookies->{SESSION_ID} // '';
my $current_user;
if ($session) {
  my $uid = DB::get_session_user_id($t, $session);
  $current_user = DB::get_user($t, $uid) if $uid;
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

my $email = $params->{email} // '';
my $error = '';
my $extra_headers = '';

if ($method eq 'POST') {
  my $u = DB::find_user_by_email($t, $email);
  if ($u) {
    my $token = gen_token();
    DB::create_session($t, $u->{id}, $token);
    DB::add_log($t, $u->{id}, 'login', "email=$email");
    $extra_headers = "Status: 302 Found\r\nSet-Cookie: SESSION_ID=$token; Path=/\r\nLocation: /\r\n";
    $current_user = $u;
  } else {
    $error = 'Пользователь с таким email не найден.';
  }
}

my $error_html = $error ? qq{<p class="note">$error</p>} : '';

my $body = <<'HTML';
<section class="card">
  <h1>Авторизация</h1>
  <p>Авторизация по email (без пароля) — учебный пример. Роли: староста/учорг/профорг/студлидер/студент.</p>
  $error_html
  <form method="post" action="/cgi-bin/login.pl">
    <div class="field">
      <label for="email">Email</label>
      <input id="email" name="email" type="email" placeholder="ivanov@example.com" required />
    </div>
    <button class="btn" type="submit">Войти</button>
  </form>
</section>
HTML

print page(
  title => 'Авторизация',
  body  => $body,
  auth_info => { user => $current_user },
  extra_headers => $extra_headers,
);

DB::close_all($t);

