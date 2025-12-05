#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp qw(tempfile);
use Time::HiRes qw(time);
use Getopt::Long qw(:config no_ignore_case bundling);

# Version
my $VERSION = '0.11.0';

# Configuration
my $MAX_LINE_LENGTH = 10000;
my $DEBUG = $ENV{DEBUG} || 0;

# Command line options
my $deep_search = 0;
my $partial_match = 0;
my $max_matches = 10000;
my $max_matches_size = 50 * 1024 * 1024;  # 50MB in bytes
my $live_output = 0;
my $show_version = 0;
my $show_help = 0;

# Global state for Ctrl+C handling
my $interrupted = 0;
my $temp_file;
my $matches_found = 0;

# Signal handlers
$SIG{INT} = sub {
    $interrupted = 1;
    print STDERR "\n\n[Interrupted by user - showing partial results...]\n";
};

$SIG{__DIE__} = sub {
    system("stty sane 2>/dev/null") if -t STDIN;
    die @_;
};

# Parse command line options
GetOptions(
    'deep-search|d' => \$deep_search,
    'partial-match|p' => \$partial_match,
    'max-matches|m=i' => \$max_matches,
    'max-matches-size|z=s' => sub {
        my ($opt, $val) = @_;
        if ($val =~ /^(\d+(?:\.\d+)?)\s*([KMG]?)B?$/i) {
            my ($num, $unit) = ($1, uc($2));
            $max_matches_size = $num * ($unit eq 'G' ? 1024**3 : $unit eq 'M' ? 1024**2 : $unit eq 'K' ? 1024 : 1);
        } else {
            die "Invalid size format: $val (use format like '50M', '1G', or '1048576')\n";
        }
    },
    'live|l' => \$live_output,
    'version|v' => \$show_version,
    'help|h' => \$show_help,
) or die "Use --help for usage information\n";

# Handle --version
if ($show_version) {
    print "pg_log_search version $VERSION\n";
    exit 0;
}

# Handle --help
if ($show_help) {
    print_help();
    exit 0;
}

# Timing variables
my %timers;
my $start_time = time();

# Check for log file - prioritize command line args over stdin
my $log_file;
my $use_stdin = 0;

# First check if a log file was provided as argument
$log_file = $ARGV[0];

if ($log_file) {
    # Log file provided as argument - use it
    unless (-f $log_file && -r $log_file) {
        die "Error: Cannot read log file: $log_file\n";
    }
    my $file_size = -s $log_file;
    print "Log file: $log_file\n";
    print "Log file size: " . sprintf("%.2f MB\n", $file_size / (1024*1024));
} elsif (!-t STDIN) {
    # No file argument, but stdin is available - use stdin for log
    $use_stdin = 1;
    print "Reading log from stdin...\n";
} else {
    # No file argument, no stdin - try to auto-detect
    $log_file = find_postgresql_log();
    if (!$log_file) {
        die "Error: No log file specified and couldn't find PostgreSQL log automatically.\n" .
            "Usage: $0 [postgresql_log_file]\n" .
            "   or: cat logfile | $0\n";
    }
    print "Found PostgreSQL log: $log_file\n";
    my $file_size = -s $log_file;
    print "Log file size: " . sprintf("%.2f MB\n", $file_size / (1024*1024));
}

# Get query from user
my $search_query = read_query_input($use_stdin);

# Normalize query for comparison and pre-compute patterns for performance
my $timer_start = time();
my $normalized_search = normalize_query_fast($search_query);

# Pre-compute search patterns to avoid repeated regex operations
my $search_pattern = query_to_pattern($normalized_search);

# Pre-compute search structure for deep matching
my $search_structure = $normalized_search;
$search_structure =~ s/\bin\s*\([^)]+\)/in(__)/gi;
# Replace parameters FIRST, before other replacements
$search_structure =~ s/\$\d+/__/g;
$search_structure =~ s/-?\d+(?:\.\d+)?/__/g;
$search_structure =~ s/'[^']*'/__/g;
$search_structure =~ s/\bnull\b/__/gi;

$timers{normalize} = time() - $timer_start;

if ($use_stdin) {
    print "\nSearching for query in stdin\n";
} else {
    print "\nSearching for query in: $log_file\n";
}
print "=" x 80 . "\n\n";

# Create temp file for output
my ($temp_fh, $temp_file_path) = tempfile(UNLINK => 1);
$temp_file = $temp_file_path;  # Store in global for Ctrl+C handler

# Process log file
$timer_start = time();
if ($use_stdin) {
    # Process stdin directly without temp file
    $matches_found = search_log(\*STDIN, $normalized_search, $search_pattern, $search_structure, $temp_fh, 0, $partial_match);
} else {
    # Open log file and process
    open(my $log_fh, '<', $log_file) or die "Cannot open $log_file: $!";
    $matches_found = search_log($log_fh, $normalized_search, $search_pattern, $search_structure, $temp_fh, -s $log_file, $partial_match);
    close($log_fh);
}
$timers{search} = time() - $timer_start;

# Add summary to temp file
print $temp_fh "\n" . "=" x 80 . "\n";
print $temp_fh "Total matches found: $matches_found\n";
print $temp_fh " (search interrupted by user)\n" if $interrupted;

# Add timing information
my $total_time = time() - $start_time;
print $temp_fh "\nProcessing time: " . sprintf("%.2f seconds\n", $total_time);
if ($DEBUG) {
    print $temp_fh "\nDetailed timing:\n";
    for my $key (sort keys %timers) {
        if ($key eq 'lines_processed') {
            print $temp_fh "  $key: " . format_number(int($timers{$key})) . "\n";
        } else {
            print $temp_fh "  $key: " . sprintf("%.3f seconds\n", $timers{$key});
        }
    }
}

close($temp_fh);

# Display results
if (!$live_output) {
    if ($matches_found > 0) {
        system("less", $temp_file);
    } else {
        print "No matches found.\n";
    }
}

# Print timing to console
printf "\nTotal processing time: %.2f seconds\n", $total_time;
if ($DEBUG) {
    print "Detailed timing:\n";
    for my $key (sort keys %timers) {
        if ($key eq 'lines_processed') {
            printf "  %s: %s\n", $key, format_number(int($timers{$key}));
        } else {
            printf "  %s: %.3f seconds\n", $key, $timers{$key};
        }
    }
}

# Format number with thousand separators
sub format_number {
    my ($num) = @_;
    $num =~ s/(\d)(?=(\d{3})+$)/$1,/g;
    return $num;
}

# Read query input from user
sub read_query_input {
    my ($use_tty) = @_;

    # Determine input source
    my $input_fh;
    my $is_terminal;

    if ($use_tty) {
        # Stdin is used for log data, read query from terminal
        open($input_fh, '<', '/dev/tty') or die "Cannot open /dev/tty for query input: $!\n";
        $is_terminal = 1;
    } else {
        # Use stdin for query input
        $input_fh = \*STDIN;
        $is_terminal = -t STDIN;
    }

    # Show prompts if reading from terminal
    if ($is_terminal) {
        print STDERR "\nEnter PostgreSQL query (paste FULL query, then press Ctrl-D):\n";
        print STDERR "Note: Query fragments won't match. Use --partial-match if the query is truncated at the end.\n";
    }

    my $entire_input = '';

    if ($is_terminal) {
        # Terminal input - use raw mode for large pastes
        my $stty_cmd = $use_tty ? "stty -g </dev/tty 2>/dev/null" : "stty -g 2>/dev/null";
        my $old_stty = `$stty_cmd`;
        chomp $old_stty;

        if ($old_stty) {
            # Disable canonical mode to bypass 4KB line buffer limit
            my $set_stty_cmd = $use_tty ? "stty -icanon -echo min 1 time 0 </dev/tty 2>/dev/null" : "stty -icanon -echo min 1 time 0 2>/dev/null";
            system($set_stty_cmd);

            my $buffer;
            my $char_count = 0;
            my $got_ctrl_d = 0;

            while (1) {
                my $nread = sysread($input_fh, $buffer, 1);
                last if !defined $nread || $nread == 0;

                if (ord($buffer) == 4) {  # Ctrl-D
                    $got_ctrl_d = 1;
                    last;
                }

                print STDERR $buffer;  # Echo
                $entire_input .= $buffer;
                $char_count++;

                # Read in chunks if data available
                if ($char_count % 100 == 0) {
                    my $extra;
                    while (1) {
                        my $extra_read = sysread($input_fh, $extra, 8192);
                        last if !defined $extra_read || $extra_read == 0;

                        if (index($extra, chr(4)) >= 0) {
                            my $pos = index($extra, chr(4));
                            $entire_input .= substr($extra, 0, $pos);
                            print STDERR substr($extra, 0, $pos);
                            $got_ctrl_d = 1;
                            last;
                        }
                        $entire_input .= $extra;
                        print STDERR $extra;
                        $char_count += length($extra);
                    }
                    last if $got_ctrl_d;
                }
            }

            my $restore_stty_cmd = $use_tty ? "stty $old_stty </dev/tty 2>/dev/null" : "stty $old_stty 2>/dev/null";
            system($restore_stty_cmd);
            print STDERR "\n";
        } else {
            # Fallback without stty
            local $/ = undef;
            $entire_input = <$input_fh>;
        }
    } else {
        # Piped input
        local $/ = undef;
        $entire_input = <$input_fh>;
    }

    # Close /dev/tty if we opened it
    close($input_fh) if $use_tty;

    $entire_input =~ s/\s+$// if defined $entire_input;

    if (!$entire_input || $entire_input eq '') {
        die "Error: No query provided\n";
    }

    if ($DEBUG) {
        open(my $debug_fh, '>', '/tmp/pg_log_search_debug_query.txt');
        print $debug_fh $entire_input;
        close($debug_fh);
        print STDERR "DEBUG: Saved query to /tmp/pg_log_search_debug_query.txt (" . length($entire_input) . " bytes)\n";
    }

    return $entire_input;
}

# Check if filename should be excluded from auto-detection
sub should_exclude_log_file {
    my ($filepath) = @_;
    my $filename = (split('/', $filepath))[-1];  # Get basename

    my @exclusion_patterns = (
        'pgbouncer',  # pgbouncer logs
     );

    # Check if filename contains any exclusion pattern
    for my $pattern (@exclusion_patterns) {
        return 1 if $filename =~ /\Q$pattern\E/i;
    }

    return 0;
}

# Try to find PostgreSQL log file automatically
sub find_postgresql_log {
    my @possible_locations = (
        '/var/log/postgresql/*.log',
        '/var/log/postgresql/postgresql-*.log',
        '/var/lib/pgsql/*/data/log/*.log',
        '/var/lib/postgresql/*/main/log/*.log',
        '/usr/local/pgsql/data/log/*.log',
        '/opt/postgresql/*/data/log/*.log',
        '/var/lib/pgsql/data/pg_log/*.log',
        '/var/lib/postgresql/*/main/pg_log/*.log',
    );
    
    # Also check for PostgreSQL data directory from running process
    my $ps_output = `ps aux 2>/dev/null | grep -E 'postgres.*-D|postmaster.*-D' | grep -v grep`;
    if ($ps_output =~ /-D\s*([^\s]+)/) {
        my $data_dir = $1;
        push @possible_locations, "$data_dir/log/*.log", "$data_dir/pg_log/*.log";
    }
    
    # Find the most recent log file
    my $most_recent_file;
    my $most_recent_time = 0;
    my @skipped_files = ();

    for my $pattern (@possible_locations) {
        my @files = glob($pattern);
        for my $file (@files) {
            # Skip excluded log files
            if (should_exclude_log_file($file)) {
                push @skipped_files, $file;
                next;
            }

            if (-f $file && -r $file) {
                my $mtime = (stat($file))[9];
                if ($mtime > $most_recent_time) {
                    $most_recent_time = $mtime;
                    $most_recent_file = $file;
                }
            }
        }
    }

    # Debug output for skipped files
    if ($DEBUG && @skipped_files) {
        print STDERR "DEBUG: Skipped excluded log files:\n";
        for my $file (@skipped_files) {
            print STDERR "  - $file\n";
        }
    }

    return $most_recent_file;
}

sub normalize_query_fast {
    my ($query) = @_;
    
    # Remove comments (keep these as they're fast)
    $query =~ s/--[^\n]*//g;
    $query =~ s/\/\*.*?\*\///gs;
    
    # Convert to lowercase
    $query = lc($query);
    
    # Fast whitespace normalization using tr/// which is much faster than s///
    # Replace tabs and newlines with spaces
    $query =~ tr/\t\n\r/ /;
    
    # Collapse multiple spaces to single space
    $query =~ tr/ / /s;
    
    # Trim leading/trailing whitespace (matching pg_stat_statements: space, tab, newline, cr, vertical tab, form feed)
    my $len = length($query);
    if ($len) {
        my $start = 0;
        my $end = $len;

        # Find first non-whitespace (quick check for common case: no leading whitespace)
        my $ch = substr($query, 0, 1);
        if ($ch eq ' ' || $ch eq "\t" || $ch eq "\n" || $ch eq "\r" || $ch eq "\x0B" || $ch eq "\f") {
            $start++;
            while ($start < $len) {
                $ch = substr($query, $start, 1);
                last unless $ch eq ' ' || $ch eq "\t" || $ch eq "\n" || $ch eq "\r" || $ch eq "\x0B" || $ch eq "\f";
                $start++;
            }
        }

        # Find last non-whitespace (quick check for common case: no trailing whitespace)
        $ch = substr($query, -1, 1);
        if ($ch eq ' ' || $ch eq "\t" || $ch eq "\n" || $ch eq "\r" || $ch eq "\x0B" || $ch eq "\f") {
            $end--;
            while ($end > $start) {
                $ch = substr($query, $end - 1, 1);
                last unless $ch eq ' ' || $ch eq "\t" || $ch eq "\n" || $ch eq "\r" || $ch eq "\x0B" || $ch eq "\f";
                $end--;
            }
        }

        # Single substr only if trimming needed
        $query = substr($query, $start, $end - $start) if $start > 0 || $end < $len;
    }
    
    # Only normalize operators if deep search mode is enabled
    if ($deep_search) {
        # This is the expensive operation - only do it if needed
        $query =~ s/\s*([(),=<>!+\-*\/])\s*/$1/g;
    }
    
    return $query;
}

sub query_to_pattern {
    my ($query) = @_;

    # Escape special regex characters
    my $pattern = quotemeta($query);

    # Handle IN clauses - simplified regex
    $pattern =~ s/\\bin\\\s*\\\([^)]+\\\)/in\\s*\\([^)]+\\)/gi;

    # Replace values with simplified patterns
    # Use \S+ (non-whitespace) instead of character class
    # Numbers
    $pattern =~ s/(?<!\\)\\-?\\d+(?:\\\\.\\d+)?/\\S+/g;

    # Quoted strings - match anything that's not comma or close paren
    $pattern =~ s/\\'[^']*\\'/[^,)]+/g;

    # Parameters - match non-whitespace
    $pattern =~ s/\\\$\d+/\\S+/g;

    return $pattern;
}

# matching function with pre-computed patterns
sub queries_match {
    my ($log_query, $normalized_search, $search_pattern, $search_structure, $partial_match) = @_;

    # Direct match first (fastest)
    return 1 if $log_query eq $normalized_search;

    # Partial match mode - check if search query is a prefix of log query
    # (useful when queries are truncated due to track_activity_query_size)
    if ($partial_match) {
        # Check if normalized_search is a prefix of log_query
        my $search_len = length($normalized_search);
        if (length($log_query) >= $search_len) {
            return 1 if substr($log_query, 0, $search_len) eq $normalized_search;
        }
        # Also check reverse - if log_query is a prefix of search
        my $log_len = length($log_query);
        if (length($normalized_search) >= $log_len) {
            return 1 if substr($normalized_search, 0, $log_len) eq $log_query;
        }
    }

    # Quick structure check - compare lengths (skip if deep search enabled)
    if (!$deep_search) {
        my $len_diff = abs(length($log_query) - length($normalized_search));
        # In partial match mode, allow larger length differences
        my $max_diff = $partial_match ? length($normalized_search) : length($normalized_search) * 0.5;
        return 0 if $len_diff > $max_diff;  # Too different
    }

    # Pattern matching - use pre-computed search pattern
    return 1 if $log_query =~ /^$search_pattern$/i;

    # Check if log query matches search as pattern
    my $log_pattern = query_to_pattern($log_query);
    return 1 if $normalized_search =~ /^$log_pattern$/i;

    # Structure comparison - only enabled with deep search flag
    if ($deep_search) {
        # Use pre-computed search_structure
        my $log_structure = $log_query;

        # Only compute structure for log query
        # Replace parameters FIRST, before other replacements
        $log_structure =~ s/\bin\s*\([^)]+\)/in(__)/gi;
        $log_structure =~ s/\$\d+/__/g;
        $log_structure =~ s/-?\d+(?:\.\d+)?/__/g;
        $log_structure =~ s/'[^']*'/__/g;
        $log_structure =~ s/\bnull\b/__/gi;

        if ($partial_match) {
            # In partial match mode, check if one is a prefix of the other
            my $search_len = length($search_structure);
            my $log_len = length($log_structure);
            if ($log_len >= $search_len) {
                return 1 if substr($log_structure, 0, $search_len) eq $search_structure;
            }
            if ($search_len >= $log_len) {
                return 1 if substr($search_structure, 0, $log_len) eq $log_structure;
            }
        } else {
            return $search_structure eq $log_structure;
        }
    }

    return 0;
}

# search function - accepts filehandle
sub search_log {
    my ($fh, $normalized_search, $search_pattern, $search_structure, $output_fh, $file_size, $partial_match) = @_;

    my $matches_found = 0;
    my $total_match_size = 0;
    my $limit_reached = '';
    my @current_statement_lines;
    my $in_statement = 0;
    my $lines_processed = 0;
    my $bytes_read = 0;
    my $last_progress = 0;
    
    # Pre-compile the regex for statement detection
    my $statement_regex = qr/LOG:\s*(?:duration:\s*[\d.]+\s*ms\s*)?\s*(?:statement|execute\s+\S+):\s*/i;
    my $continuation_regex = qr/^\s+\S/;
    my $detail_regex = qr/DETAIL:/i;  # Match DETAIL anywhere in line (has timestamp prefix)
    
    # Timing for matching
    my $match_time = 0;
    my $read_time = 0;
    
    while (1) {
        my $read_start = time();
        my $line = <$fh>;
        last unless defined $line;
        $read_time += time() - $read_start;
        
        chomp $line;

        # Trim excessively long lines to prevent memory/performance issues
        if (length($line) > $MAX_LINE_LENGTH) {
            $line = substr($line, 0, $MAX_LINE_LENGTH);
        }

        $lines_processed++;
        $bytes_read += length($line) if $file_size;

        # Check for interrupt
        last if $interrupted;

        # Progress reporting every 10,000 lines
        if ($lines_processed % 10000 == 0) {
            if ($file_size) {
                # File with known size - show percentage
                my $progress = ($bytes_read / $file_size) * 100;
                if ($progress - $last_progress > 1) {  # Update every 1%
                    printf STDERR "\rProgress: %.1f%% (%d lines, %d matches)", $progress, $lines_processed, $matches_found;
                    $last_progress = $progress;
                }
            } else {
                # stdin or unknown size - show line count and matches
                printf STDERR "\rProgress: %s lines, %d matches", format_number($lines_processed), $matches_found;
            }
        }
        
        # Check limits before processing more
        if ($matches_found >= $max_matches) {
            $limit_reached = 'max_matches';
            last;
        }
        if ($total_match_size >= $max_matches_size) {
            $limit_reached = 'max_size';
            last;
        }

        # Check if this is a log line with a statement
        if ($line =~ $statement_regex) {
            # Process previous statement if exists
            if (@current_statement_lines) {
                my $match_start = time();
                my $match_size = check_and_print_match(\@current_statement_lines, $normalized_search, $search_pattern, $search_structure, \$matches_found, $output_fh, $partial_match);
                $total_match_size += $match_size;
                $match_time += time() - $match_start;
            }

            # Start new statement
            @current_statement_lines = ($line);
            $in_statement = 1;

        } elsif ($in_statement) {
            # Check if this is a continuation of the statement
            if ($line =~ $continuation_regex || $line =~ $detail_regex || $line =~ /^\s*$/) {
                push @current_statement_lines, $line;
            } else {
                # End of statement - process it
                my $match_start = time();
                my $match_size = check_and_print_match(\@current_statement_lines, $normalized_search, $search_pattern, $search_structure, \$matches_found, $output_fh, $partial_match);
                $total_match_size += $match_size;
                $match_time += time() - $match_start;
                @current_statement_lines = ();
                $in_statement = 0;
            }
        }
    }
    
    # Process last statement if exists (unless we hit a limit)
    if (@current_statement_lines && !$limit_reached) {
        my $match_start = time();
        my $match_size = check_and_print_match(\@current_statement_lines, $normalized_search, $search_pattern, $search_structure, \$matches_found, $output_fh, $partial_match);
        $total_match_size += $match_size;
        $match_time += time() - $match_start;
    }

    # Clear progress line (always clear if we showed progress)
    print STDERR "\r" . " " x 80 . "\r" if $lines_processed > 0;

    # Report if limits were reached
    if ($limit_reached eq 'max_matches') {
        print STDERR "\nReached maximum match limit ($max_matches). Stopping search.\n";
    } elsif ($limit_reached eq 'max_size') {
        my $size_mb = sprintf("%.2f", $max_matches_size / (1024*1024));
        print STDERR "\nReached maximum match size (${size_mb}MB). Stopping search.\n";
    }

    # Store detailed timings
    $timers{read_time} = $read_time;
    $timers{match_time} = $match_time;
    $timers{lines_processed} = $lines_processed;

    return $matches_found;
}

# Replace $N parameters with actual values
sub replace_parameters {
    my ($lines_ref) = @_;

    # Find DETAIL line with parameters
    my $detail_idx = -1;
    for (my $i = 0; $i < @$lines_ref; $i++) {
        if ($lines_ref->[$i] =~ /DETAIL:\s*parameters:/i) {
            $detail_idx = $i;
            last;
        }
    }

    return 0 unless $detail_idx >= 0;
    
    my $params_line = $lines_ref->[$detail_idx];
    
    # Parse parameters from DETAIL line
    if ($params_line =~ /parameters:\s*(.+)$/i) {
        my $params_str = $1;
        my %params;
        
        # Parse parameters - handle various formats
        while ($params_str =~ /\$(\d+)\s*=\s*('(?:[^'\\]|\\.)*'|NULL|[^,]+?)(?:\s*,\s*|\s*$)/g) {
            my $param_num = $1;
            my $param_value = $2;
            # Trim whitespace from value
            $param_value =~ s/^\s+|\s+$//g;
            $params{$param_num} = $param_value;
        }
        
        # Replace parameters in all lines
        for (my $i = 0; $i < @$lines_ref; $i++) {
            next if $i == $detail_idx;  # Skip the DETAIL line itself
            
            # Replace each parameter
            foreach my $num (keys %params) {
                $lines_ref->[$i] =~ s/\$$num\b/$params{$num}/g;
            }
        }
        
        # Remove the DETAIL line from output
        splice(@$lines_ref, $detail_idx, 1);
        return 1;
    }
    
    return 0;
}

# Check if statement matches and print if it does
# Returns the size of the match in bytes (0 if no match)
sub check_and_print_match {
    my ($lines, $normalized_search, $search_pattern, $search_structure, $matches_ref, $output_fh, $partial_match) = @_;

    return 0 unless @$lines;

    # Extract just the query text from the lines
    my $query_text = '';
    my $first_line = 1;

    for my $line (@$lines) {
        if ($first_line && $line =~ /LOG:\s*(?:duration:\s*[\d.]+\s*ms\s*)?\s*(?:statement|execute\s+\S+):\s*(.*)$/i) {
            $query_text = $1;
            $first_line = 0;
        } elsif (!$first_line && $line !~ /^\s*DETAIL:/i) {
            # Continuation line
            if ($line =~ /^\s+(.*)/) {
                $query_text .= "\n" . $1;
            } elsif ($line =~ /^\s*$/) {
                $query_text .= "\n";
            }
        }
    }

    return 0 unless $query_text;

    # Normalize the log query
    my $normalized_log = normalize_query_fast($query_text);

    # Check if queries match - using pre-computed patterns
    if (queries_match($normalized_log, $normalized_search, $search_pattern, $search_structure, $partial_match)) {
        $$matches_ref++;

        # Make a copy of lines for output
        my @output_lines = @$lines;

        # Replace parameters if found and remove DETAIL line
        replace_parameters(\@output_lines);

        # Print the matched lines
        my $output = join("\n", @output_lines) . "\n\n";
        print $output_fh $output;

        # In live mode, also print to stdout immediately
        if ($live_output) {
            print STDOUT $output;
        }

        return length($output);
    }

    return 0;
}

# Print help information
sub print_help {
    print <<'HELP';
pg_log_search - Fast PostgreSQL log query search tool

USAGE:
    pg_log_search [OPTIONS] [logfile]
    cat logfile | pg_log_search [OPTIONS]

DESCRIPTION:
    Searches PostgreSQL log files for specific SQL queries. Handles multi-line
    queries, parameter substitution, and various log formats. Optimized for
    speed with large log files.

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version number
    -d, --deep-search       Enable thorough matching with operator normalization
                            and structure comparison (slower but more accurate).
                            Disables length-based quick rejection optimization.
    -p, --partial-match     Enable partial matching for queries truncated at the end
                            (useful when queries are cut off due to
                            track_activity_query_size limit). Allows matching
                            when search query or log query is incomplete.
    -l, --live              Show matches in real-time as they're found
    -m, --max-matches N     Stop after N matches (default: 10000)
    -z, --max-matches-size SIZE
                            Stop when total match size reaches SIZE
                            (default: 50M). Accepts K, M, G suffixes.

ENVIRONMENT VARIABLES:
    DEBUG=1                 Show detailed timing information

EXAMPLES:
    # Auto-detect most recent PostgreSQL log and search in it (prompts for query)
    pg_log_search

    # Search specific log file
    pg_log_search /var/log/postgresql/postgresql.log

    # Search with log from stdin (query entered interactively)
    cat postgresql.log | pg_log_search

    # Search with query from stdin (log file specified)
    pg_log_search /var/log/postgresql/postgresql.log < query.sql

    # Monitor live log with tail -f and show matches in real-time
    tail -f /var/log/postgresql/postgresql.log | pg_log_search --live

    # Search log file and show matches as they're found
    pg_log_search --live /var/log/postgresql/postgresql.log

    # Limit results and use deep search
    pg_log_search -d -m 100 postgresql.log

    # Size limit with live output
    pg_log_search -l --max-matches-size 10M postgresql.log

    # Search with partial matching for truncated queries
    pg_log_search --partial-match postgresql.log

QUERY INPUT:
    After starting, paste your FULL SQL query and press Ctrl-D when done.
    Multi-line queries are fully supported.

    IMPORTANT: Query fragments won't match - you must provide the complete query
    from beginning to end. If your query might be truncated at the end (e.g., due
    to track_activity_query_size limit), use the --partial-match option.

    Note: Queries can contain parameter placeholders ($1, $2, ..., $N) as from
    pg_stat_statements. The tool will match them against actual parameter values
    in the log entries.

INTERRUPTING:
    Press Ctrl+C during search to stop and view partial results found so far.

OUTPUT:
    Matched queries are displayed with:
    - Original log line with timestamp and duration
    - Parameter values substituted for $1, $2, etc.
    - Clean formatting (DETAIL lines removed)

HELP
}
