use 5.016;
use strict;
use Socket;
use IO::Select;
my ($remote, $port, $iaddr, $paddr, $proto, $line);

$remote  = "localhost";
$port    = 8888;
$iaddr   = inet_aton($remote) or die "no host: $remote";
$paddr   = sockaddr_in($port, $iaddr);
$proto   = getprotobyname("tcp");

socket(SOCK, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
connect(SOCK, $paddr) or die "connect: $!";
say "port: $port";
autoflush SOCK 1;
$line ="";

my $select = IO::Select->new([\*STDIN, \*SOCK]);
our %waiters;
sub wait_socket_readable {
    my ($fd, $cb) = @_;
    $select->add($fd);
    push @{ $waiters{$fd} }, $cb;
}


wait_socket_readable(\*STDIN, sub {
    my $read = sysread(\*STDIN, my $buf, 1024);
    if ($read) {
        print "from STDIN: ", $buf;
        print SOCK $buf;
        if ($buf eq "exit\n") { exit 0;}
    }
});

wait_socket_readable(\*SOCK, sub {
    my $read = sysread(\*SOCK, my $buf, 1024);
    if ($read) {
        print "From socket: ", $buf;
    }

});

my @ready_r;
my $timeout = 1;
while (1) {
    @ready_r = $select->can_read($timeout);
    for my $fd (@ready_r) {
        for my $cb (@{ $waiters{$fd} }) {
            $cb->();
        }
    }
}
close (SOCK) or  die "close: $!";
exit(0);
