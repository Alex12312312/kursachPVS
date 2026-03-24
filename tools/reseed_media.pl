use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../cgi-bin/lib";
use DBI;

$ENV{APP_DATA_DIR} //= "$FindBin::Bin/../data";
my $db_path = "$ENV{APP_DATA_DIR}/app.sqlite";

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path", "", "", {
  RaiseError => 1,
  AutoCommit => 1,
  sqlite_unicode => 1,
});

# Берем доступных пользователей: сначала старост, затем остальных
my $users = $dbh->selectall_arrayref(q{
  SELECT id, full_name, role
  FROM users
  ORDER BY CASE WHEN role='староста' THEN 0 ELSE 1 END, full_name
}, { Slice => {} });

die "No users found, cannot reseed media.\n" unless @$users;

my $author_news_1 = $users->[0]{id};
my $author_news_2 = $users->[1]{id} // $users->[0]{id};
my $author_photo_1 = $users->[2]{id} // $users->[0]{id};
my $author_photo_2 = $users->[3]{id} // $users->[1]{id} // $users->[0]{id};

my $now = time();

$dbh->do(q{DELETE FROM news});
$dbh->do(q{DELETE FROM photos});
$dbh->do(q{DELETE FROM content_type});

my $ins_ct = $dbh->prepare(q{
  INSERT INTO content_type(id, usersid, type) VALUES (?, ?, ?)
});
my $ins_news = $dbh->prepare(q{
  INSERT INTO news(
    id, title, body, image, author_id, created_at, Content_typeusersid, Content_typeid
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
});
my $ins_photo = $dbh->prepare(q{
  INSERT INTO photos(
    id, title, url, author_id, created_at, Content_typeusersid, Content_typeid
  ) VALUES (?, ?, ?, ?, ?, ?, ?)
});

# content_type: 1/2 для news, 3/4 для photos
$ins_ct->execute(1, $author_news_1, 1);
$ins_ct->execute(2, $author_news_2, 1);
$ins_ct->execute(3, $author_photo_1, 2);
$ins_ct->execute(4, $author_photo_2, 2);

$ins_news->execute(
  'n1',
  'Обновление расписания по группам',
  'На сайте доступен новый сценарий выбора: факультет -> группа -> расписание.',
  '/assets/group-photo.svg',
  $author_news_1,
  $now - 7200,
  $author_news_1,
  1
);
$ins_news->execute(
  'n2',
  'Добавлены новые учебные группы',
  'В базе представлены 2 факультета и 3 группы с распределением ролей студентов.',
  '/assets/logo.svg',
  $author_news_2,
  $now - 3600,
  $author_news_2,
  2
);

$ins_photo->execute(
  'p1',
  'Фото группы',
  '/assets/group-photo.svg',
  $author_photo_1,
  $now - 1800,
  $author_photo_1,
  3
);
$ins_photo->execute(
  'p2',
  'Логотип проекта',
  '/assets/logo.svg',
  $author_photo_2,
  $now - 900,
  $author_photo_2,
  4
);

 $dbh->do(q{
  UPDATE users
  SET content_count =
    COALESCE((SELECT COUNT(1) FROM news n WHERE n.author_id = users.id), 0) +
    COALESCE((SELECT COUNT(1) FROM photos p WHERE p.author_id = users.id), 0)
});

my ($ct_count) = $dbh->selectrow_array(q{SELECT COUNT(1) FROM content_type});
my ($n_count)  = $dbh->selectrow_array(q{SELECT COUNT(1) FROM news});
my ($p_count)  = $dbh->selectrow_array(q{SELECT COUNT(1) FROM photos});

print "Reseed completed: content_type=$ct_count, news=$n_count, photos=$p_count\n";

$dbh->disconnect;

