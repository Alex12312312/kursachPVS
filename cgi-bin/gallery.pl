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

my $t = DB::open_all();
my $cookies = parse_cookies();
my $session = $cookies->{SESSION_ID} // '';
my $current_user;
if ($session) {
  my $uid = DB::get_session_user_id($t, $session);
  $current_user = DB::get_user($t, $uid) if $uid;
}

my $method = $ENV{REQUEST_METHOD} // 'GET';
if ($method eq 'POST') {
  my $len = int($ENV{CONTENT_LENGTH} // 0);
  my $raw = '';
  read(STDIN, $raw, $len) if $len > 0;
  my $p = parse_params($raw);
  my $title = $p->{title} // '';
  my $url   = $p->{url}   // '';
  if ($current_user && $title ne '' && $url ne '') {
    my $pid = DB::add_photo($t, $title, $url, $current_user->{id});
    DB::add_log($t, $current_user->{id}, 'photo_uploaded', $pid);
  }
}

my $photos = DB::list_photos($t);

my $cards = '';
for my $p (@$photos) {
  my $title = html_escape($p->{title});
  my $url   = html_escape($p->{url});
  my $author = DB::get_user($t, $p->{author_id});
  my $author_name = $author ? html_escape($author->{full_name}) : 'Неизвестный автор';

  $cards .= <<"HTML";
<article class="card">
  <div class="img-frame">
    <img src="$url" alt="$title" />
  </div>
  <h2 style="margin-top:10px">$title</h2>
  <p class="muted">Автор: $author_name</p>
</article>
HTML
}
$cards ||= qq{<p class="muted">Пока нет фотографий.</p>};

my $upload_block = '';
if ($current_user) {
  $upload_block = <<"HTML";
<section class="card" style="margin-top:16px">
  <h2>Добавить фотографию</h2>
  <form method="post" action="/cgi-bin/gallery.pl">
    <div class="field">
      <label for="title">Заголовок</label>
      <input id="title" name="title" required />
    </div>
    <div class="field">
      <label for="url">URL изображения</label>
      <input id="url" name="url" placeholder="/assets/group-photo.svg" required />
    </div>
    <button class="btn" type="submit">Загрузить фотографию в галерею</button>
  </form>
</section>
HTML
}

my $body = <<"HTML";
<section class="card">
  <h1>Галерея</h1>
</section>

<section class="grid" style="margin-top:16px">
  $cards
</section>
$upload_block
HTML

print page(
  title => 'Галерея',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

