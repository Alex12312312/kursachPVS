use strict;
use warnings;
use utf8;

use Fcntl qw(O_RDONLY);
use DB_File qw($DB_HASH);
use Encode qw(decode);

my $have_sqlite = eval { require DBI; require DBD::SQLite; 1 };
if (!$have_sqlite) {
  die <<"EOM";
DBD::SQLite не найден. Установите модуль и повторите:

  cpan DBD::SQLite
или (если есть cpanm)
  cpanm DBD::SQLite

После установки запустите:
  perl tools\\export_to_sqlite.pl
EOM
}

use DBI ();

my $DATA_DIR = 'data';
my $sqlite_file = "$DATA_DIR/app.sqlite";

sub open_dbfile_hash {
  my ($path) = @_;
  my %h;
  tie %h, 'DB_File', $path, O_RDONLY, 0, $DB_HASH
    or die "Cannot open DB_File '$path': $!";
  return \%h;
}

sub unpack_utf8_list {
  my ($s) = @_;
  $s //= '';
  my @parts = split /\|/, $s, -1;
  @parts = map { decode('UTF-8', $_, 1) } @parts;
  return @parts;
}

sub run {
  my $dbh = DBI->connect("dbi:SQLite:dbname=$sqlite_file","","", {
    RaiseError => 1,
    AutoCommit => 0,
    sqlite_unicode => 1,
  });

  # Схема (простой и достаточный вариант)
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      login TEXT,
      full_name TEXT,
      role TEXT,
      email TEXT
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS news (
      id TEXT PRIMARY KEY,
      title TEXT,
      body TEXT,
      image TEXT,
      author_id TEXT,
      created_at INTEGER
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS photos (
      id TEXT PRIMARY KEY,
      title TEXT,
      url TEXT,
      author_id TEXT,
      created_at INTEGER
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS logs (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      action TEXT,
      details TEXT,
      created_at INTEGER
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id TEXT,
      created_at INTEGER
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS schedule (
      key TEXT PRIMARY KEY,
      text TEXT,
      updated_at INTEGER
    )
  });
  $dbh->do(q{
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  });

  # Очистим (idempotent экспорт)
  for my $tbl (qw(users news photos logs sessions schedule meta)) {
    $dbh->do("DELETE FROM $tbl");
  }

  # USERS
  if (-f "$DATA_DIR/users.db") {
    my $h = open_dbfile_hash("$DATA_DIR/users.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO users (id, login, full_name, role, email) VALUES (?,?,?,?,?)
    });
    for my $id (keys %$h) {
      my ($login, $full_name, $role, $email) = unpack_utf8_list($h->{$id});
      $sth->execute($id, $login, $full_name, $role, $email);
    }
    untie %$h;
  }

  # NEWS
  if (-f "$DATA_DIR/news.db") {
    my $h = open_dbfile_hash("$DATA_DIR/news.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO news (id, title, body, image, author_id, created_at) VALUES (?,?,?,?,?,?)
    });
    for my $id (keys %$h) {
      my ($title, $body, $image, $author_id, $created_at) = unpack_utf8_list($h->{$id});
      $sth->execute($id, $title, $body, $image, $author_id, 0 + ($created_at // 0));
    }
    untie %$h;
  }

  # PHOTOS
  if (-f "$DATA_DIR/photos.db") {
    my $h = open_dbfile_hash("$DATA_DIR/photos.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO photos (id, title, url, author_id, created_at) VALUES (?,?,?,?,?)
    });
    for my $id (keys %$h) {
      my ($title, $url, $author_id, $created_at) = unpack_utf8_list($h->{$id});
      $sth->execute($id, $title, $url, $author_id, 0 + ($created_at // 0));
    }
    untie %$h;
  }

  # LOGS
  if (-f "$DATA_DIR/logs.db") {
    my $h = open_dbfile_hash("$DATA_DIR/logs.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO logs (id, user_id, action, details, created_at) VALUES (?,?,?,?,?)
    });
    for my $id (keys %$h) {
      my ($user_id, $action, $details, $created_at) = unpack_utf8_list($h->{$id});
      $sth->execute($id, $user_id, $action, $details, 0 + ($created_at // 0));
    }
    untie %$h;
  }

  # SESSIONS
  if (-f "$DATA_DIR/sessions.db") {
    my $h = open_dbfile_hash("$DATA_DIR/sessions.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO sessions (token, user_id, created_at) VALUES (?,?,?)
    });
    for my $token (keys %$h) {
      my ($user_id, $created_at) = unpack_utf8_list($h->{$token});
      $sth->execute($token, $user_id, 0 + ($created_at // 0));
    }
    untie %$h;
  }

  # SCHEDULE
  if (-f "$DATA_DIR/schedule.db") {
    my $h = open_dbfile_hash("$DATA_DIR/schedule.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO schedule (key, text, updated_at) VALUES (?,?,?)
    });
    for my $key (keys %$h) {
      my ($text, $updated_at) = unpack_utf8_list($h->{$key});
      $sth->execute($key, $text, 0 + ($updated_at // 0));
    }
    untie %$h;
  }

  # META
  if (-f "$DATA_DIR/meta.db") {
    my $h = open_dbfile_hash("$DATA_DIR/meta.db");
    my $sth = $dbh->prepare(q{
      INSERT INTO meta (key, value) VALUES (?,?)
    });
    for my $key (keys %$h) {
      my ($value) = unpack_utf8_list($h->{$key});
      $sth->execute($key, $value);
    }
    untie %$h;
  }

  $dbh->commit;
  $dbh->disconnect;

  print "Exported to $sqlite_file successfully.\n";
}

run();

