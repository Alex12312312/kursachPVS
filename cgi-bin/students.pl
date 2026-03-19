use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Util qw();
use DB qw();

print "Status: 302 Found\r\nLocation: /cgi-bin/users.pl\r\n\r\n";

