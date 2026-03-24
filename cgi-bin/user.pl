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
my $group = $user->{groupid} ? DB::get_group($t, $user->{groupid}) : undef;
my $department = ($group && $group->{department_id}) ? DB::get_department($t, $group->{department_id}) : undef;
my $faculty = ($group && $group->{faculty_id}) ? DB::get_faculty($t, $group->{faculty_id}) : undef;
my $group_name = $group ? html_escape($group->{name}) : '—';
my $department_name = $department ? html_escape($department->{name}) : '—';
my $faculty_name = $faculty ? html_escape($faculty->{name}) : '—';
my $news_items = DB::list_news_by_author($t, $user->{id});
my $photo_items = DB::list_photos_by_author($t, $user->{id});

sub fmt_dt {
  my ($ts) = @_;
  return '—' if !defined $ts || $ts !~ /^\d+$/;
  my @lt = localtime($ts);
  return sprintf('%02d.%02d.%04d %02d:%02d', $lt[3], $lt[4] + 1, $lt[5] + 1900, $lt[2], $lt[1]);
}

my $news_rows = '';
for my $n (@$news_items) {
  my $nid = html_escape($n->{id});
  my $title = html_escape($n->{title});
  my $created = html_escape(fmt_dt($n->{created_at}));
  $news_rows .= <<"HTML";
<tr>
  <td><a href="/cgi-bin/news.pl?id=$nid">$title</a></td>
  <td>$created</td>
</tr>
HTML
}
$news_rows ||= qq{<tr><td colspan="2" class="muted">Новостей пока нет.</td></tr>};

my $photo_rows = '';
for my $p (@$photo_items) {
  my $title = html_escape($p->{title});
  my $url = html_escape($p->{url});
  my $created = html_escape(fmt_dt($p->{created_at}));
  $photo_rows .= <<"HTML";
<tr>
  <td><a href="$url" target="_blank" rel="noopener noreferrer">$title</a></td>
  <td>$created</td>
</tr>
HTML
}
$photo_rows ||= qq{<tr><td colspan="2" class="muted">Фотографий пока нет.</td></tr>};

$body = <<"HTML";
<section class="card">
  <h1>Личная страница студента</h1>

  <table>
    <tbody>
      <tr><th>ФИО</th><td>$name</td></tr>
      <tr><th>Роль</th><td>$role</td></tr>
      <tr><th>Email</th><td>$email</td></tr>
      <tr><th>Логин</th><td>$login</td></tr>
      <tr><th>Группа</th><td>$group_name</td></tr>
      <tr><th>Кафедра</th><td>$department_name</td></tr>
      <tr><th>Факультет</th><td>$faculty_name</td></tr>
    </tbody>
  </table>

  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl">Назад к списку группы</a>
  </div>
</section>

<section class="card" style="margin-top:16px">
  <table>
    <thead>
      <tr>
        <th>Заголовок</th>
        <th>Дата</th>
      </tr>
    </thead>
    <tbody>
      $news_rows
    </tbody>
  </table>
  <table>
    <thead>
      <tr>
        <th>Название</th>
        <th>Дата</th>
      </tr>
    </thead>
    <tbody>
      $photo_rows
    </tbody>
  </table>
</section>
HTML

print page(
  title => "Студент — $name",
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

