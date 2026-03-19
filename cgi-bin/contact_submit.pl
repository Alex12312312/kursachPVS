use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw();
use DB qw();

my $body = <<'HTML';
<section class="card">
  <h1>Форма отключена</h1>
  <p>Этот обработчик относился к старой версии проекта (до перехода на SQLite и новую структуру страниц).</p>
  <div class="anchors" style="margin-top:12px">
    <a class="btn" href="/">На главную</a>
    <a class="btn" href="/cgi-bin/users.pl">Список группы</a>
    <a class="btn" href="/cgi-bin/gallery.pl">Галерея</a>
  </div>
</section>
HTML

print Util::page(
  title => 'Форма отключена',
  body  => $body,
);

