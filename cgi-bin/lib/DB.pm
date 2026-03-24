package DB;
use strict;
use warnings;
use utf8;
use DBI;

# Таблицы (по актуальной схеме):
# faculty(id, name)
# department(id, name, faculty_id)
# group(id, name, faculty_id, department_id)
# users(id, login, full_name, role, email, groupid, content_count)
# shedule(group_id PRIMARY KEY, text, updated_at)
# sessions(token, user_id, created_at)
# logs(id, user_id, action, details, created_at)
# content_type(id, usersid, type)
# news(..., Content_typeusersid, Content_typeid)
# photos(..., Content_typeusersid, Content_typeid)

sub _sqlite_path {
  my $root = $ENV{APP_DATA_DIR} // 'data';
  return "$root/app.sqlite";
}

sub _connect {
  my $path = _sqlite_path();
  my $dbh = DBI->connect("dbi:SQLite:dbname=$path", "", "", {
    RaiseError    => 1,
    AutoCommit    => 1,
    sqlite_unicode=> 1,
  }) or die $DBI::errstr;
  return $dbh;
}

sub open_all {
  my $dbh = _connect();
  _ensure_schema($dbh);
  _seed_if_needed($dbh);
  _recalculate_content_counts($dbh);
  return $dbh;
}

sub close_all {
  my ($dbh) = @_;
  $dbh->disconnect if $dbh;
}

sub _ensure_schema {
  my ($dbh) = @_;
  $dbh->do(q{CREATE TABLE IF NOT EXISTS faculty(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS department(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    faculty_id INTEGER NOT NULL
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS "group"(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    faculty_id INTEGER NOT NULL,
    department_id INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS users(
    id TEXT PRIMARY KEY,
    login TEXT,
    full_name TEXT,
    role TEXT,
    email TEXT,
    groupid INTEGER,
    content_count INTEGER DEFAULT 0
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS news(
    id TEXT PRIMARY KEY,
    title TEXT, body TEXT, image TEXT,
    author_id TEXT, created_at INTEGER,
    Content_typeusersid TEXT,
    Content_typeid INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS photos(
    id TEXT PRIMARY KEY,
    title TEXT, url TEXT, author_id TEXT, created_at INTEGER,
    Content_typeusersid TEXT,
    Content_typeid INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS content_type(
    id INTEGER PRIMARY KEY,
    usersid TEXT NOT NULL,
    type INTEGER NOT NULL
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS logs(
    id TEXT PRIMARY KEY,
    user_id TEXT, action TEXT, details TEXT, created_at INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS sessions(
    token TEXT PRIMARY KEY,
    user_id TEXT, created_at INTEGER
  )});

  $dbh->do(q{CREATE TABLE IF NOT EXISTS shedule(
    group_id INTEGER PRIMARY KEY,
    text TEXT, updated_at INTEGER
  )});


  my $has_groupid = 0;
  my $cols = $dbh->selectall_arrayref(q{PRAGMA table_info(users)}, { Slice => {} });
  for my $c (@$cols) {
    if (($c->{name} // '') eq 'groupid') {
      $has_groupid = 1;
      last;
    }
  }
  if (!$has_groupid) {
    $dbh->do(q{ALTER TABLE users ADD COLUMN groupid INTEGER});
  }
  my $has_content_count = 0;
  for my $c (@$cols) {
    if (($c->{name} // '') eq 'content_count') {
      $has_content_count = 1;
      last;
    }
  }
  if (!$has_content_count) {
    $dbh->do(q{ALTER TABLE users ADD COLUMN content_count INTEGER DEFAULT 0});
  }

  my $group_cols = $dbh->selectall_arrayref(q{PRAGMA table_info("group")}, { Slice => {} });
  my %have_group_col = map { ($_->{name} // '') => 1 } @$group_cols;
  if (!$have_group_col{department_id}) {
    $dbh->do(q{ALTER TABLE "group" ADD COLUMN department_id INTEGER});
  }

  # Миграция старых news/photos без ссылок на content_type
  my %required_news_cols = map { $_ => 1 } qw(Content_typeusersid Content_typeid);
  my %required_photo_cols = map { $_ => 1 } qw(Content_typeusersid Content_typeid);
  my $news_cols = $dbh->selectall_arrayref(q{PRAGMA table_info(news)}, { Slice => {} });
  my $photo_cols = $dbh->selectall_arrayref(q{PRAGMA table_info(photos)}, { Slice => {} });
  my %have_news = map { ($_->{name} // '') => 1 } @$news_cols;
  my %have_photo = map { ($_->{name} // '') => 1 } @$photo_cols;

  if (!$have_news{Content_typeusersid}) {
    $dbh->do(q{ALTER TABLE news ADD COLUMN Content_typeusersid TEXT});
  }
  if (!$have_news{Content_typeid}) {
    $dbh->do(q{ALTER TABLE news ADD COLUMN Content_typeid INTEGER});
  }
  if (!$have_photo{Content_typeusersid}) {
    $dbh->do(q{ALTER TABLE photos ADD COLUMN Content_typeusersid TEXT});
  }
  if (!$have_photo{Content_typeid}) {
    $dbh->do(q{ALTER TABLE photos ADD COLUMN Content_typeid INTEGER});
  }

  _ensure_departments_for_existing_groups($dbh);
}

sub _seed_if_needed {
  my ($dbh) = @_;
  my ($fac_count) = $dbh->selectrow_array(q{SELECT COUNT(1) FROM faculty});
  return if ($fac_count // 0) > 0;

  my $now = time();

  $dbh->do(q{DELETE FROM logs});
  $dbh->do(q{DELETE FROM sessions});
  $dbh->do(q{DELETE FROM news});
  $dbh->do(q{DELETE FROM photos});
  $dbh->do(q{DELETE FROM users});
  $dbh->do(q{DELETE FROM shedule});
  $dbh->do(q{DELETE FROM content_type});
  $dbh->do(q{DELETE FROM "group"});
  $dbh->do(q{DELETE FROM department});
  $dbh->do(q{DELETE FROM faculty});

  my $ins_faculty = $dbh->prepare(q{INSERT OR REPLACE INTO faculty(id,name) VALUES (?,?)});
  $ins_faculty->execute(1, 'Факультет информатики');
  $ins_faculty->execute(2, 'Факультет экономики');

  # Departments: внутри факультетов
  my $ins_department = $dbh->prepare(q{
    INSERT OR REPLACE INTO department(id,name,faculty_id) VALUES (?,?,?)
  });
  $ins_department->execute(1, 'Кафедра программной инженерии', 1);
  $ins_department->execute(2, 'Кафедра информационных систем', 1);
  $ins_department->execute(3, 'Кафедра финансов', 2);

  # Groups: внутри кафедр
  my $ins_group = $dbh->prepare(q{
    INSERT OR REPLACE INTO "group"(id,name,faculty_id,department_id) VALUES (?,?,?,?)
  });
  $ins_group->execute(1, 'ПИ-21', 1, 1);
  $ins_group->execute(2, 'ПИ-22', 1, 2);
  $ins_group->execute(3, 'ЭК-11', 2, 3);

  # Users: в каждой группе 1 староста + 3 студента
  my $ins_user = $dbh->prepare(q{
    INSERT OR REPLACE INTO users(id,login,full_name,role,email,groupid) VALUES (?,?,?,?,?,?)
  });

  # ПИ-21
  $ins_user->execute('u_pi21_head','pi21_head','Иванов Иван','староста','ivanov.pi21@example.com',1);
  $ins_user->execute('u_pi21_s1','pi21_s1','Петров Пётр','студент','petrov.pi21@example.com',1);
  $ins_user->execute('u_pi21_s2','pi21_s2','Сидорова Анна','студент','sidorova.pi21@example.com',1);
  $ins_user->execute('u_pi21_s3','pi21_s3','Кузнецов Артём','студент','kuznetsov.pi21@example.com',1);

  # ПИ-22
  $ins_user->execute('u_pi22_head','pi22_head','Орлова Мария','староста','orlova.pi22@example.com',2);
  $ins_user->execute('u_pi22_s1','pi22_s1','Смирнов Егор','студент','smirnov.pi22@example.com',2);
  $ins_user->execute('u_pi22_s2','pi22_s2','Николаева Ольга','студент','nikolaeva.pi22@example.com',2);
  $ins_user->execute('u_pi22_s3','pi22_s3','Васильев Илья','студент','vasilyev.pi22@example.com',2);

  # ЭК-11
  $ins_user->execute('u_ek11_head','ek11_head','Соколова Елена','староста','sokolova.ek11@example.com',3);
  $ins_user->execute('u_ek11_s1','ek11_s1','Фёдоров Никита','студент','fedorov.ek11@example.com',3);
  $ins_user->execute('u_ek11_s2','ek11_s2','Павлова Дарья','студент','pavlova.ek11@example.com',3);
  $ins_user->execute('u_ek11_s3','ek11_s3','Воронов Максим','студент','voronov.ek11@example.com',3);

  # Content types:
  # type=1 -> news, type=2 -> photo
  my $ins_ct = $dbh->prepare(q{
    INSERT OR REPLACE INTO content_type(id,usersid,type) VALUES (?,?,?)
  });
  $ins_ct->execute(1, 'u_pi21_head', 1);
  $ins_ct->execute(2, 'u_ek11_head', 1);
  $ins_ct->execute(3, 'u_pi21_s1', 2);
  $ins_ct->execute(4, 'u_pi22_s2', 2);

  # News
  my $ins_news = $dbh->prepare(q{
    INSERT OR REPLACE INTO news(
      id,title,body,image,author_id,created_at,Content_typeusersid,Content_typeid
    ) VALUES (?,?,?,?,?,?,?,?)
  });
  $ins_news->execute(
    'n1',
    'Старт учебного семестра',
    'Добро пожаловать на сайт студенческой группы! Здесь будут публиковаться новости и объявления.',
    '/assets/group-photo.svg',
    'u_pi21_head',
    $now,
    'u_pi21_head',
    1
  );
  $ins_news->execute(
    'n2',
    'Подготовка к сессии',
    'Староста напоминает о консультациях перед экзаменами. Подробности уточняйте у преподавателей.',
    '/assets/logo.svg',
    'u_ek11_head',
    $now - 86400,
    'u_ek11_head',
    2
  );

  # Photos
  my $ins_photo = $dbh->prepare(q{
    INSERT OR REPLACE INTO photos(
      id,title,url,author_id,created_at,Content_typeusersid,Content_typeid
    ) VALUES (?,?,?,?,?,?,?)
  });
  $ins_photo->execute('p1','Фото группы ПИ-21','/assets/group-photo.svg','u_pi21_s1',$now-40000,'u_pi21_s1',3);
  $ins_photo->execute('p2','Логотип группы','/assets/logo.svg','u_pi22_s2',$now-80000,'u_pi22_s2',4);

  # Shedule (по группе)
  my $ins_sched = $dbh->prepare(q{INSERT OR REPLACE INTO shedule(group_id,text,updated_at) VALUES (?,?,?)});
  $ins_sched->execute(1, "ПИ-21\nПн: Математика, Программирование\nВт: Английский\nСр: Базы данных", $now);
  $ins_sched->execute(2, "ПИ-22\nПн: Алгоритмы, ООП\nСр: Сети\nПт: Инженерия ПО", $now);
  $ins_sched->execute(3, "ЭК-11\nПн: Микроэкономика\nВт: Макроэкономика\nЧт: Статистика", $now);

  _recalculate_content_counts($dbh);
}

sub _ensure_departments_for_existing_groups {
  my ($dbh) = @_;

  my ($dep_count) = $dbh->selectrow_array(q{SELECT COUNT(1) FROM department});
  return if ($dep_count // 0) > 0;

  my $faculties = $dbh->selectall_arrayref(q{
    SELECT id, name
    FROM faculty
    ORDER BY id
  }, { Slice => {} });

  my %default_dep_for_faculty;
  my $next_dep_id = 1;
  for my $f (@$faculties) {
    my $dep_name = 'Кафедра по умолчанию';
    $dbh->do(q{
      INSERT OR REPLACE INTO department(id,name,faculty_id) VALUES (?,?,?)
    }, undef, $next_dep_id, $dep_name, $f->{id});
    $default_dep_for_faculty{$f->{id}} = $next_dep_id;
    $next_dep_id++;
  }

  for my $faculty_id (keys %default_dep_for_faculty) {
    $dbh->do(q{
      UPDATE "group"
      SET department_id=?
      WHERE faculty_id=? AND (department_id IS NULL OR department_id=0)
    }, undef, $default_dep_for_faculty{$faculty_id}, $faculty_id);
  }
}

sub _recalculate_content_counts {
  my ($dbh) = @_;
  $dbh->do(q{
    UPDATE users
    SET content_count =
      COALESCE((SELECT COUNT(1) FROM news n WHERE n.author_id = users.id), 0) +
      COALESCE((SELECT COUNT(1) FROM photos p WHERE p.author_id = users.id), 0)
  });
}

sub _ensure_content_type {
  my ($dbh, $usersid, $type) = @_;
  my ($ctid) = $dbh->selectrow_array(q{
    SELECT id FROM content_type WHERE usersid=? AND type=? LIMIT 1
  }, undef, $usersid, $type);
  if (defined $ctid) {
    return $ctid;
  }
  my ($max_id) = $dbh->selectrow_array(q{SELECT COALESCE(MAX(id),0) FROM content_type});
  my $new_id = ($max_id // 0) + 1;
  $dbh->do(q{
    INSERT INTO content_type(id,usersid,type) VALUES (?,?,?)
  }, undef, $new_id, $usersid, $type);
  return $new_id;
}

# ---------- Факультеты / группы ----------

sub list_faculties {
  my ($dbh) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id, name FROM faculty ORDER BY name
  }, { Slice => {} });
}

sub get_faculty {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id, name FROM faculty WHERE id=?
  }, undef, $id);
}

sub list_departments_by_faculty {
  my ($dbh, $faculty_id) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id, name, faculty_id
    FROM department
    WHERE faculty_id=?
    ORDER BY name
  }, { Slice => {} }, $faculty_id);
}

sub get_department {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id, name, faculty_id
    FROM department
    WHERE id=?
  }, undef, $id);
}

sub list_groups_by_faculty {
  my ($dbh, $faculty_id) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id, name, faculty_id, department_id
    FROM "group"
    WHERE faculty_id=?
    ORDER BY name
  }, { Slice => {} }, $faculty_id);
}

sub list_groups_by_department {
  my ($dbh, $department_id) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id, name, faculty_id, department_id
    FROM "group"
    WHERE department_id=?
    ORDER BY name
  }, { Slice => {} }, $department_id);
}

sub get_group {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id, name, faculty_id, department_id
    FROM "group"
    WHERE id=?
  }, undef, $id);
}

# ---------- Пользователи ----------

sub list_users {
  my ($dbh) = @_;
  my $rows = $dbh->selectall_arrayref(q{
    SELECT id,login,full_name,role,email,groupid,COALESCE(content_count,0) AS content_count
    FROM users
    ORDER BY full_name
  }, { Slice => {} });
  return $rows;
}

sub list_users_by_group {
  my ($dbh, $group_id, $sort_by, $sort_dir) = @_;
  $sort_by  = defined $sort_by  ? $sort_by  : '';
  $sort_dir = defined $sort_dir ? lc $sort_dir : '';
  $sort_dir = $sort_dir eq 'desc' ? 'DESC' : 'ASC';

  my %sort_map = (
    name     => 'u.full_name COLLATE NOCASE',
    role     => 'u.role COLLATE NOCASE',
    email    => 'u.email COLLATE NOCASE',
    activity => 'u.content_count',
  );

  my $order_sql;
  if ($sort_map{$sort_by}) {
    $order_sql = "$sort_map{$sort_by} $sort_dir, u.full_name COLLATE NOCASE ASC";
  } else {
    $order_sql = "CASE WHEN u.role='староста' THEN 0 ELSE 1 END ASC, u.full_name COLLATE NOCASE ASC";
  }

  my $sql = qq{
    SELECT
      u.id, u.login, u.full_name, u.role, u.email, u.groupid, COALESCE(u.content_count,0) AS content_count
    FROM users u
    WHERE u.groupid=?
    ORDER BY $order_sql
  };
  my $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, $group_id);
  return $rows;
}

sub get_user {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email,groupid,COALESCE(content_count,0) AS content_count
    FROM users
    WHERE id=?
  }, undef, $id);
}

sub find_user_by_login {
  my ($dbh, $login) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email,groupid,COALESCE(content_count,0) AS content_count
    FROM users
    WHERE login=?
  }, undef, $login);
}

sub find_user_by_email {
  my ($dbh, $email) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email,groupid,COALESCE(content_count,0) AS content_count
    FROM users
    WHERE email=?
  }, undef, $email);
}

# ---------- Новости ----------

sub list_news {
  my ($dbh) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id,title,body,image,author_id,created_at
    FROM news
    ORDER BY created_at DESC
  }, { Slice => {} });
}

sub list_news_by_author {
  my ($dbh, $author_id) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id,title,body,image,author_id,created_at
    FROM news
    WHERE author_id=?
    ORDER BY created_at DESC
  }, { Slice => {} }, $author_id);
}

sub get_news {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,title,body,image,author_id,created_at FROM news WHERE id=?
  }, undef, $id);
}

sub add_news {
  my ($dbh, $title, $body, $image, $author_id) = @_;
  my $id = 'n' . time() . int(rand(1000));
  my $now = time();
  my $ctid = _ensure_content_type($dbh, $author_id, 1);
  $dbh->do(q{
    INSERT INTO news(
      id,title,body,image,author_id,created_at,Content_typeusersid,Content_typeid
    ) VALUES(?,?,?,?,?,?,?,?)
  }, undef, $id, $title, $body, $image, $author_id, $now, $author_id, $ctid);
  _recalculate_content_counts($dbh);
  return $id;
}

# ---------- Галерея ----------

sub list_photos {
  my ($dbh) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id,title,url,author_id,created_at
    FROM photos
    ORDER BY created_at DESC
  }, { Slice => {} });
}

sub list_photos_by_author {
  my ($dbh, $author_id) = @_;
  return $dbh->selectall_arrayref(q{
    SELECT id,title,url,author_id,created_at
    FROM photos
    WHERE author_id=?
    ORDER BY created_at DESC
  }, { Slice => {} }, $author_id);
}

sub add_photo {
  my ($dbh, $title, $url, $author_id) = @_;
  my $id = 'p' . time() . int(rand(1000));
  my $now = time();
  my $ctid = _ensure_content_type($dbh, $author_id, 2);
  $dbh->do(q{
    INSERT INTO photos(
      id,title,url,author_id,created_at,Content_typeusersid,Content_typeid
    ) VALUES(?,?,?,?,?,?,?)
  }, undef, $id, $title, $url, $author_id, $now, $author_id, $ctid);
  _recalculate_content_counts($dbh);
  return $id;
}

# ---------- Расписание ----------

sub get_schedule_by_group {
  my ($dbh, $group_id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT group_id, text, updated_at
    FROM shedule
    WHERE group_id=?
  }, undef, $group_id);
}

sub set_schedule_by_group {
  my ($dbh, $group_id, $text) = @_;
  my $now = time();
  $dbh->do(q{
    INSERT OR REPLACE INTO shedule(group_id,text,updated_at) VALUES(?,?,?)
  }, undef, $group_id, $text, $now);
}

# Совместимость со старым кодом (использовать не рекомендуется)
sub get_schedule {
  my ($dbh) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT group_id, text, updated_at
    FROM shedule
    ORDER BY group_id
    LIMIT 1
  });
}

sub set_schedule {
  my ($dbh, $text) = @_;
  my $first = get_schedule($dbh);
  my $gid = $first ? $first->{group_id} : 1;
  set_schedule_by_group($dbh, $gid, $text);
}

# ---------- Логи ----------

sub add_log {
  my ($dbh, $user_id, $action, $details) = @_;
  my $id = 'L' . time() . int(rand(1000));
  my $now = time();
  $dbh->do(q{
    INSERT INTO logs(id,user_id,action,details,created_at) VALUES(?,?,?,?,?)
  }, undef, $id, ($user_id // ''), ($action // ''), ($details // ''), $now);
  return $id;
}

# ---------- Сессии ----------

sub create_session {
  my ($dbh, $user_id, $token) = @_;
  my $now = time();
  $dbh->do(q{
    INSERT OR REPLACE INTO sessions(token,user_id,created_at) VALUES(?,?,?)
  }, undef, $token, $user_id, $now);
}

sub get_session_user_id {
  my ($dbh, $token) = @_;
  my ($uid) = $dbh->selectrow_array(q{
    SELECT user_id FROM sessions WHERE token=?
  }, undef, $token);
  return $uid;
}

sub delete_session {
  my ($dbh, $token) = @_;
  return unless defined $token;
  $dbh->do(q{DELETE FROM sessions WHERE token=?}, undef, $token);
}

1;

