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
if ($method eq 'POST') {
  my $len = int($ENV{CONTENT_LENGTH} // 0);
  my $raw = '';
  read(STDIN, $raw, $len) if $len > 0;
  my $p = parse_params($raw);
  my $text = $p->{schedule_text} // '';

  if ($current_user && $current_user->{role} eq 'староста' && $text ne '') {
    DB::set_schedule($t, $text);
    DB::add_log($t, $current_user->{id}, 'schedule_updated', '');
  }
}

my $sched = DB::get_schedule($t);
my $text = $sched ? html_escape($sched->{text}) : 'Расписание ещё не заполнено.';

my $upload_block = '';
if ($current_user && $current_user->{role} eq 'староста') {
  $upload_block = <<"HTML";
<section class="card" style="margin-top:16px">
  <h2>Обновить расписание (для старосты)</h2>
  <form method="post" action="/cgi-bin/schedule.pl">
    <div class="field">
      <label for="schedule_text">Текст расписания (одна строка — один день)</label>
      <textarea id="schedule_text" name="schedule_text" required>$text</textarea>
    </div>
    <button class="btn" type="submit">Загрузить расписание</button>
  </form>
</section>
HTML
}

my $body = <<"HTML";
<section class="card">
  <h1>Расписание</h1>
  <pre class="muted" style="white-space:pre-wrap">$text</pre>
</section>
$upload_block
HTML

print page(
  title => 'Расписание',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

