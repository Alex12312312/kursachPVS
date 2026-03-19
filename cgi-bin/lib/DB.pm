package DB;
use strict;
use warnings;
use utf8;
use Fcntl qw(O_CREAT O_RDWR);
use DB_File qw($DB_HASH);
use Encode qw(encode decode);
use DBI;

# Таблицы:
# users       — пользователи (студенты группы)
#               поля (в pack): login, full_name, role, email
# news        — новости: title, body, image, author_id, created_at
# logs        — логи: user_id, action, details, created_at
# photos      — фотографии для галереи: title, url, author_id, created_at
# sessions    — сессии авторизации: user_id, created_at
# schedule    — актуальное расписание: text, updated_at

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
  return $dbh;
}

sub close_all {
  my ($dbh) = @_;
  $dbh->disconnect if $dbh;
}

sub _ensure_schema {
  my ($dbh) = @_;
  $dbh->do(q{CREATE TABLE IF NOT EXISTS users(
    id TEXT PRIMARY KEY,
    login TEXT,
    full_name TEXT,
    role TEXT,
    email TEXT
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS news(
    id TEXT PRIMARY KEY,
    title TEXT, body TEXT, image TEXT,
    author_id TEXT, created_at INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS photos(
    id TEXT PRIMARY KEY,
    title TEXT, url TEXT, author_id TEXT, created_at INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS logs(
    id TEXT PRIMARY KEY,
    user_id TEXT, action TEXT, details TEXT, created_at INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS sessions(
    token TEXT PRIMARY KEY,
    user_id TEXT, created_at INTEGER
  )});
  $dbh->do(q{CREATE TABLE IF NOT EXISTS schedule(
    key TEXT PRIMARY KEY,
    text TEXT, updated_at INTEGER
  )});
}

sub _seed_if_needed {
  my ($dbh) = @_;
  my ($users_count) = $dbh->selectrow_array(q{SELECT COUNT(1) FROM users});
  return if ($users_count // 0) > 0;

  my $now = time();

  # Users
  my $ins_user = $dbh->prepare(q{INSERT OR REPLACE INTO users(id,login,full_name,role,email) VALUES (?,?,?,?,?)});
  $ins_user->execute('u_starosta','starosta','Иванов Иван (староста)','староста','ivanov@example.com');
  $ins_user->execute('u_uchorg','uchorg','Петрова Анна (учорг)','учорг','petrova@example.com');
  $ins_user->execute('u_proforg','proforg','Сидоров Артём (профорг)','профорг','sidorov@example.com');
  $ins_user->execute('u_leader','leader','Кузнецова Мария (студлидер)','студлидер','kuz@example.com');
  $ins_user->execute('u_student1','stud1','Студент Один','студент','stud1@example.com');
  $ins_user->execute('u_student2','stud2','Студент Два','студент','stud2@example.com');

  # News
  my $ins_news = $dbh->prepare(q{INSERT OR REPLACE INTO news(id,title,body,image,author_id,created_at) VALUES (?,?,?,?,?,?)});
  $ins_news->execute('n1','Старт учебного семестра','Добро пожаловать на сайт студенческой группы! Здесь будут публиковаться новости и объявления.','/assets/group-photo.svg','u_starosta',$now);
  $ins_news->execute('n2','Подготовка к сессии','Староста напоминает о консультациях перед экзаменами. Подробности уточняйте у преподавателей.','/assets/logo.svg','u_uchorg',$now-86400);

  # Photos
  my $ins_photo = $dbh->prepare(q{INSERT OR REPLACE INTO photos(id,title,url,author_id,created_at) VALUES (?,?,?,?,?)});
  $ins_photo->execute('p1','Фото группы','/assets/group-photo.svg','u_leader',$now-40000);
  $ins_photo->execute('p2','Логотип группы','/assets/logo.svg','u_proforg',$now-80000);

  # Schedule
  my $ins_sched = $dbh->prepare(q{INSERT OR REPLACE INTO schedule(key,text,updated_at) VALUES (?,?,?)});
  $ins_sched->execute('current',"Пн: Математика, Программирование\nВт: Окно\nСр: Сети, Базы данных",$now);
}

sub _pack {
  my (@parts) = @_;
  return join('|', map { encode('UTF-8', $_ // '') } @parts);
}

sub _unpack {
  my ($s) = @_;
  $s //= '';
  my @parts = split /\|/, $s, -1;
  @parts = map { decode('UTF-8', $_, 1) } @parts;
  return @parts;
}

# ---------- Пользователи ----------

sub list_users {
  my ($dbh) = @_;
  my $rows = $dbh->selectall_arrayref(q{
    SELECT id,login,full_name,role,email FROM users ORDER BY full_name
  }, { Slice => {} });
  return $rows;
}

sub get_user {
  my ($dbh, $id) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email FROM users WHERE id=?
  }, undef, $id);
}

sub find_user_by_login {
  my ($dbh, $login) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email FROM users WHERE login=?
  }, undef, $login);
}

sub find_user_by_email {
  my ($dbh, $email) = @_;
  return $dbh->selectrow_hashref(q{
    SELECT id,login,full_name,role,email FROM users WHERE email=?
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
  $dbh->do(q{
    INSERT INTO news(id,title,body,image,author_id,created_at) VALUES(?,?,?,?,?,?)
  }, undef, $id, $title, $body, $image, $author_id, $now);
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

sub add_photo {
  my ($dbh, $title, $url, $author_id) = @_;
  my $id = 'p' . time() . int(rand(1000));
  my $now = time();
  $dbh->do(q{
    INSERT INTO photos(id,title,url,author_id,created_at) VALUES(?,?,?,?,?)
  }, undef, $id, $title, $url, $author_id, $now);
  return $id;
}

# ---------- Расписание ----------

sub get_schedule {
  my ($dbh) = @_;
  my $row = $dbh->selectrow_hashref(q{
    SELECT text, updated_at FROM schedule WHERE key='current'
  });
  return $row;
}

sub set_schedule {
  my ($dbh, $text) = @_;
  my $now = time();
  $dbh->do(q{
    INSERT OR REPLACE INTO schedule(key,text,updated_at) VALUES('current',?,?)
  }, undef, $text, $now);
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

