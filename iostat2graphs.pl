#!/usr/bin/perl

use strict;
use warnings;

use Archive::Zip qw/AZ_OK/;
use File::Path;
use HTML::Entities;
use POSIX qw/floor ceil/;
use RRDs;
use Text::ParseWords;
use Time::Local;

if ($#ARGV != 8) {
    die 'Usage: perl iostat2graph.pl csv_file report_dir width height requests_limit bytes_limit qlength_limit wtime_limit stime_limit';
}

my $csv_file       = $ARGV[0];
my $report_dir     = $ARGV[1];
my $width          = $ARGV[2];
my $height         = $ARGV[3];
my $requests_limit = $ARGV[4];
my $bytes_limit    = $ARGV[5];
my $qlength_limit  = $ARGV[6];
my $wtime_limit    = $ARGV[7];
my $stime_limit    = $ARGV[8];

my @colors = (
    '008FFF', 'FF00BF', 'BFBF00', 'BF00FF',
    'FF8F00', '00BFBF', '7F5FBF', 'BF5F7F',
    '7F8F7F', '005FFF', 'FF007F', '7FBF00',
    '7F00FF', 'FF5F00', '00BF7F', '008FBF',
    'BF00BF', 'BF8F00', '7F5F7F', '005FBF',
    'BF007F', '7F8F00', '7F00BF', 'BF5F00',
    '008F7F', '0000FF', 'FF0000', '00BF00',
    '005F7F', '7F007F', '7F5F00', '0000BF',
    'BF0000', '008F00'
    );

my $epoch = 978274800; # 2001/01/01 00:00:00
my $top_dir = '..';
my $rrd_file = '/dev/shm/iostat2graphs/' . &random_str() . '.rrd';

my ($hostname, @devices, @data, %value);
my ($start_time, $end_time) = (0, 0);

&load_csv();
&create_rrd();
&update_rrd();
&create_dir();
&create_graph();
&delete_rrd();
&create_html();
&create_zip();

sub load_csv {
    my ($buffer, $device_last, $flag_device_pickup, $flag_duplicate);
    
    open(my $fh, '<', $csv_file) or die $!;
    
    while (my $line = <$fh>) {
        chomp($line);
        
        if ($line eq '') {
            # Empty
        } elsif ($line =~ /^Host/) {
            # Host
            my @cols = parse_line(',', 0, $line);
            
            if ($cols[1] =~ /\(([^\)]+?)\)/) {
                $hostname = $1;
            }
            
        } elsif ($line =~ /^Datetime/) {
            # Header
        } else {
            # Body
            my @cols = parse_line(',', 0, $line);
            
            if ($start_time == 0) {
                if (!defined($hostname)) {
                    die 'It is not a iostat CSV file. No \'Host\' column found.';
                }
                
                $flag_device_pickup = 1;
                $start_time = &get_unixtime($cols[0]);
            }
            
            $cols[1] =~ tr/\//_/; # 'cciss/c0d0'       -> 'cciss_c0d0'
            $cols[6] *= 1024;     # rkB/s              -> rBytes/s
            $cols[7] *= 1024;     # wkB/s              -> wBytes/s
            $cols[8] *= 512;      # avgrq-sz (Sectors) -> avgrq-sz (Bytes)
            
            if ($flag_device_pickup) {
                if (defined($devices[0]) and ($cols[1] eq $devices[0])) {
                    $flag_device_pickup = 0;
                    $device_last = $devices[$#devices];
                    push @data, $buffer;
                } else {
                    if (&is_block_device($cols[1])) {
                        push @devices, $cols[1];
                    }
                }
            }
            
            if ($cols[1] eq $devices[0]) {
                my $unixtime = &get_unixtime($cols[0]);
                
                if ($unixtime <= $end_time) {
                    $flag_duplicate = 1;
                } else {
                    $flag_duplicate = 0;
                    $end_time = $unixtime;
                    $buffer = $epoch + $unixtime - $start_time;
                }
            }
            
            if ($flag_duplicate) {
                next;
            }
            
            if (&is_block_device($cols[1])) {
                $buffer .= ':' . join(':', @cols[2..$#cols]);
            }
            
            if (defined($device_last) and ($cols[1] eq $device_last)) {
                push @data, $buffer;
            }
        }
    }
}

sub create_rrd {
    my @options;
    my $steps = floor(($end_time - $start_time) / 3600) + 1;
    my $rows = ceil(($end_time - $start_time) / $steps) + 1;
    
    # --start
    push @options, '--start';
    push @options, $epoch - 1;
    
    # --step
    push @options, '--step';
    push @options, 1;
    
    foreach my $device (@devices) {
        # rrqm/s wrqm/s
        push @options, "DS:RRMERGE_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        push @options, "DS:WRMERGE_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # r/s w/s
        push @options, "DS:RREQ_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        push @options, "DS:WREQ_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # rBytes/s wBytes/s
        push @options, "DS:RBYTE_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        push @options, "DS:WBYTE_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # avgrq-sz (Bytes)
        push @options, "DS:RSIZE_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # avgqu-sz
        push @options, "DS:QLENGTH_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # await
        push @options, "DS:WTIME_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # svctm
        push @options, "DS:STIME_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
        
        # %util
        push @options, "DS:UTIL_${device}:GAUGE:5:U:U";
        push @options, "RRA:AVERAGE:0.5:${steps}:${rows}";
    }
    
    RRDs::create($rrd_file, @options);
    
    if (my $error = RRDs::error) {
        die $error;
    }
}

sub update_rrd {
    RRDs::update($rrd_file, @data);
    
    if (my $error = RRDs::error) {
        &delete_rrd();
        die $error;
    }
}

sub create_dir {
    eval {
        mkpath($report_dir);
    };
    
    if ($@) {
        &delete_rrd();
        die $@;
    }
}

sub create_graph {
    my (@template, @options, @values);
    my $window = (floor(($end_time - $start_time) / 3600) + 1) * 60;
    
    # Template
    push @template, '--start';
    push @template, $epoch;
    
    push @template, '--end';
    push @template, $epoch + $end_time - $start_time;
    
    push @template, '--width';
    push @template, $width;
    
    push @template, '--height';
    push @template, $height;
    
    push @template, '--lower-limit';
    push @template, 0;
    
    push @template, '--rigid';
    
    foreach my $device (@devices) {
        # rrqm/s wrqm/s
        @options = @template;
        
        push @options, '--title';
        push @options, "I/O Requests Merged ${device} (/sec)";
        
        push @options, "DEF:RRMERGE=${rrd_file}:RRMERGE_${device}:AVERAGE";
        push @options, "LINE1:RRMERGE#${colors[0]}:read";
        
        push @options, "DEF:WRMERGE=${rrd_file}:WRMERGE_${device}:AVERAGE";
        push @options, "LINE1:WRMERGE#${colors[1]}:write";
        
        push @options, "VDEF:R_MIN=RRMERGE,MINIMUM";
        push @options, "PRINT:R_MIN:%4.2lf";
        push @options, "VDEF:R_AVG=RRMERGE,AVERAGE";
        push @options, "PRINT:R_AVG:%4.2lf";
        push @options, "VDEF:R_MAX=RRMERGE,MAXIMUM";
        push @options, "PRINT:R_MAX:%4.2lf";
        
        push @options, "VDEF:W_MIN=WRMERGE,MINIMUM";
        push @options, "PRINT:W_MIN:%4.2lf";
        push @options, "VDEF:W_AVG=WRMERGE,AVERAGE";
        push @options, "PRINT:W_AVG:%4.2lf";
        push @options, "VDEF:W_MAX=WRMERGE,MAXIMUM";
        push @options, "PRINT:W_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/rmerged_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"RRMERGE_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"RRMERGE_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"RRMERGE_${device}"}->{'MAX'} = $values[0]->[2];
        $value{"WRMERGE_${device}"}->{'MIN'} = $values[0]->[3];
        $value{"WRMERGE_${device}"}->{'AVG'} = $values[0]->[4];
        $value{"WRMERGE_${device}"}->{'MAX'} = $values[0]->[5];
        
        # r/s w/s
        @options = @template;
        
        if ($requests_limit != 0) {
            push @options, '--upper-limit';
            push @options, $requests_limit;
        }
        
        push @options, '--title';
        push @options, "I/O Requests ${device} (/sec)";
        
        push @options, "DEF:RREQ=${rrd_file}:RREQ_${device}:AVERAGE";
        push @options, "LINE1:RREQ#${colors[0]}:read";
        
        push @options, "DEF:WREQ=${rrd_file}:WREQ_${device}:AVERAGE";
        push @options, "LINE1:WREQ#${colors[1]}:write";
        
        push @options, "VDEF:R_MIN=RREQ,MINIMUM";
        push @options, "PRINT:R_MIN:%4.2lf";
        push @options, "VDEF:R_AVG=RREQ,AVERAGE";
        push @options, "PRINT:R_AVG:%4.2lf";
        push @options, "VDEF:R_MAX=RREQ,MAXIMUM";
        push @options, "PRINT:R_MAX:%4.2lf";
        
        push @options, "VDEF:W_MIN=WREQ,MINIMUM";
        push @options, "PRINT:W_MIN:%4.2lf";
        push @options, "VDEF:W_AVG=WREQ,AVERAGE";
        push @options, "PRINT:W_AVG:%4.2lf";
        push @options, "VDEF:W_MAX=WREQ,MAXIMUM";
        push @options, "PRINT:W_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/requests_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"RREQ_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"RREQ_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"RREQ_${device}"}->{'MAX'} = $values[0]->[2];
        $value{"WREQ_${device}"}->{'MIN'} = $values[0]->[3];
        $value{"WREQ_${device}"}->{'AVG'} = $values[0]->[4];
        $value{"WREQ_${device}"}->{'MAX'} = $values[0]->[5];
        
        # rBytes/s wBytes/s
        @options = @template;
        
        if ($bytes_limit != 0) {
            push @options, '--upper-limit';
            push @options, $bytes_limit;
        }
        
        push @options, '--base';
        push @options, 1024;
        
        push @options, '--title';
        push @options, "I/O Bytes ${device} (Bytes/sec)";
        
        push @options, "DEF:RBYTE=${rrd_file}:RBYTE_${device}:AVERAGE";
        push @options, "LINE1:RBYTE#${colors[0]}:read";
        
        push @options, "DEF:WBYTE=${rrd_file}:WBYTE_${device}:AVERAGE";
        push @options, "LINE1:WBYTE#${colors[1]}:write";
        
        push @options, "VDEF:R_MIN=RBYTE,MINIMUM";
        push @options, "PRINT:R_MIN:%4.2lf %s";
        push @options, "VDEF:R_AVG=RBYTE,AVERAGE";
        push @options, "PRINT:R_AVG:%4.2lf %s";
        push @options, "VDEF:R_MAX=RBYTE,MAXIMUM";
        push @options, "PRINT:R_MAX:%4.2lf %s";
        
        push @options, "VDEF:W_MIN=WBYTE,MINIMUM";
        push @options, "PRINT:W_MIN:%4.2lf %s";
        push @options, "VDEF:W_AVG=WBYTE,AVERAGE";
        push @options, "PRINT:W_AVG:%4.2lf %s";
        push @options, "VDEF:W_MAX=WBYTE,MAXIMUM";
        push @options, "PRINT:W_MAX:%4.2lf %s";
        
        @values = RRDs::graph("${report_dir}/bytes_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"RBYTE_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"RBYTE_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"RBYTE_${device}"}->{'MAX'} = $values[0]->[2];
        $value{"WBYTE_${device}"}->{'MIN'} = $values[0]->[3];
        $value{"WBYTE_${device}"}->{'AVG'} = $values[0]->[4];
        $value{"WBYTE_${device}"}->{'MAX'} = $values[0]->[5];
        
        # avgrq-sz (Bytes)
        @options = @template;
        
        push @options, '--base';
        push @options, 1024;
        
        push @options, '--title';
        push @options, "I/O Request Size ${device} (Bytes)";
        
        push @options, "DEF:RSIZE=${rrd_file}:RSIZE_${device}:AVERAGE";
        push @options, "AREA:RSIZE#${colors[0]}:request_size";
        
        push @options, "CDEF:RSIZE_AVG=RSIZE,${window},TREND";
        push @options, "LINE1:RSIZE_AVG#${colors[1]}:request_size_${window}secs";
        
        push @options, "VDEF:R_MIN=RSIZE,MINIMUM";
        push @options, "PRINT:R_MIN:%4.2lf %s";
        push @options, "VDEF:R_AVG=RSIZE,AVERAGE";
        push @options, "PRINT:R_AVG:%4.2lf %s";
        push @options, "VDEF:R_MAX=RSIZE,MAXIMUM";
        push @options, "PRINT:R_MAX:%4.2lf %s";
        
        @values = RRDs::graph("${report_dir}/rsize_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"RSIZE_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"RSIZE_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"RSIZE_${device}"}->{'MAX'} = $values[0]->[2];
        
        # avgqu-sz
        @options = @template;
        
        if ($qlength_limit != 0) {
            push @options, '--upper-limit';
            push @options, $qlength_limit;
        }
        
        push @options, '--title';
        push @options, "I/O Queue Length ${device}";
        
        push @options, "DEF:QLENGTH=${rrd_file}:QLENGTH_${device}:AVERAGE";
        push @options, "AREA:QLENGTH#${colors[0]}:queue_length";
        
        push @options, "CDEF:QLENGTH_AVG=QLENGTH,${window},TREND";
        push @options, "LINE1:QLENGTH_AVG#${colors[1]}:queue_length_${window}secs";
        
        push @options, "VDEF:Q_MIN=QLENGTH,MINIMUM";
        push @options, "PRINT:Q_MIN:%4.2lf";
        push @options, "VDEF:Q_AVG=QLENGTH,AVERAGE";
        push @options, "PRINT:Q_AVG:%4.2lf";
        push @options, "VDEF:Q_MAX=QLENGTH,MAXIMUM";
        push @options, "PRINT:Q_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/qlength_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"QLENGTH_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"QLENGTH_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"QLENGTH_${device}"}->{'MAX'} = $values[0]->[2];
        
        # await
        @options = @template;
        
        if ($wtime_limit != 0) {
            push @options, '--upper-limit';
            push @options, $wtime_limit;
        }
        
        push @options, '--title';
        push @options, "I/O Wait Time ${device} (millisecs)";
        
        push @options, "DEF:WTIME=${rrd_file}:WTIME_${device}:AVERAGE";
        push @options, "AREA:WTIME#${colors[0]}:wait_time";
        
        push @options, "CDEF:WTIME_AVG=WTIME,${window},TREND";
        push @options, "LINE1:WTIME_AVG#${colors[1]}:wait_time_${window}secs";
        
        push @options, "VDEF:W_MIN=WTIME,MINIMUM";
        push @options, "PRINT:W_MIN:%4.2lf";
        push @options, "VDEF:W_AVG=WTIME,AVERAGE";
        push @options, "PRINT:W_AVG:%4.2lf";
        push @options, "VDEF:W_MAX=WTIME,MAXIMUM";
        push @options, "PRINT:W_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/wtime_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"WTIME_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"WTIME_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"WTIME_${device}"}->{'MAX'} = $values[0]->[2];
        
        # svctm
        @options = @template;
        
        if ($stime_limit != 0) {
            push @options, '--upper-limit';
            push @options, $stime_limit;
        }
        
        push @options, '--title';
        push @options, "I/O Service Time ${device} (millisecs)";
        
        push @options, "DEF:STIME=${rrd_file}:STIME_${device}:AVERAGE";
        push @options, "AREA:STIME#${colors[0]}:service_time";
        
        push @options, "CDEF:STIME_AVG=STIME,${window},TREND";
        push @options, "LINE1:STIME_AVG#${colors[1]}:service_time_${window}secs";
        
        push @options, "VDEF:S_MIN=STIME,MINIMUM";
        push @options, "PRINT:S_MIN:%4.2lf";
        push @options, "VDEF:S_AVG=STIME,AVERAGE";
        push @options, "PRINT:S_AVG:%4.2lf";
        push @options, "VDEF:S_MAX=STIME,MAXIMUM";
        push @options, "PRINT:S_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/stime_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"STIME_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"STIME_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"STIME_${device}"}->{'MAX'} = $values[0]->[2];
        
        # %util
        @options = @template;
        
        push @options, '--upper-limit';
        push @options, 100;
        
        push @options, '--title';
        push @options, "I/O Utilization ${device} (%)";
        
        push @options, "DEF:UTIL=${rrd_file}:UTIL_${device}:AVERAGE";
        push @options, "AREA:UTIL#${colors[0]}:utilization";
        
        push @options, "CDEF:UTIL_AVG=UTIL,${window},TREND";
        push @options, "LINE1:UTIL_AVG#${colors[1]}:utilization_${window}secs";
        
        push @options, "VDEF:U_MIN=UTIL,MINIMUM";
        push @options, "PRINT:U_MIN:%4.2lf";
        push @options, "VDEF:U_AVG=UTIL,AVERAGE";
        push @options, "PRINT:U_AVG:%4.2lf";
        push @options, "VDEF:U_MAX=UTIL,MAXIMUM";
        push @options, "PRINT:U_MAX:%4.2lf";
        
        @values = RRDs::graph("${report_dir}/util_${device}.png", @options);
        
        if (my $error = RRDs::error) {
            &delete_rrd();
            die $error;
        }
        
        $value{"UTIL_${device}"}->{'MIN'} = $values[0]->[0];
        $value{"UTIL_${device}"}->{'AVG'} = $values[0]->[1];
        $value{"UTIL_${device}"}->{'MAX'} = $values[0]->[2];
    }
}

sub delete_rrd {
    unlink $rrd_file;
}

sub create_html {
    my $hostname_enc = encode_entities($hostname);
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($start_time);
    
    my $datetime = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec); 
        
    my $duration = $end_time - $start_time;
    my ($report_suffix) = $report_dir =~ /([^\/]+)\/*$/;
    
    open(my $fh, '>', "${report_dir}/index.html") or die $!;
    
    print $fh <<_EOF_;
<!DOCTYPE html>
<html>
  <head>
    <title>${hostname_enc} ${datetime} - iostat2graphs</title>
    <link href="${top_dir}/css/bootstrap.min.css" rel="stylesheet" />
    <style type="text/css">
      body {
        padding-top: 20px;
        padding-bottom: 20px;
      }
      .sidebar-nav {
        padding: 12px 4px;
      }
      .hero-unit {
        padding: 24px;
      }
      th.header {
        text-align: center;
      }
      td.number {
        text-align: right;
      }
    </style>
  </head>
  <body>
    <div class="container-fluid">
      <div class="row-fluid">
        <div class="span3">
          <div class="well sidebar-nav">
            <ul class="nav nav-list">
              <li class="nav-header">I/O Requests Merged</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#rmerged_${device}\">I/O Requests Merged ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Requests</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#requests_${device}\">I/O Requests ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Bytes</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#bytes_${device}\">I/O Bytes ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Request Size</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#rsize_${device}\">I/O Request Size ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Queue Length</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#qlength_${device}\">I/O Queue Length ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Wait Time</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#wtime_${device}\">I/O Wait Time ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Service Time</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#stime_${device}\">I/O Service Time ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
              <li class="nav-header">I/O Utilization</li>
_EOF_
    
    foreach my $device (@devices) {
        print $fh ' ' x 14;
        print $fh "<li><a href=\"#util_${device}\">I/O Utilization ${device}</a></li>\n";
    }
    
    print $fh <<_EOF_;
            </ul>
          </div>
        </div>
        <div class="span9">
          <div class="hero-unit">
            <h1>iostat2graphs</h1>
            <ul>
              <li>Hostname: ${hostname_enc}</li>
              <li>Datetime: ${datetime}</li>
              <li>Duration: ${duration} (secs)</li>
            </ul>
          </div>
          <p><a href="i_${report_suffix}.zip">Download a Zip file</a></p>
          <h2>I/O Requests Merged</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="rmerged_${device}">I/O Requests Merged ${device}</h3>
          <p><img src="rmerged_${device}.png" alt="I/O Requests Merged ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Requests Merged ${device} (/sec)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>read</td>
                <td class="number">$value{"RRMERGE_${device}"}->{'MIN'}</td>
                <td class="number">$value{"RRMERGE_${device}"}->{'AVG'}</td>
                <td class="number">$value{"RRMERGE_${device}"}->{'MAX'}</td>
              </tr>
              <tr>
                <td>write</td>
                <td class="number">$value{"WRMERGE_${device}"}->{'MIN'}</td>
                <td class="number">$value{"WRMERGE_${device}"}->{'AVG'}</td>
                <td class="number">$value{"WRMERGE_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Requests</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="requests_${device}">I/O Requests ${device}</h3>
          <p><img src="requests_${device}.png" alt="I/O Requests ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Requests ${device} (/sec)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>read</td>
                <td class="number">$value{"RREQ_${device}"}->{'MIN'}</td>
                <td class="number">$value{"RREQ_${device}"}->{'AVG'}</td>
                <td class="number">$value{"RREQ_${device}"}->{'MAX'}</td>
              </tr>
              <tr>
                <td>write</td>
                <td class="number">$value{"WREQ_${device}"}->{'MIN'}</td>
                <td class="number">$value{"WREQ_${device}"}->{'AVG'}</td>
                <td class="number">$value{"WREQ_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Bytes</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="bytes_${device}">I/O Bytes ${device}</h3>
          <p><img src="bytes_${device}.png" alt="I/O Bytes ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Bytes ${device} (Bytes/sec)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>read</td>
                <td class="number">$value{"RBYTE_${device}"}->{'MIN'}</td>
                <td class="number">$value{"RBYTE_${device}"}->{'AVG'}</td>
                <td class="number">$value{"RBYTE_${device}"}->{'MAX'}</td>
              </tr>
              <tr>
                <td>write</td>
                <td class="number">$value{"WBYTE_${device}"}->{'MIN'}</td>
                <td class="number">$value{"WBYTE_${device}"}->{'AVG'}</td>
                <td class="number">$value{"WBYTE_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Request Size</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="rsize_${device}">I/O Request Size ${device}</h3>
          <p><img src="rsize_${device}.png" alt="I/O Request Size ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Request Size ${device} (Bytes)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>request_size</td>
                <td class="number">$value{"RSIZE_${device}"}->{'MIN'}</td>
                <td class="number">$value{"RSIZE_${device}"}->{'AVG'}</td>
                <td class="number">$value{"RSIZE_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Queue Length</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="qlength_${device}">I/O Queue Length ${device}</h3>
          <p><img src="qlength_${device}.png" alt="I/O Queue Length ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Queue Length ${device}</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>queue_length</td>
                <td class="number">$value{"QLENGTH_${device}"}->{'MIN'}</td>
                <td class="number">$value{"QLENGTH_${device}"}->{'AVG'}</td>
                <td class="number">$value{"QLENGTH_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Wait Time</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="wtime_${device}">I/O Wait Time ${device}</h3>
          <p><img src="wtime_${device}.png" alt="I/O Wait Time ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Wait Time ${device} (millisecs)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>wait_time</td>
                <td class="number">$value{"WTIME_${device}"}->{'MIN'}</td>
                <td class="number">$value{"WTIME_${device}"}->{'AVG'}</td>
                <td class="number">$value{"WTIME_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Service Time</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="stime_${device}">I/O Service Time ${device}</h3>
          <p><img src="stime_${device}.png" alt="I/O Service Time ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Service Time ${device} (millisecs)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>service_time</td>
                <td class="number">$value{"STIME_${device}"}->{'MIN'}</td>
                <td class="number">$value{"STIME_${device}"}->{'AVG'}</td>
                <td class="number">$value{"STIME_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
          <hr />
          <h2>I/O Utilization</h2>
_EOF_
    
    foreach my $device (@devices) {
        print $fh <<_EOF_;
          <h3 id="util_${device}">I/O Utilization ${device}</h3>
          <p><img src="util_${device}.png" alt="I/O Utilization ${device}"></p>
          <table class="table table-condensed">
            <thead>
              <tr>
                <th class="header">I/O Utilization ${device} (%)</th>
                <th class="header">Minimum</th>
                <th class="header">Average</th>
                <th class="header">Maximum</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>utilization</td>
                <td class="number">$value{"UTIL_${device}"}->{'MIN'}</td>
                <td class="number">$value{"UTIL_${device}"}->{'AVG'}</td>
                <td class="number">$value{"UTIL_${device}"}->{'MAX'}</td>
              </tr>
            </tbody>
          </table>
_EOF_
    }
    
    print $fh <<_EOF_;
        </div>
      </div>
      <hr />
      <div class="footer">
        (c) 2012, Sadao Hiratsuka.
      </div>
    </div>
    <script src="${top_dir}/js/jquery-1.7.2.min.js"></script>
    <script src="${top_dir}/js/bootstrap.min.js"></script>
  </body>
</html>
_EOF_
    
    close($fh);
}

sub create_zip {
    my ($report_suffix) = $report_dir =~ /([^\/]+)\/*$/;
    my $zip = Archive::Zip->new();
    
    $zip->addTreeMatching($report_dir, $report_suffix, '\.(html|png)$');
    
    if ($zip->writeToFileNamed("${report_dir}/i_${report_suffix}.zip") != AZ_OK) {
        die;
    }
}

sub random_str {
    my $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    my $length = length($chars);
    my $str = '';
    
    for (my $i = 0; $i < 16; $i++) {
        $str .= substr($chars, int(rand($length)), 1);
    }
    
    return $str;
}

sub get_unixtime {
    my ($datetime) = @_;
    my $unixtime = 0;
    
    if ($datetime =~ /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)/) {
        $unixtime = timelocal($6, $5, $4, $3, $2 - 1, $1);
    }
}

sub is_block_device {
    my ($device) = @_;
    
    if (($device =~ /^\w+[a-z]$/)
        or ($device =~ /^md\d+$/)
        or ($device =~ /^cciss\/c\d+d\d+$/)) {
        
        return 1;
    } else {
        return 0;
    }
}

