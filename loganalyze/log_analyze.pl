#!/usr/bin/perl

use strict;
use warnings qw(all);
use Data::Dumper();

my $VERBOSE = 0;

my $MAX_OK_TIME = 600000; #ms

my $FILENAME=$ARGV[0] or die "call syntax $0 logfile";
open (IN, $FILENAME) || die "cannot open $FILENAME because $!";
warn "starting work with file $FILENAME\n" if ($VERBOSE);

my %queries_stat = ();
my @long_query   = ();
my @huge_query_line = ();

my $total_time   = 1;
my $total_queries = 1;
my $total_unique_queries = 1;

{
my ($time, $user, $db, $pid, $duration, $query);
my ($count, $lines) = (0, 0);

while (<IN>) {
	chomp;
	$count++;

	if (/^\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2}(?:\.\d+)?) \S+ (\d+) (\S*)@(\S*) from (?:\S*) \[vxid:.*? txid:\d+\] \[.*?\]\s*(.*)$/) {
		count_query($time, $user, $db, $pid, $duration, $query, $count) if ($count>1 and $lines>0);
		($time, $pid, $user, $db, $lines, $duration, $query) = ($1, $2, $3, $4, parse_log_line($5));
	} elsif (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \S+/) {
		die "cannot parse line '$_'\n";
		next;
	} elsif ($lines>0) {
		$query.="\n$_";
		$lines++;
		die "parser error lines>200000 before line $count" if ($lines>200000);
	} else {
#		print "skipped line $_\n";
	}
	#print STDERR "\r".$count;
}
}

sub parse_log_line {
	my $line = shift;
	#LOG:  duration: 2.067 ms  statement:  ...
	if ($line =~ /LOG:  duration: (\d+\.\d+) ms  (.*)$/) { 
		return(1, $1, $2);
	} else {
#		print "skipped header: '$_'\n";
		return (0, 0, '');
	}
}


print "===================================================================================================================\n\n\n";

my $pos = 0;
my $time_left = $total_time;
print "total time used: ".((int($total_time/36000))/100)." hours \n";
print "total unique queries found: ".scalar(keys(%queries_stat))."\n";
foreach (sort {$queries_stat{$b}{time} <=> $queries_stat{$a}{time}} keys %queries_stat) {
	$pos++;
	my $percent = 100*$queries_stat{$_}{time}/$total_time;
	last if ($percent<1);
	$time_left -= $queries_stat{$_}{time};
	print "\n\n\n\n===================================================\npos:$pos\ttotal_time: ".sprintf('%.02f',($queries_stat{$_}{time}/(3600*1000)))." h (".sprintf('%.02f', $percent)."%)\tavg_time:\t".sprintf('%.02f',($queries_stat{$_}{time}/$queries_stat{$_}{count}))."ms\n$_";
	print "\n\nSample (user=$queries_stat{$_}{user} db=$queries_stat{$_}{db}):\n$queries_stat{$_}{sample}\n";
}
print "\n\n other: ".int($time_left/100)." s (".sprintf('%.02f', ($time_left*100/$total_time))."%)\n";
print "====================================================================================================================\n\n\n";

$pos = 0;
my $count_left = $total_queries;
print "total queries found: $total_queries\n";
foreach (sort {$queries_stat{$b}{count} <=> $queries_stat{$a}{count}} keys %queries_stat) {
	$pos++;
	my $percent = 100*$queries_stat{$_}{count}/$total_queries;
	last if ($percent<2);
	$count_left -= $queries_stat{$_}{count};
	print "\n\n\n\n===================================================\npos:$pos\ttotal_count: $queries_stat{$_}{count} (".sprintf('%.02f', $percent)."%)\tavg_time:\t".sprintf('%.02f',($queries_stat{$_}{time}/$queries_stat{$_}{count}))."ms\n$_";
	print "\n\nSample (user=$queries_stat{$_}{user} db=$queries_stat{$_}{db}):\n$queries_stat{$_}{sample}\n";
}
print "\n\n other: ".int($count_left/100)." s (".sprintf('%.02f', ($count_left*100/$total_queries))."%)\n";
print "===================================================================================================================\n\n\n";

print "total long queries found: ".scalar(@long_query)."\n";
foreach (@long_query) {
	chomp;
	print "$_\n";
}
print "===================================================================================================================\n\n\n";

print "total huge queries found: ".scalar(@huge_query_line)."\n";
foreach (@huge_query_line) {
        chomp;
        print "'$_->[2]...' with length $_->[1] at line $_->[0]\n";
}
print "===================================================================================================================\n\n\n";

sub filter_query {
	my $string = shift;

	$string =~ s/^\s*--.*$//gm;
	$string =~ s/[\s\n\r\t]+/ /g;
	$string = lc($string);
	$string =~ s/^ //;
	$string =~ s/ $//;

	if ($string =~ /copy .* to stdout/) {
		return 'COPY to stdout (backup) queries';
	};

	$string =~ s/dbdpg_p\d+_\d+/dbdpg/g;
	$string =~ s/pdo_stmt_\d+/pdo_stmt/g;
	$string =~ s/(?:bind|execute|parse) \S+:/prepared:/g;
	$string =~ s/savepoint\s+.*$/SAVEPOINT/;
	$string =~ s/\/\*.*?\*\///g;

	$string =~ s/(::[a-z0-9]+)//g;

        $string =~ s/e?'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?'/TIMESTAMP/g;
        $string =~ s/e?'\d{4}-\d{2}-\d{2}'/DATE/g;
        $string =~ s/e?'[^']*?'/TEXT/g;

        $string =~ s/_\d{4}_\d{2}/YYYYMM/g;

        $string =~ s/\$\d+/PLACEHOLDER/g;

	$string =~ s/\[\s*\d+\s*\]/[SOMEARRAY]/g;

	$string =~ s/\((DIGIT|TEXT|PLACEHOLDER|null|false|true|DATE|TIMESTAMP)\)/$1/g;

	$string =~ s/(=|<>|\(|,|\+|-|<|>|\*|\/)\s*-?\d+(?:\.\d+)?/$1 DIGIT/g;
	$string =~ s/-?\d+(?:\.\d+)?\s*(=|<>|\)|,|\+|-|<|>|\*|\/)/DIGIT $1/g;

	$string =~ s/(?:\s*(?:DIGIT|TEXT|PLACEHOLDER|null|false|true|DATE|TIMESTAMP)\s*,){1,1000}/VALUES_LIST,/g;
	$string =~ s/\((?:\s*(?:VALUES_LIST|DIGIT|TEXT|PLACEHOLDER|null|false|true|DATE|TIMESTAMP)\s*,){0,1000}\s*(?:VALUES_LIST|DIGIT|TEXT|PLACEHOLDER|null|false|true|DATE|TIMESTAMP)\s*\)/(VALUES LIST)/g;
	$string =~ s/(insert into \S+) \(.*?\)/$1 (FIELD LIST)/g;
	$string =~ s/values\s+\(.*?\)/values (VALUES LIST)/g;
	$string =~ s/update (?:only )?(\S+) set .*? where/update $1 set SET_LIST where/g;
	$string =~ s/(limit|offset) \d+/$1 SOME/g;

	return $string;
}

sub count_query {
	my ($time, $user, $db, $pid, $duration, $orig_query, $count) = @_;
	die unless ($time && $user && $db && $pid && $duration && $orig_query);

	#skip too long queries
	if ($duration>$MAX_OK_TIME) {
		push @long_query, "too long query at $time worked: (".((int($duration/10))/100)." second):\n$orig_query";
	} elsif (length($orig_query) > 500000) { 
		push @huge_query_line, [$count, length($orig_query), sprintf('%.200s', $orig_query)]; 
	} else {
		my $query = "user=$user db=$db QUERY: ".filter_query($orig_query);
		$queries_stat{$query} ||= {time=>0, count=>0, sample=>$orig_query, user=>$user, db=>$db};

		if ($queries_stat{$query}{count}==0) {
			$total_unique_queries++; 
#			print "new query found:\n$query\noriginal query was\n$orig_query\n=================================================================\n\n";
			if ($VERBOSE and scalar(keys %queries_stat) > 500) {
				warn "new query found:\n$query\noriginal query was\n$orig_query\n=================================================================\n\n";
			}
		}

		$queries_stat{$query}{time} += $duration;
		$queries_stat{$query}{count}++;
		$total_time += $duration;
		$total_queries++;
	}
} 

