use 5.010;
use strict;
use Socket;
use IO::Select;
use Carp;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Errno qw(EAGAIN EINTR EWOULDBLOCK);

sub logmsg { print "$0 $$: @_ at ", scalar localtime(), "\n" }
my $port  = 8888;
my $proto = getprotobyname("tcp");

socket(my $fd_server, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
setsockopt($fd_server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or die "setsockopt: $!";
bind($fd_server, sockaddr_in($port, INADDR_ANY)) or die "bind: $!";
listen($fd_server, SOMAXCONN) or  die "listen: $!";
logmsg "Server started on port $port";


my $select = IO::Select->new();

our %waiters;
sub wait_socket_readable {
    my ($fd, $cb) = @_;
    $select->add($fd);
    push @{ $waiters{$fd} }, $cb;
}

wait_socket_readable($fd_server, sub {
    my $paddr = accept(my $fd_client, $fd_server);
    my ($port, $iaddr) = sockaddr_in($paddr);
    my $name = gethostbyaddr($iaddr, AF_INET);
    logmsg "connection from $name [",inet_ntoa($iaddr), "] at port $port";

    autoflush $fd_client, 1;
    print $fd_client "Hello client!\n";

    wait_socket_readable($fd_client, sub {
        my $read = sysread($fd_client, my $buf, 1024);
        if ($read == 0) {
            $select->remove($fd_client);
            delete $waiters{$fd_client};
        } else {
            print "from [",inet_ntoa($iaddr), "] : ", $buf;
        }

    });
});

wait_socket_readable(\*STDIN, sub {
    my $read = sysread(\*STDIN, my $buf, 1024);
    if ($read) {
        print "from STDIN: ", $buf;
        if ($buf eq "exit\n") { exit 0;}

    }
});

our @deadlines;
our $now = time;
sub wait_timeout {
    my ($t, $cb) = @_;
    my $deadline = $now + $t;
    @deadlines = sort { $a->[0] <=> $b->[0] } @deadlines, [ $deadline, $cb ];
}

wait_timeout(30, sub {
    say scalar keys %waiters;
    my @save;
    my @all_fh = $select->handles();
    for my $fh (@all_fh) {

        if (($fh ne $fd_server) && ($fh ne \*STDIN)) {
            print $fh "Disconnect!\n";
            close($fh);
            $select->remove($fh);
            push @save, $fh;
        }
    }
    for my $fh (@save) {
        delete $waiters{$fh};
    }
    say scalar keys %waiters;
    say "\nThe socket was closed";
});

wait_timeout(20, sub {
    say "\nThe socket will be closed after 10 s";
});


my @ready_r;
my @ready_w;
my $timeout = 1;
my $line = "";
while (($line ne "exit\n")) {
    $now = time;
    @ready_r = $select->can_read($timeout);
    for my $fd (@ready_r) {
        for my $cb (@{ $waiters{$fd} }) {
            $cb->();
        }
    }
    my @exec;
    while ((@deadlines) && ($now > $deadlines[0][0])) {
        push @exec, shift(@deadlines);
    }
    for my $dl (@exec) {
        $dl->[1]->();
    }
}
