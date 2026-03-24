use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../cgi-bin/lib";
use lib "$FindBin::Bin/..";

use DB qw();

$ENV{APP_DATA_DIR} //= "$FindBin::Bin/../data";

my $dbh = DB::open_all();

# Очистим таблицы (idempotent)
for my $tbl (qw(logs sessions news photos content_type users shedule "group" department faculty)) {
  $dbh->do("DELETE FROM $tbl");
}

my $now = time();

my @faculties = (
  { id => 1, name => 'Факультет информатики' },
  { id => 2, name => 'Факультет экономики'   },
);

my @departments = (
  { id => 1, faculty_id => 1, name => 'Кафедра программной инженерии' },
  { id => 2, faculty_id => 1, name => 'Кафедра информационных систем' },
  { id => 3, faculty_id => 2, name => 'Кафедра финансов' },
);

my @groups = (
  { id => 1, faculty_id => 1, department_id => 1, name => 'ПИ-21' },
  { id => 2, faculty_id => 1, department_id => 1, name => 'ПИ-22' },
  { id => 3, faculty_id => 1, department_id => 2, name => 'ИС-21' },
  { id => 4, faculty_id => 1, department_id => 2, name => 'ИС-22' },
  { id => 5, faculty_id => 2, department_id => 3, name => 'ЭК-11' },
  { id => 6, faculty_id => 2, department_id => 3, name => 'ЭК-12' },
);

my $ins_faculty = $dbh->prepare(q{INSERT OR REPLACE INTO faculty(id,name) VALUES (?,?)});
for my $f (@faculties) {
  $ins_faculty->execute($f->{id}, $f->{name});
}

my $ins_department = $dbh->prepare(q{
  INSERT OR REPLACE INTO department(id,name,faculty_id) VALUES (?,?,?)
});
for my $d (@departments) {
  $ins_department->execute($d->{id}, $d->{name}, $d->{faculty_id});
}

my $ins_group = $dbh->prepare(q{
  INSERT OR REPLACE INTO "group"(id,name,faculty_id,department_id) VALUES (?,?,?,?)
});
for my $g (@groups) {
  $ins_group->execute($g->{id}, $g->{name}, $g->{faculty_id}, $g->{department_id});
}

# В каждой группе 4 студента: 1 староста + 3 обычных
my $ins_user = $dbh->prepare(q{
  INSERT OR REPLACE INTO users(id,login,full_name,role,email,groupid,content_count)
  VALUES (?,?,?,?,?,?,?)
});

my @created_users;
my $uid_seq = 1;
for my $g (@groups) {
  my $gid = $g->{id};
  my $gname = $g->{name};

  my $head_id = sprintf('u_g%02d_head', $gid);
  my $head_login = sprintf('g%02d_head', $gid);
  my $head_email = sprintf('g%02d.head@example.com', $gid);
  my $head_name = "Староста группы $gname";
  $ins_user->execute($head_id, $head_login, $head_name, 'староста', $head_email, $gid, 0);
  push @created_users, $head_id;

  for my $n (1..3) {
    my $sid = sprintf('u_g%02d_s%d', $gid, $n);
    my $slogin = sprintf('g%02d_s%d', $gid, $n);
    my $semail = sprintf('g%02d.s%d@example.com', $gid, $n);
    my $sname = sprintf('Студент %02d-%d (%s)', $uid_seq, $n, $gname);
    $ins_user->execute($sid, $slogin, $sname, 'студент', $semail, $gid, 0);
    push @created_users, $sid;
  }
  $uid_seq++;
}

# Один студент, у которого будет 4 новости
my $news_author = 'u_g01_s1';
my $photo_author1 = 'u_g02_s2';
my $photo_author2 = 'u_g05_head';

my $ins_ct = $dbh->prepare(q{
  INSERT OR REPLACE INTO content_type(id,usersid,type) VALUES (?,?,?)
});
$ins_ct->execute(1, $news_author, 1);   # news
$ins_ct->execute(2, $photo_author1, 2); # photo
$ins_ct->execute(3, $photo_author2, 2); # photo

my $ins_news = $dbh->prepare(q{
  INSERT OR REPLACE INTO news(
    id,title,body,image,author_id,created_at,Content_typeusersid,Content_typeid
  ) VALUES (?,?,?,?,?,?,?,?)
});
for my $i (1..4) {
  $ins_news->execute(
    "n$i",
    "Новость #$i от активного студента",
    "Материал новости #$i. Автор - студент группы ПИ-21.",
    ($i % 2 ? '/assets/group-photo.svg' : '/assets/logo.svg'),
    $news_author,
    $now - $i * 3600,
    $news_author,
    1
  );
}

my $ins_photo = $dbh->prepare(q{
  INSERT OR REPLACE INTO photos(
    id,title,url,author_id,created_at,Content_typeusersid,Content_typeid
  ) VALUES (?,?,?,?,?,?,?)
});
$ins_photo->execute('p1', 'Фото с мероприятия', '/assets/group-photo.svg', $photo_author1, $now - 5400, $photo_author1, 2);
$ins_photo->execute('p2', 'Логотип проекта', '/assets/logo.svg', $photo_author2, $now - 7200, $photo_author2, 3);

my $ins_sched = $dbh->prepare(q{
  INSERT OR REPLACE INTO shedule(group_id,text,updated_at) VALUES(?,?,?)
});
for my $g (@groups) {
  my $txt = "$g->{name}\nПн: Профильный предмет\nСр: Практика\nПт: Семинар";
  $ins_sched->execute($g->{id}, $txt, $now);
}

# Пара логов для примера
$dbh->do(q{
  INSERT OR REPLACE INTO logs(id,user_id,action,details,created_at) VALUES (?,?,?,?,?)
}, undef, 'L1','u_g01_head','login','Первый вход старосты', $now - 10_000);
$dbh->do(q{
  INSERT OR REPLACE INTO logs(id,user_id,action,details,created_at) VALUES (?,?,?,?,?)
}, undef, 'L2', $news_author,'news_submitted','Добавил 4 новости', $now - 9_000);

# Обновим users.content_count
$dbh->do(q{
  UPDATE users
  SET content_count =
    COALESCE((SELECT COUNT(1) FROM news n WHERE n.author_id = users.id), 0) +
    COALESCE((SELECT COUNT(1) FROM photos p WHERE p.author_id = users.id), 0)
});

DB::close_all($dbh);

print "Demo data seeded successfully.\n";

