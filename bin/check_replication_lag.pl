#!/usr/bin/perl

use strict;
use warnings qw(all);

my $MASTER_DB=$ARGV[0] or die "call syntax $0 masterdb slavedb";
my $REPLICA_DB=$ARGV[1] or die "call syntax $0 masterdb slavedb";
my $CRON=$ARGV[2];
my $CRON_LIMIT=$ARGV[3];

my $pg_version = `psql -qAtX -h $MASTER_DB -c "SELECT (setting::numeric/10000)::int FROM pg_settings WHERE name='server_version_num'"`
    or die "ERROR: failed to check version, aborting";
my $lsn_current = $pg_version < 10 ? "pg_current_xlog_location" : "pg_current_wal_lsn";
my $lsn_received = $pg_version < 10 ? "pg_last_xlog_receive_location" : "pg_last_wal_receive_lsn";
my $master_pos = `psql -X -t -h $MASTER_DB -c 'SELECT $lsn_current()'`;
my $replica_pos = `psql -X -t -h $REPLICA_DB -c 'SELECT $lsn_received()'`;
$master_pos =~ s/^\s*(\S+)\s*$/$1/;
$replica_pos =~ s/^\s*(\S+)\s*$/$1/;

my $replay_delay = CalculateNumericalOffset($master_pos) - CalculateNumericalOffset($replica_pos);

if ($CRON and $CRON_LIMIT) {
    if ($replay_delay > $CRON_LIMIT) {
        print "ERROR: replication lag $MASTER_DB -> $REPLICA_DB is $replay_delay bytes\n";
    }
} else {
    print "$replay_delay\n";
}


sub CalculateNumericalOffset
{
    my $stringofs = shift;

    my @pieces = split /\//, $stringofs;
    die "Invalid offset: $stringofs" unless ($#pieces == 1);

    # First part is logid, second part is record offset
    return (hex("ffffffff") * hex($pieces[0])) + hex($pieces[1]);
}
