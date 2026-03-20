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

my $params = parse_params($ENV{QUERY_STRING} // '');
my $faculty_id = $params->{faculty_id} // '';
my $group_id   = $params->{group_id} // '';

my $body = '';
if ($faculty_id eq '') {
  my $faculties = DB::list_faculties($t);
  my $items = '';
  for my $f (@$faculties) {
    my $id = html_escape($f->{id});
    my $name = html_escape($f->{name});
    $items .= qq{<li><a class="btn" href="/cgi-bin/users.pl?faculty_id=$id">$name</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Шаг 1: выберите факультет.</p>
  <ol class="toc">$items</ol>
</section>
HTML
} elsif ($group_id eq '') {
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $groups = DB::list_groups_by_faculty($t, $faculty_id);
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  my $items = '';
  for my $g (@$groups) {
    my $gid = html_escape($g->{id});
    my $gname = html_escape($g->{name});
    $items .= qq{<li><a class="btn" href="/cgi-bin/users.pl?faculty_id=$faculty_id&group_id=$gid">$gname</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Шаг 2: факультет <span class="pill">$fname</span>. Выберите группу.</p>
  <ol class="toc">$items</ol>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl">Назад к факультетам</a>
  </div>
</section>
HTML
} else {
  my $group = DB::get_group($t, $group_id);
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $users = DB::list_users_by_group($t, $group_id);

  my $rows = '';
  for my $u (@$users) {
    my $name = html_escape($u->{full_name});
    my $role = html_escape($u->{role});
    my $email = html_escape($u->{email});
    my $id = html_escape($u->{id});
    $rows .= <<"HTML";
<tr>
  <td><a href="/cgi-bin/user.pl?id=$id">$name</a></td>
  <td>$role</td>
  <td>$email</td>
</tr>
HTML
  }

  my $gname = html_escape($group ? $group->{name} : "ID $group_id");
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Факультет: <span class="pill">$fname</span>, группа: <span class="pill">$gname</span>.</p>

  <table>
    <thead>
      <tr>
        <th>ФИО</th>
        <th>Роль</th>
        <th>Email</th>
      </tr>
    </thead>
    <tbody>
      $rows
    </tbody>
  </table>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl?faculty_id=$faculty_id">Назад к выбору группы</a>
    <a href="/cgi-bin/users.pl">Назад к факультетам</a>
  </div>
</section>
HTML
}

print page(
  title => 'Список группы',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

