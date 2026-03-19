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

my $news = DB::get_news($t, $id);

my $body;
if (!$news) {
  my $safe = html_escape($id);
  $body = <<"HTML";
<section class="card">
  <h1>Новость не найдена</h1>
  <p>Не найдена новость с идентификатором <span class="pill">$safe</span>.</p>
  <div class="anchors">
    <a href="/">На главную</a>
  </div>
</section>
HTML
  print page(
    title => 'Новость не найдена',
    body  => $body,
    auth_info => { user => $current_user },
  );
  DB::close_all($t);
  exit 0;
}

my $title  = html_escape($news->{title});
my $text   = html_escape($news->{body});
my $img    = html_escape($news->{image} || '/assets/logo.svg');
my $author = DB::get_user($t, $news->{author_id});
my $author_name = $author ? html_escape($author->{full_name}) : 'Неизвестный автор';

$body = <<"HTML";
<section class="card">
  <h1>$title</h1>
  <p class="muted">Автор: $author_name</p>

  <div class="img-frame" style="margin:12px 0">
    <img src="$img" alt="$title" />
  </div>

  <p>$text</p>

  <div class="anchors" style="margin-top:12px">
    <a href="/">К списку новостей</a>
  </div>
</section>
HTML

print page(
  title => "Новость — $title",
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

