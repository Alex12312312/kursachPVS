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
my $faculty_id    = $params->{faculty_id} // '';
my $department_id = $params->{department_id} // '';
my $group_id      = $params->{group_id} // '';
my $sort_by       = $params->{sort_by} // '';
my $sort_dir      = $params->{sort_dir} // 'asc';
$sort_dir = lc($sort_dir) eq 'desc' ? 'desc' : 'asc';

sub build_users_url {
  my (%opts) = @_;
  my @parts;
  for my $k (qw(faculty_id department_id group_id sort_by sort_dir)) {
    next if !defined $opts{$k} || $opts{$k} eq '';
    my $v = html_escape($opts{$k});
    push @parts, "$k=$v";
  }
  my $qs = join('&', @parts);
  return '/cgi-bin/users.pl' . ($qs ? "?$qs" : '');
}

sub sortable_header_link {
  my (%opts) = @_;
  my $label    = $opts{label} // '';
  my $column   = $opts{column} // '';
  my $active   = ($sort_by eq $column);
  my $next_dir = ($active && $sort_dir eq 'asc') ? 'desc' : 'asc';
  my $arrow    = $active ? ($sort_dir eq 'asc' ? ' ▲' : ' ▼') : '';
  my $href = build_users_url(
    faculty_id    => $faculty_id,
    department_id => $department_id,
    group_id      => $group_id,
    sort_by       => $column,
    sort_dir      => $next_dir,
  );
  return qq{<a href="$href">$label$arrow</a>};
}

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
} elsif ($department_id eq '') {
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $departments = DB::list_departments_by_faculty($t, $faculty_id);
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  my $items = '';
  for my $d (@$departments) {
    my $did = html_escape($d->{id});
    my $dname = html_escape($d->{name});
    $items .= qq{<li><a class="btn" href="/cgi-bin/users.pl?faculty_id=$faculty_id&department_id=$did">$dname</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Шаг 2: факультет <span class="pill">$fname</span>. Выберите кафедру.</p>
  <ol class="toc">$items</ol>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl">Назад к факультетам</a>
  </div>
</section>
HTML
} elsif ($group_id eq '') {
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $department = DB::get_department($t, $department_id);
  my $groups = DB::list_groups_by_department($t, $department_id);
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  my $dname = html_escape($department ? $department->{name} : "ID $department_id");
  my $items = '';
  for my $g (@$groups) {
    my $gid = html_escape($g->{id});
    my $gname = html_escape($g->{name});
    $items .= qq{<li><a class="btn" href="/cgi-bin/users.pl?faculty_id=$faculty_id&department_id=$department_id&group_id=$gid">$gname</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Шаг 3: факультет <span class="pill">$fname</span>, кафедра <span class="pill">$dname</span>. Выберите группу.</p>
  <ol class="toc">$items</ol>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl?faculty_id=$faculty_id">Назад к выбору кафедры</a>
    <a href="/cgi-bin/users.pl">Назад к факультетам</a>
  </div>
</section>
HTML
} else {
  my $group = DB::get_group($t, $group_id);
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $department = DB::get_department($t, $department_id);
  my $users = DB::list_users_by_group($t, $group_id, $sort_by, $sort_dir);

  my $rows = '';
  for my $u (@$users) {
    my $name = html_escape($u->{full_name});
    my $role = html_escape($u->{role});
    my $email = html_escape($u->{email});
    my $id = html_escape($u->{id});
    my $activity = html_escape($u->{content_count} // 0);
    $rows .= <<"HTML";
<tr>
  <td><a href="/cgi-bin/user.pl?id=$id" style="text-decoration:none; color:white">$name</a></td>
  <td>$role</td>
  <td>$email</td>
  <td>$activity</td>
</tr>
HTML
  }

  my $gname = html_escape($group ? $group->{name} : "ID $group_id");
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  my $dname = html_escape($department ? $department->{name} : "ID $department_id");
  my $name_header = sortable_header_link(label => 'ФИО', column => 'name');
  my $role_header = sortable_header_link(label => 'Роль', column => 'role');
  my $email_header = sortable_header_link(label => 'Email', column => 'email');
  my $activity_header = sortable_header_link(label => 'Активность', column => 'activity');

  $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Факультет: <span class="pill">$fname</span>, кафедра: <span class="pill">$dname</span>, группа: <span class="pill">$gname</span>.</p>

  <table>
    <thead>
      <tr>
        <th>$name_header</th>
        <th>$role_header</th>
        <th>$email_header</th>
        <th>$activity_header</th>
      </tr>
    </thead>
    <tbody>
      $rows
    </tbody>
  </table>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/users.pl?faculty_id=$faculty_id&department_id=$department_id">Назад к выбору группы</a>
    <a href="/cgi-bin/users.pl?faculty_id=$faculty_id">Назад к выбору кафедры</a>
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

