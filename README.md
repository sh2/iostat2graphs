# iostat2graphs

This is a web application which draws graphs from an iostat log file output by [rstat](https://github.com/sh2/rstat). It is a derivative product of [dstat2graphs](https://github.com/sh2/dstat2graphs).

You can use the demo site below.

- [iostat2graphs - dbstudy.info](https://dbstudy.info/iostat2graphs)

Here is a sample output.

- [k01sl6.local 2017/01/29 17:54:14 - iostat2graphs](https://dbstudy.info/iostat2graphs/reports/20170129-190230_hUjRTRUR/)

When you use the demo site, please be aware of the following.

- A CSV file size that can be uploaded is limited to 4MBytes.
- Since there is no access control, please do not upload sensitive data.

## Setup

This tool is intended to be used in Red Hat Enterprise Linux 6/7 and their clone distributions.

This tool requires Apache HTTP Server and PHP. Please install 'Web Server' and 'PHP Support' package groups.

    # yum groupinstall 'Web Server' 'PHP Support'

Next, please install the following packages.

- perl-Archive-Zip
- perl-HTML-Parser
- rrdtool
- rrdtool-perl

<!-- dummy comment line for breaking list -->

    # yum install perl-Archive-Zip perl-HTML-Parser rrdtool rrdtool-perl

This tool uses '/dev/shm' as a working directory. Please create the working directory and give write permission to user 'apache'. If you want to use this tool permanently, please add such procedures to '/etc/rc.local'.

    # mkdir /dev/shm/iostat2graphs
    # chown apache:apache /dev/shm/iostat2graphs

Please place the scripts under the document root of the Apache HTTP Server, create 'reports' directory and give write permission to user 'apache'.

    # mkdir <document_root>/<script_dir>/reports
    # chown apache:apache <document_root>/<script_dir>/reports

If the CSV file size is large, you should modify PHP settings to handle large files. Please adjust parameter 'upload\_max\_filesize' in '/etc/php.ini' to the value greater than the CSV file size. This parameter must meet the relationship 'memory\_limit &gt; post\_max\_size &gt; upload\_max\_filesize'.

    memory_limit = 128M
    post_max_size = 8M
    upload_max_filesize = 2M

## Web UI

If you access http://&lt;server\_host&gt;/&lt;script\_dir&gt;/ in a web browser, the screen will be displayed. When you specify the CSV file and press the Upload button, the graphs will be drawn.

- iostat CSV File
    - iostat CSV File ... Specify the CSV file you want to upload.
- Graph Size
    - Width ... Specify the horizontal size of graphs, in pixel.
    - Height ... Specify the vertical size of graphs, in pixel.
- Graph Upper Limits
    - I/O Requests ... Specify the maximum value of the Y-axis for I/O Requests graphs. The unit is Times/second. It is automatically adjusted if you specify 0.
    - I/O Bytes ... Specify the maximum value of the Y-axis for I/O Bytes graphs. The unit is Bytes/second. It is automatically adjusted if you specify 0.
    - I/O Queue Length ... Specify the maximum value of the Y-axis for I/O Queue Length graphs. It is automatically adjusted if you specify 0.
    - I/O Wait Time ... Specify the maximum value of the Y-axis for I/O Wait Time graphs. The unit is Milliseconds. It is automatically adjusted if you specify 0.
    - I/O Service Time ... Specify the maximum value of the Y-axis for I/O Service Time graphs. The unit is Milliseconds. It is automatically adjusted if you specify 0.
- Other Settings
    - X-axis ... Select whether to display elapsed time or actual time on the X-axis.
    - Offset ... Cut the specified time from the beginning of the CSV file. The unit is second.
    - Duration ... Draw only the specified time from the beginning or the offset position. The unit is second. It draws until the end of the CSV file if you specify 0.

## Perl CUI

It is possible to draw graphs using Perl script 'iostat2graphs.pl'. Please give write permission of '/dev/shm/iostat2graphs' to the user which executes this script. Command line options are as follows. All must be specified.

    $ perl iostat2graph.pl csv_file report_dir width height requests_limit bytes_limit qlength_limit wtime_limit stime_limit offset duration is_actual

- report_dir ... Specify the directory where you want to store graphs. It is automatically created if it does not exist.

Options other than 'report_dir' are the same as those that can be specified from Web UI.
