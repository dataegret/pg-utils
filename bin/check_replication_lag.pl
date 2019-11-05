#!/usr/bin/perl

use strict;
use warnings qw(all);

if ($#ARGV < 1) { Usage(); }

my ($MASTER,$REPLICA,$CRON,$LIMIT) = @ARGV;

if (defined($CRON)) {
  if (!defined($LIMIT)) { Usage(); }
  $LIMIT=GetBytes($LIMIT);
  if ($LIMIT < 0) { Usage(); }
}

my $pg_version = `psql -qAtX -h $MASTER -c "SELECT (setting::numeric/10000)::int FROM pg_settings WHERE name='server_version_num'" 2>&1`;
if ( $? ) { Abort("Failed to check PostgreSQL version of \"$MASTER\"", $pg_version); }

my $lsn_current = $pg_version < 10 ? "pg_current_xlog_location" : "pg_current_wal_lsn";
my $lsn_received = $pg_version < 10 ? "pg_last_xlog_receive_location" : "pg_last_wal_receive_lsn";

my $master_pos = `psql -qAtX -h $MASTER -c 'SELECT CASE WHEN pg_is_in_recovery() THEN $lsn_received() ELSE $lsn_current() END' 2>&1`;
if ( $? ) { Abort("Failed to get WAL position of \"$MASTER\"", $master_pos); }
chomp $master_pos;

my @R = split /,/, $REPLICA;
foreach my $R ( @R ) {
  my $replica_pos = `psql -qAtX -h $R -c 'SELECT CASE WHEN pg_is_in_recovery() THEN $lsn_received() ELSE NULL END' 2>&1`;
  if ( $? ) { Error("Failed to get WAL position of \"$R\"", $replica_pos); next; }
  chomp $replica_pos;

  if (length($replica_pos)) {
    my $lag = GetNumOffset($master_pos) - GetNumOffset($replica_pos);
    if ( $lag < 0 ) { $lag=0; }

    if ($CRON and $LIMIT) {
      if ($lag > $LIMIT) { Error("$MASTER -> $R lag is ".GetPretty($lag)); }
    } else {
      print "$MASTER -> $R lag is ".GetPretty($lag)."\n";
    }
  }
}


sub Error
{
  my ($error, $detail, $abort) = @_;
  print "ERROR: $error".( defined($abort) ? ", aborting" : "" )."\n";
  if ( length($detail) ) { $detail =~ s/^/> /msg; print $detail; }
  if ( $abort ) { exit(1); }
}
sub Abort
{
  my ($error, $detail) = @_;
  Error($error, $detail, 1);
}

sub Usage
{
  print "Usage: $0 <master> <replica>[,<replica2>[,…]] [<cron> <limit>],\n";
  print "where:\n";
  print "<master>                   - IP of the Master, typically localhost (can be cascaded replica)\n";
  print "<replica>[,<replica2>[,…]] - comma-separated list of replicas\n";
  print "<cron>                     - \"yes\" for limited (cron) output\n";
  print "<limit>                    - lag threshold, suffixes KB, MB or GB can be used, mandatory for cron output\n";
  exit(1);
}

sub GetNumOffset
{
  my $offset = shift;
  my @pieces = split /\//, $offset;

  # First part is logid, second part is record offset
  return (hex("ffffffff") * hex($pieces[0])) + hex($pieces[1]);
}

sub GetBytes
{
  my ($in, $pow) = (shift, 1);

  my $b = lc ( $in );
  if ($b =~ /b$/) { chop $b; }

  my $l = substr($b, -1);

  if ($l eq "k")        { $pow=1024; chop $b; }
  elsif ($l eq "m")     { $pow=1024*1024; chop $b; }
  elsif ($l eq "g")     { $pow=1024*1024*1024; chop $b; }
  elsif ($l !~ /[0-9]/) { return -1; }

  return $b = $b * $pow;
}

sub GetPretty
{
  my $bytes = $_[0];
  foreach ( '','KB','MB','GB','TB','PB' ) {
    return sprintf("%.2f", $bytes)."$_" if $bytes < 1024;
    $bytes /= 1024;
  }
}
