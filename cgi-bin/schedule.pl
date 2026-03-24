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
my $params;
if ($method eq 'POST') {
  my $len = int($ENV{CONTENT_LENGTH} // 0);
  my $raw = '';
  read(STDIN, $raw, $len) if $len > 0;
  $params = parse_params($raw);
} else {
  $params = parse_params($ENV{QUERY_STRING} // '');
}

my $faculty_id    = $params->{faculty_id} // '';
my $department_id = $params->{department_id} // '';
my $group_id      = $params->{group_id} // '';

if ($method eq 'POST') {
  my $text = $params->{schedule_text} // '';
  if ($current_user
      && $current_user->{role} eq 'староста'
      && $current_user->{groupid}
      && $group_id ne ''
      && $current_user->{groupid} == $group_id
      && $text ne '') {
    DB::set_schedule_by_group($t, $group_id, $text);
    DB::add_log($t, $current_user->{id}, 'schedule_updated', "group_id=$group_id");
  }
}

my $body = '';
if ($faculty_id eq '') {
  my $faculties = DB::list_faculties($t);
  my $items = '';
  for my $f (@$faculties) {
    my $id = html_escape($f->{id});
    my $name = html_escape($f->{name});
    $items .= qq{<li><a class="btn" href="/cgi-bin/schedule.pl?faculty_id=$id">$name</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Расписание</h1>
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
    $items .= qq{<li><a class="btn" href="/cgi-bin/schedule.pl?faculty_id=$faculty_id&department_id=$did">$dname</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Расписание</h1>
  <p>Шаг 2: факультет <span class="pill">$fname</span>. Выберите кафедру.</p>
  <ol class="toc">$items</ol>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/schedule.pl">Назад к факультетам</a>
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
    $items .= qq{<li><a class="btn" href="/cgi-bin/schedule.pl?faculty_id=$faculty_id&department_id=$department_id&group_id=$gid">$gname</a></li>};
  }
  $body = <<"HTML";
<section class="card">
  <h1>Расписание</h1>
  <p>Шаг 3: факультет <span class="pill">$fname</span>, кафедра <span class="pill">$dname</span>. Выберите группу.</p>
  <ol class="toc">$items</ol>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/schedule.pl?faculty_id=$faculty_id">Назад к выбору кафедры</a>
    <a href="/cgi-bin/schedule.pl">Назад к факультетам</a>
  </div>
</section>
HTML
} else {
  my $group = DB::get_group($t, $group_id);
  my $faculty = DB::get_faculty($t, $faculty_id);
  my $department = DB::get_department($t, $department_id);
  my $sched = DB::get_schedule_by_group($t, $group_id);
  my $text = $sched ? html_escape($sched->{text}) : 'Расписание для этой группы ещё не заполнено.';

  my $gname = html_escape($group ? $group->{name} : "ID $group_id");
  my $fname = html_escape($faculty ? $faculty->{name} : "ID $faculty_id");
  my $dname = html_escape($department ? $department->{name} : "ID $department_id");

  my $upload_block = '';
  if ($current_user
      && $current_user->{role} eq 'староста'
      && $current_user->{groupid}
      && $current_user->{groupid} == $group_id) {
    $upload_block = <<"HTML";
<section class="card" style="margin-top:16px">
  <h2>Обновить расписание</h2>
  <form method="post" action="/cgi-bin/schedule.pl">
    <input type="hidden" name="faculty_id" value="$faculty_id" />
    <input type="hidden" name="department_id" value="$department_id" />
    <input type="hidden" name="group_id" value="$group_id" />
    <div class="field">
      <label for="schedule_text">Текст расписания</label>
      <textarea id="schedule_text" name="schedule_text" required>$text</textarea>
    </div>
    <button class="btn" type="submit">Загрузить расписание</button>
  </form>
</section>
HTML
  }

  $body = <<"HTML";
<section class="card">
  <h1>Расписание</h1>
  <p>Факультет: <span class="pill">$fname</span>, кафедра: <span class="pill">$dname</span>, группа: <span class="pill">$gname</span>.</p>
  <pre class="muted" style="white-space:pre-wrap">$text</pre>
  <div class="anchors" style="margin-top:12px">
    <a href="/cgi-bin/schedule.pl?faculty_id=$faculty_id&department_id=$department_id">Назад к выбору группы</a>
    <a href="/cgi-bin/schedule.pl?faculty_id=$faculty_id">Назад к выбору кафедры</a>
    <a href="/cgi-bin/schedule.pl">Назад к факультетам</a>
  </div>
</section>
$upload_block
HTML
}

print page(
  title => 'Расписание',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

