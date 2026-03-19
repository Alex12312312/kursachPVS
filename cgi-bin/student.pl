use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw();
use DB qw();

my $method = $ENV{REQUEST_METHOD} // 'GET';
my $params = {};

if ($method eq 'GET') {
  $params = Util::parse_params($ENV{QUERY_STRING} // '');
} elsif ($method eq 'POST') {
  my $len = int($ENV{CONTENT_LENGTH} // 0);
  my $raw = '';
  if ($len > 0) { read(STDIN, $raw, $len); }
  $params = Util::parse_params($raw);
}

my $id = $params->{id} // '';

print "Status: 302 Found\r\nLocation: /cgi-bin/user.pl?id=$id\r\n\r\n";

