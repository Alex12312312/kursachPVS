use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw(html_escape page);
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

my $users = DB::list_users($t);

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

my $body = <<"HTML";
<section class="card">
  <h1>Список группы</h1>
  <p>Список студентов; при нажатии на строку — переход на личную страницу студента.</p>

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
</section>
HTML

print page(
  title => 'Список группы',
  body  => $body,
  auth_info => { user => $current_user },
);

DB::close_all($t);

