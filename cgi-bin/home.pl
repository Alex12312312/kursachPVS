use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw(html_escape page);
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

my $news = DB::list_news($t);

my $cards = '';
for my $n (@$news) {
  my $title = html_escape($n->{title});
  my $img   = html_escape($n->{image} || '/assets/logo.svg');
  my $id    = html_escape($n->{id});
  $cards .= <<"HTML";
<article class="card">
  <a href="/cgi-bin/news.pl?id=$id" style="text-decoration:none;color:inherit">
    <div class="img-frame">
      <img src="$img" alt="$title" />
    </div>
    <h2 style="margin-top:10px">$title</h2>
  </a>
</article>
HTML
}
$cards ||= qq{<p class="muted">Пока нет новостей.</p>};

my $body = <<"HTML";
<section class="card">
  <h1>Новости группы</h1>
  <p>Главная страница: каждая новость показана как картинка, по щелчку — переход на страницу новости.</p>
</section>

<section class="grid" style="margin-top:16px">
  $cards
</section>
HTML

print page(
  title => 'Главная — новости',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

