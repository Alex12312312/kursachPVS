use strict;
use warnings;
use utf8;

use IO::Socket::INET;
use IPC::Open3;
use Symbol qw(gensym);
use Cwd qw(abs_path);
use File::Spec;

my $HOST = '127.0.0.1';
my $PORT = 8081;

my $ROOT = abs_path('.');
my $WWW  = File::Spec->catdir($ROOT, 'www');
my $ASSETS = File::Spec->catdir($ROOT, 'assets');
my $CGI  = File::Spec->catdir($ROOT, 'cgi-bin');
my $DATA = File::Spec->catdir($ROOT, 'data');

my $server = IO::Socket::INET->new(
  LocalAddr => $HOST,
  LocalPort => $PORT,
  Proto     => 'tcp',
  Listen    => 10,
  Reuse     => 1,
) or die "Cannot start server on $HOST:$PORT: $!\n";

print "Server running at http://$HOST:$PORT/\n";
print "Press Ctrl+C to stop.\n";

while (my $client = $server->accept) {
  $client->autoflush(1);
  eval { handle_client($client) };
  close $client;
}

sub handle_client {
  my ($client) = @_;
  my $req = read_http_request($client);
  return unless $req;

  my $path = $req->{path};
  my $query = $req->{query};

  if ($path eq '/') {
    $path = '/cgi-bin/home.pl';
  }

  if ($path =~ m{^/cgi-bin/([^/?#]+\.pl)$}) {
    my $script = $1;
    my $script_path = File::Spec->catfile($CGI, $script);
    return http_404($client) unless -f $script_path;
    return run_cgi($client, $req, $script_path, $query);
  }

  if ($path =~ m{^/assets/(.+)$}) {
    return serve_file($client, File::Spec->catfile($ASSETS, safe_rel($1)));
  }

  my $file = File::Spec->catfile($WWW, safe_rel($path));
  return serve_file($client, $file);
}

sub read_http_request {
  my ($client) = @_;
  my $line = <$client>;
  return undef unless defined $line;
  $line =~ s/\r?\n\z//;
  my ($method, $target, $proto) = split / /, $line, 3;
  return undef unless $method && $target;

  my %h;
  while (my $l = <$client>) {
    last if $l eq "\r\n" || $l eq "\n";
    $l =~ s/\r?\n\z//;
    my ($k, $v) = split /:\s*/, $l, 2;
    next unless defined $k;
    $h{lc($k)} = $v // '';
  }

  my ($path, $query) = split /\?/, $target, 2;
  $path  //= '/';
  $query //= '';

  my $body = '';
  if (uc($method) eq 'POST') {
    my $len = int($h{'content-length'} // 0);
    if ($len > 0) {
      read($client, $body, $len);
    }
  }

  return {
    method => uc($method),
    path   => $path,
    query  => $query,
    proto  => $proto // 'HTTP/1.1',
    headers => \%h,
    body   => $body,
  };
}

sub safe_rel {
  my ($p) = @_;
  $p //= '';
  $p =~ s{\\}{/}g;
  $p =~ s{^/}{};
  $p =~ s{/\z}{};
  $p =~ s{\0}{}g;
  # вычищаем ".."
  my @parts = grep { $_ ne '' && $_ ne '.' && $_ ne '..' } split m{/+}, $p;
  return File::Spec->catfile(@parts);
}

sub serve_file {
  my ($client, $file) = @_;
  return http_404($client) unless -f $file;
  open my $fh, '<', $file or return http_500($client, "Cannot open file");
  binmode $fh;
  local $/;
  my $content = <$fh>;
  close $fh;

  my $ct = content_type($file);
  my $len = length($content);
  print $client "HTTP/1.1 200 OK\r\n";
  print $client "Content-Type: $ct\r\n";
  print $client "Content-Length: $len\r\n";
  print $client "Connection: close\r\n";
  print $client "\r\n";
  print $client $content;
}

sub content_type {
  my ($file) = @_;
  return 'text/html; charset=utf-8' if $file =~ /\.html\z/i;
  return 'text/css; charset=utf-8'  if $file =~ /\.css\z/i;
  return 'application/javascript; charset=utf-8' if $file =~ /\.js\z/i;
  return 'image/svg+xml' if $file =~ /\.svg\z/i;
  return 'image/png' if $file =~ /\.png\z/i;
  return 'image/jpeg' if $file =~ /\.jpe?g\z/i;
  return 'text/plain; charset=utf-8';
}

sub run_cgi {
  my ($client, $req, $script_path, $query) = @_;
  local %ENV = %ENV;
  $ENV{REQUEST_METHOD}  = $req->{method};
  $ENV{QUERY_STRING}    = $query // '';
  $ENV{CONTENT_LENGTH}  = length($req->{body} // '');
  $ENV{CONTENT_TYPE}    = $req->{headers}->{'content-type'} // 'application/x-www-form-urlencoded';
  $ENV{SCRIPT_NAME}     = $req->{path};
  $ENV{HTTP_COOKIE}     = $req->{headers}->{'cookie'} // '';
  $ENV{APP_DATA_DIR}    = $DATA;

  my $err = gensym;
  my $pid = open3(my $in, my $out, $err, 'perl', $script_path);

  print $in ($req->{body} // '');
  close $in;

  my $cgi_out = do { local $/; <$out> };
  close $out;
  my $cgi_err = do { local $/; <$err> };
  close $err;
  waitpid($pid, 0);

  if (($? >> 8) != 0) {
    return http_500($client, "CGI error:\n$cgi_err");
  }

  # CGI returns headers + blank line + body. We pass headers through.
  my ($headers, $body) = split /\r?\n\r?\n/, $cgi_out, 2;
  $headers //= "Content-Type: text/plain; charset=utf-8";
  $body //= '';

  my $status = '200 OK';
  if ($headers =~ /^Status:\s*(.+)\s*$/mi) {
    $status = $1;
    $headers =~ s/^Status:\s*.+\r?\n//mi;
  }

  my $len = length($body);
  print $client "HTTP/1.1 $status\r\n";
  print $client "$headers\r\n";
  print $client "Content-Length: $len\r\n";
  print $client "Connection: close\r\n";
  print $client "\r\n";
  print $client $body;
}

sub http_404 {
  my ($client) = @_;
  my $body = "<h1>404</h1><p>Not found</p>";
  print $client "HTTP/1.1 404 Not Found\r\n";
  print $client "Content-Type: text/html; charset=utf-8\r\n";
  print $client "Content-Length: " . length($body) . "\r\n";
  print $client "Connection: close\r\n\r\n";
  print $client $body;
}

sub http_500 {
  my ($client, $msg) = @_;
  $msg //= 'Internal Server Error';
  my $safe = $msg;
  $safe =~ s/&/&amp;/g; $safe =~ s/</&lt;/g; $safe =~ s/>/&gt;/g;
  my $body = "<h1>500</h1><pre>$safe</pre>";
  print $client "HTTP/1.1 500 Internal Server Error\r\n";
  print $client "Content-Type: text/html; charset=utf-8\r\n";
  print $client "Content-Length: " . length($body) . "\r\n";
  print $client "Connection: close\r\n\r\n";
  print $client $body;
}

