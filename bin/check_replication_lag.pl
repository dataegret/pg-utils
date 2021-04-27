#!/usr/bin/perl

use strict;
use warnings qw(all);

if ( scalar(@ARGV) < 2 ) { Usage(); }

my ($MASTER,$REPLICA,$CRON,$LIMIT) = @ARGV;
my $PSQL="PGCONNECT_TIMEOUT=10 psql -qAtX";

if ( defined($CRON) ) {
  if ( !defined($LIMIT) ) { Usage(); }
  $LIMIT = GetBytes($LIMIT);
  if ( $LIMIT < 0 ) { Usage(); }
}

my $CONN;
($CONN, $MASTER) = &GetConn($MASTER);

my $pg_version = `$PSQL $CONN -c "SELECT (setting::numeric/10000)::int FROM pg_settings WHERE name='server_version_num'" 2>&1`;
if ( $? ) { Abort("Failed to check PostgreSQL version of \"$MASTER\"", $pg_version); }

my $lsn_current = $pg_version < 10 ? "pg_current_xlog_location()" : "pg_current_wal_lsn()";
my $lsn_received = $pg_version < 10 ? "greatest(pg_last_xlog_receive_location(), pg_last_xlog_replay_location())" : "greatest(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())";

my $master_pos = `$PSQL $CONN -c 'SELECT CASE WHEN pg_is_in_recovery() THEN $lsn_received ELSE $lsn_current END' 2>&1`;
if ( $? ) { Abort("Failed to get WAL position of \"$MASTER\"", $master_pos); }
chomp $master_pos;

my @R = split /,/, $REPLICA;
foreach my $R ( @R ) {
  my $lim = $LIMIT if defined($LIMIT);

  # Custom limit for replica
  if ( $R =~ /:[0-9]+[KkMmGg]?[Bb]$/ ) {
    (my $l = $R) =~ s/^.*://;
    $R =~ s/:[^:]*$//;
    $lim = GetBytes($l);
    if ( $lim < 0 ) {
      Error("Incorrect replica limit \"$lim\"");
      next;
    }
  }

  ($CONN, $R) = &GetConn($R);

  my $replica_pos = `$PSQL $CONN -c 'SELECT CASE WHEN pg_is_in_recovery() THEN $lsn_received ELSE NULL END' 2>&1`;
  if ( $? ) { Error("Failed to get WAL position of \"$R\"", $replica_pos); next; }
  chomp $replica_pos;

  if ( length($replica_pos) ) {
    my $lag = GetNumOffset($master_pos) - GetNumOffset($replica_pos);
    if ( $lag < 0 ) { $lag=0; }

    if ( $CRON and $LIMIT ) {
      if ( $lag > $lim ) { Error("$MASTER -> $R lag is ".GetPretty($lag)); }
    }
    else {
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
  print "Usage: $0 <master> <replica>[,<replica2>[,…]] [<be_quiet> <threshold>]\n";
  print "where:\n";
  print "<master>                   - address of the Master, typically localhost (can be cascaded replica),\n";
  print "<replica>[,<replica2>[,…]] - comma-separated list of replica addresses (see details below),\n";
  print "<be_quiet>                 - \"yes\" for limited output, the only lag reported is that above provided threshold (suitable for cron)\n";
  print "<threshold>                - lag threshold, suffixes KB, MB or GB can be used, mandatory in quiet mode\n\n";
  print "Master and replica address details:\n";
  print "- can be DNS name, FQDN or local alias,\n";
  print "- IPv4 address,\n";
  print "- IPv6 address, but make sure to use [] around IPv6 addresses, otherwise last group will be treated as port,\n";
  print "- it is possible to specify port after the address (any of the above) via colon, if necessary\n";
  print "- timeout will be reported if database cannot be reached within 10 seconds,\n";
  print "- replica (and only replica) can have it's own threshold specified via colon.\n";
  print "  In this case, though, it is mandatory to use suffix B, KB, MB or GB, otherwise it'll be treated as port.\n";
  print "  To specify threshold without port, use double colon before the threshold.\n\n";
  print "It is safe to specify master in the list of replicas, no lag will be reported.\nThis is handy, as exactly the same check can be deployed on all servers.\n";
  exit(1);
}

sub GetConn
{
  my $text = shift;

  my $port;

  # Strip trailing colons, if any
  $text =~ s/:+$//;

  # Has port
  if ( $text =~ /((?::))((?:[0-9]+))$/ ) {
    ($port = $text) =~ s/^.*://;
    $text =~ s/:[^:]*$//;
  }

  # Host has square brackets
  $text =~ s/^\[([^]]*)\]$/$1/ if ( $text =~ /^\[[^]]*\]$/ );

  return ("-h $text".(length($port // '') ? " -p $port" : ""), $text);
}

sub GetNumOffset
{
  my $offset = shift;
  my @pieces = split /\//, $offset;

  # First part is logid, second part is record offset
  return ( hex("ffffffff") * hex($pieces[0])) + hex($pieces[1] );
}

sub GetBytes
{
  my ($in, $pow) = (shift, 1);

  my $b = lc ( $in );
  if ( $b =~ /b$/ ) { chop $b; }

  my $l = substr($b, -1);

  if ( $l eq "k" )        { $pow = 1024; chop $b; }
  elsif ( $l eq "m" )     { $pow = 1024*1024; chop $b; }
  elsif ( $l eq "g" )     { $pow = 1024*1024*1024; chop $b; }
  elsif ( $l !~ /[0-9]/ ) { return -1; }

  return $b = $b * $pow;
}

sub GetPretty
{
  my $bytes = $_[0];
  foreach ( '', 'KB', 'MB', 'GB', 'TB', 'PB' ) {
    return sprintf("%.2f", $bytes)."$_" if $bytes < 1024;
    $bytes /= 1024;
  }
}
