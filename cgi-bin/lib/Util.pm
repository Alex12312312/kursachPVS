package Util;
use strict;
use warnings;
use utf8;
use Encode qw(decode);
use Exporter 'import';

our @EXPORT_OK = qw(
  url_decode
  parse_params
  html_escape
  page
);

sub url_decode {
  my ($s) = @_;
  $s //= '';
  $s =~ tr/+/ /;
  $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
  return $s;
}

sub parse_params {
  my ($raw) = @_;
  $raw //= '';
  my %p;
  for my $pair (split /[&;]/, $raw) {
    next if $pair eq '';
    my ($k, $v) = split /=/, $pair, 2;
    $k = url_decode($k // '');
    $v = url_decode($v // '');
    # Попытка привести к UTF-8, если пришло как байты
    # (в Windows/CGI это часто нужно)
    eval { $k = decode('UTF-8', $k, 1) };
    eval { $v = decode('UTF-8', $v, 1) };
    $p{$k} = $v;
  }
  return \%p;
}

sub html_escape {
  my ($s) = @_;
  $s //= '';
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/>/&gt;/g;
  $s =~ s/"/&quot;/g;
  $s =~ s/'/&#39;/g;
  return $s;
}

sub page {
  my (%a) = @_;
  my $title = $a{title} // 'CGI';
  my $body  = $a{body}  // '';
  my $nav_extra = $a{nav_extra} // '';
   my $extra_headers = $a{extra_headers} // '';

  my $auth_info = $a{auth_info} // {};
  my $user_label = '';
  if ($auth_info->{user}) {
    my $u = $auth_info->{user};
    my $name = html_escape($u->{full_name});
    my $role = html_escape($u->{role});
    $user_label = qq{<span class="pill">Вы вошли как $name ($role)</span> <a class="pill" href="/cgi-bin/logout.pl">Выйти</a>};
  } else {
    $user_label = qq{<a class="pill" href="/login.html">Войти</a>};
  }

  return <<"HTML";
Content-Type: text/html; charset=utf-8
$extra_headers

<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>$title</title>
  <link rel="stylesheet" href="/styles.css" />
  <script defer src="/app.js"></script>
</head>
<body>
  <a id="top"></a>
  <header>
    <div class="container bar">
      <a class="brand" href="/">
        <img src="/assets/logo.svg" alt="Логотип" />
        <div>
          <strong>Сайт студенческой группы</strong>
          <span>Динамика (Perl CGI)</span>
        </div>
      </a>
      <nav>
        <a href="/">Главная</a>
        <a href="/cgi-bin/schedule.pl">Расписание</a>
        <a href="/cgi-bin/gallery.pl">Галерея</a>
        <a href="/cgi-bin/users.pl">Список группы</a>
        $nav_extra
      </nav>
    </div>
  </header>
  <main class="container">
    <section class="card" style="margin-bottom:16px">
      $user_label
    </section>
    $body
    <footer class="card" style="margin-top:16px">
      <div class="anchors">
        <a href="#top">В начало</a>
        <a href="#bottom">В конец</a>
        <a href="/">На главную</a>
      </div>
      <a id="bottom"></a>
      <div style="margin-top:10px">
        <span class="pill">© <span data-year></span></span>
        <span class="pill">CGI</span>
        <span class="pill">DBM</span>
      </div>
    </footer>
  </main>
</body>
</html>
HTML
}

1;

