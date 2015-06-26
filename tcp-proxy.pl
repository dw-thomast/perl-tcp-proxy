#!/usr/bin/perl
#
# Peteris Krumins (peter@catonmat.net)
# http://www.catonmat.net  --  good coders code, great reuse
#
# A simple TCP proxy that implements IP-based access control
# Currently the ports are hard-coded, and it proxies
# 0.0.0.0:1080 to localhost:55555.
#
# Written for the article "Turn any Linux computer into SOCKS5
# proxy in one command," which can be read here:
#
# http://www.catonmat.net/blog/linux-socks5-proxy
#

use warnings;
use strict;

use IO::Socket;
use IO::Select;
use Getopt::Long qw(:config no_ignore_case);

my $dest_host = '127.0.0.1';
my $dest_port = 55555;
my $local_port = 1080;
my $local_host = '0.0.0.0';
my $rbuffsize = 32 * 1024;
my @allowed_ips = ( '127.0.0.1' );
my $queue = 100;
my $ioset = IO::Select->new;
my %socket_map;
my %allowed;

my $debug = 0;

GetOptions(
    "dest-host|h=s" => \$dest_host,
    "dest-port|p=s" => \$dest_port,
    "local-host|H=s" => \$local_host,
    "local-port|P=s" => \$local_port,
    "allowed|i=s" => \@allowed_ips,
    "debug|d!" => \$debug,
    "read-buffer|r=s", \$rbuffsize,
    "queue|q=i", \$queue,
);

sub new_conn {
    my ($host, $port) = @_;
    return IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port
    ) || die "Unable to connect to $host:$port: $!";
}

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => $queue,
    ) || die "Unable to listen on $host:$port: $!";
}

sub new_connection {
    my $server = shift;
    my $client = $server->accept or return;
    my $client_ip = client_ip($client) or return;

    unless (client_allowed($client)) {
        print "Connection from $client_ip denied.\n" if $debug;
        $client->close;
        return;
    }
    print "Connection from $client_ip accepted.\n" if $debug;

    my $remote = new_conn($dest_host, $dest_port);

    $ioset->add($client);
    $ioset->add($remote);

    $socket_map{ $client->fileno() } = $remote;
    $socket_map{ $remote->fileno() } = $client;

    0
}

sub close_connection {
    my $client = shift;
    my $remote = $socket_map{ $client->fileno() };
    my $client_ip = client_ip( $remote ) || '<unknown>';

    if ($client_ip eq $dest_host) {
        # local connection closed
        $client_ip = client_ip( $client ) || '<unknown>';
    }
   
    $ioset->remove( $client );
    $ioset->remove( $remote );

    delete $socket_map{ $client->fileno() };
    delete $socket_map{ $remote->fileno() };

    $client->close;
    $remote->close;

    print "Connection from $client_ip closed.\n" if $debug;
}

sub client_ip {
    my $client = shift;
    my $addr = $client->peeraddr or return;
    return inet_ntoa($addr);
}

sub client_allowed {
    my $client = shift;
    my $client_ip = client_ip($client) or return;
    return exists $allowed{ $client_ip };
}

print "Starting a server on $local_host:$local_port ";
print "(proxy to $dest_host:$dest_port)\n";
%allowed = map { +"$_" => 1 } @allowed_ips;
my $server = new_server($local_host, $local_port);
$ioset->add($server);

while (1) {
    for my $socket ($ioset->can_read) {
        my $fno = $socket->fileno() or next;

        if ($socket == $server) {
            new_connection($server);
            next;
        }
        
        next unless exists $socket_map{ $fno };
        my $remote = $socket_map{ $fno };
        my $read = $socket->sysread(my $buffer, $rbuffsize);
        if ($read) {
            $remote->syswrite($buffer);
        } else {
            close_connection($socket);
        }
    }
}

