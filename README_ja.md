# iostat2graphs

[rstat](https://github.com/sh2/rstat)�����Ϥ���iostat�Υ��ե�������Ȥ˥���դ����褹��Web���ץꥱ�������Ǥ���[dstat2graphs](https://github.com/sh2/dstat2graphs)�������ץ�����ȤǤ���

## ����ץ�

�ʲ��Υǥ⥵���ȤǼºݤ˻��ѤǤ��ޤ���

- [iostat2graphs - dbstudy.info](http://dbstudy.info/iostat2graphs)

���Ϸ�̤Υ���ץ�Ǥ���

- [k01sl6.local 2017/01/29 17:54:14 - iostat2graphs](http://dbstudy.info/iostat2graphs/reports/20170129-190230_hUjRTRUR/)

�ǥ⥵���Ȥλ��Ѥ˺ݤ��Ƥϡ�����������դ��Ƥ���������

- ���åץ��ɤǤ���CSV�ե����륵�����ϡ�4MBytes�ޤǤǤ���
- �����������浡ǽ�Ϥ���ޤ���Τǡ���̩���ι⤤�ǡ����ϥ��åץ��ɤ��ʤ��Ǥ���������

## ���åȥ��å�

Red Hat Enterprise Linux 6/7�ȡ������Υ�����ǥ����ȥ�ӥ塼�������оݤˤ��Ƥ��ޤ���

Apache HTTP Server��PHP�����󥹥ȡ��뤵��Ƥ���ɬ�פ�����ޤ������˥ѥå��������롼��Web Server��PHP Support�򥤥󥹥ȡ��뤷�Ƥ���������

    # yum groupinstall 'Web Server' 'PHP Support'

³���ưʲ��Υѥå������򥤥󥹥ȡ��뤷�Ƥ���������

- perl-Archive-Zip
- perl-HTML-Parser
- rrdtool
- rrdtool-perl

<!-- dummy comment line for breaking list -->

    # yum install perl-Archive-Zip perl-HTML-Parser rrdtool rrdtool-perl

�ܥġ���Ϻ�ȥǥ��쥯�ȥ�Ȥ���/dev/shm����Ѥ��ޤ����ʲ��Τ褦�ˤ��ƺ�ȥǥ��쥯�ȥ���������apache�桼�����񤭹��ߤ�Ԥ�����֤ˤ��Ƥ����������ܥġ���򹱵�Ū�˻��Ѥ�����ϡ�/etc/rc.local�˺�ȥǥ��쥯�ȥ�����������ɲä���ʤɤ��Ƥ���������

    # mkdir /dev/shm/iostat2graphs
    # chown apache:apache /dev/shm/iostat2graphs

Apache HTTP Server�Υɥ�����ȥ롼���۲��˥�����ץȤ����֤��Ƥ���������������ץȤ����֤����ǥ��쥯�ȥ��ľ����reports�ǥ��쥯�ȥ���������apache�桼�����񤭹��ߤ�Ԥ�����֤ˤ��Ƥ���������

    # mkdir <document_root>/<script_dir>/reports
    # chown apache:apache <document_root>/<script_dir>/reports

rstat��CSV�ե����륵�������礭����硢PHP���礭�ʥե�����򰷤���褦�ˤ��Ƥ���ɬ�פ�����ޤ���/etc/php.ini�ˤ����ƥѥ�᡼��upload\_max\_filesize��CSV�ե����륵���������礭���ͤ�Ĵ�ᤷ�Ƥ������������ΤȤ�memory\_limit &gt; post\_max\_size &gt; upload\_max\_filesize�Ȥ����ط���������ɬ�פ�����ޤ���

    memory_limit = 128M
    post_max_size = 8M
    upload_max_filesize = 2M

## �����ֲ��̤���λȤ���

Web�֥饦����http://&lt;server\_host&gt;/&lt;script\_dir&gt;/�˥�����������ȡ�CSV�ե�����򥢥åץ��ɤ�����̤�ɽ������ޤ���CSV�ե��������ꤷ��Upload�ܥ���򲡤��ȡ�����դ����褵��ޤ���

- iostat CSV File
    - iostat CSV File �� ���åץ��ɤ���CSV�ե��������ꤷ�ޤ���
- Graph Size
    - Width �� ����դβ�����������ꤷ�ޤ���ñ�̤ϥԥ�����Ǥ���
    - Height �� ����դνĥ���������ꤷ�ޤ���ñ�̤ϥԥ�����Ǥ���
- Graph Upper Limits
    - I/O Requests �� I/O Requests�Υ���դˤĤ��ơ�Y���κ����ͤ���ꤷ�ޤ���ñ�̤ϲ�/�äǤ���0����ꤹ��ȼ�ưĴ�ᤷ�ޤ���
    - I/O Bytes (Bytes/second) �� I/O Bytes�Υ���դˤĤ��ơ�Y���κ����ͤ���ꤷ�ޤ���ñ�̤ϥХ���/�äǤ���0����ꤹ��ȼ�ưĴ�ᤷ�ޤ���
    - I/O Queue Length �� I/O Queue Length�Υ���դˤĤ��ơ�Y���κ����ͤ���ꤷ�ޤ���0����ꤹ��ȼ�ưĴ�ᤷ�ޤ���
    - I/O Wait Time �� I/O Wait Time�Υ���դˤĤ��ơ�Y���κ����ͤ���ꤷ�ޤ���ñ�̤ϥߥ��äǤ���0����ꤹ��ȼ�ưĴ�ᤷ�ޤ���
    - I/O Service Time �� I/O Service Time�Υ���դˤĤ��ơ�Y���κ����ͤ���ꤷ�ޤ���ñ�̤ϥߥ��äǤ���0����ꤹ��ȼ�ưĴ�ᤷ�ޤ���
- Other Settings
    - X-Axis �� X���˷в���֤�ɽ�����뤫�ºݤλ����ɽ�����뤫�����򤷤ޤ���
    - Offset �� ���ꤷ�����֤�����CSV�ե��������Ƭ���饫�åȤ������褷�ޤ���ñ�̤��äǤ���
    - Duration �� CSV�ե��������Ƭ�����뤤��Offset���֤�����ꤷ�����֤Τ����褷�ޤ���ñ�̤��äǤ���0����ꤹ���CSV�ե�����������ޤ����褷�ޤ���

## Perl������ץ�ñ�ΤǤλȤ���

Perl������ץ�iostat2graphs.pl��ñ�Τǻ��Ѥ��ƥ���դ����褹�뤳�Ȥ���ǽ�Ǥ�����ȥǥ��쥯�ȥ�/dev/shm/iostat2graphs���Ф��ƥ�����ץȼ¹ԥ桼�����񤭹��ߤ�Ԥ�����֤ˤ��Ƥ����Ƥ������������ޥ�ɥ饤�󥪥ץ����ϰʲ����̤�Ǥ������٤ƻ��ꤹ��ɬ�פ�����ޤ���

    $ perl iostat2graph.pl csv_file report_dir width height requests_limit bytes_limit qlength_limit wtime_limit stime_limit offset duration is_actual

- report_dir ����դ���Ϥ���ǥ��쥯�ȥ����ꤷ�ޤ����ǥ��쥯�ȥ꤬¸�ߤ��ʤ����ϼ�ư�������ޤ���

report_dir�ʳ��Υ��ץ����ϡ������ֲ��̤������Ǥ����Τ�Ʊ���Ǥ���
