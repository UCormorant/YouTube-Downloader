#!/usr/local/bin/perl

use utf8;
use strict;
use warnings;

binmode STDIN  => ":encoding(cp932)";
binmode STDOUT => ":encoding(cp932)";
binmode STDERR => ":encoding(cp932)";

use IO::Dir;
use Getopt::Long;
use Encode qw(encode decode);


local $| = 1;

our $PROGRAM_NAME = 'YoutubeDownloader';
our $VERSION      = '0.2.8';

my (
    @link, $list, $dir, $all, $test,
    $verbose, $fmt, $beep, $help,
);
my $result = GetOptions(
    "l|href=s" => \@link,
    "a|list=s" => \$list,
    "d|directory" => \$dir,
    "t|test" => \$test,
    "s|all" => \$all,
    "v|verbose" => \$verbose,
    "f|fmt:18" => \$fmt,
    "b|beep" => \$beep,
    "h|help|?" => \$help,
);

$list ||= 'yt.txt';
$dir  ||= './';
$fmt  ||= 0;
$beep = $beep ? "\a" : '';

die <<"_HELP_" if $help;
$PROGRAM_NAME - Ver. $VERSION
yt [-a | --list <downloadlist_filename>] [-d | --directory <downloaddir>] [-l | --href <URL>]
  -l or --href: input URLs. (ex. -l URL -l URL -l URL ...)
  -a or --list: list of target. input filename. default is 'yt.txt'.
  -d or --download: download directory. input dirname. default is current.
  -v: show download progress.
  -f: set &fmt. default is undefind. if you set this option without argumens, use -f=18.
          ( 5=[320x180 H.263 flv],  6=[480x270 H.263 flv],
            7=[176x144 ? 3gp],     13=[176x144 MPEG4 3gp],
           18=[480x270 H.264 mp4], 22=[1280x720 H.264 mp4],
           34=[320x180 H.264 flv], 35=[640x380 H.264 flv]  )
  -b: beep when some error happened.
  -t: test mode.
  -h: this is.
_HELP_

$list = decode('cp932', $list);
$dir  = decode('cp932', $dir );

main();


sub main {
	my $yt = YouTube::VideoURI->new(dir => $dir, all => $all, progress => $verbose, fmt => $fmt);
	my @lines = @link;

	unless (@lines) {
		my $fh = IO::File->new($list, '<:utf8') or die "cannot open '$list'\n";
		@lines = $fh->getlines;
	}

	print "test mode start. \n\n" if $test;

	for (@lines) {
		chomp $_;
		if ($test) {
			$yt->get_video_uri($_);
			print 'location: ' . $yt->uri . "\n";
		}
		else {
			$yt->download($_);
		}
	}

	print "test mode end. \n" if $test;
	print "complete works.\n";
}


package YouTube::VideoURI;

use utf8;
use strict;
use warnings;

binmode STDIN  => ":encoding(cp932)";
binmode STDOUT => ":encoding(cp932)";
binmode STDERR => ":encoding(cp932)";

use Carp;
use URI;
use Encode qw(encode decode);
use LWP::UserAgent;


our $VERSION = '0.1.2';

sub new {
	my $class  = shift;
	my %opt    = @_;

	return bless({
		dir => $opt{dir},
		ua  => LWP::UserAgent->new(),
		all => $opt{all},
		progress => $opt{progress},
		fmt => $opt{fmt},
		ext => ($opt{fmt} ==  7 or $opt{fmt} == 13) ? '3gp'
		    :  ($opt{fmt} == 18 or $opt{fmt} == 22) ? 'mp4'
		                                            : 'flv',
	}, $class);
}

sub get_video_uri {
	my ($self, $uri) = @_;

	my $uri_c = URI->new($uri);
	my %params = $uri_c->query_form;
	$params{v} ||= '';
	croak("Malformed URL or missing parameter") if ($params{v} eq '');

	print "get_video_uri: $params{v} ... ";

	my $res = $self->{ua}->get($uri);

	croak($res->status_line) if $res->is_error;

	my $content = decode('utf8', $res->content);

	if ($content =~ /video_id=([^&]*).*?&t=([^&]*)(?:.*?&title=(.*)';)?/) {
		$self->{uri}  = "http://www.youtube.com/get_video?video_id=$1&t=$2";
		$self->{uri} .= "&fmt=$self->{fmt}" if $self->{fmt};
		$self->{title} = $3 || '_';
		$self->{title} =~ s!&amp;!&!g;
		$self->{title} =~ s![\\/:*?"<>|]!_!g;
	}

	print "ok.\n";


	$self->{uri};
}

sub uri {
	return shift->{uri} || undef;
}

sub title {
	return shift->{title} || undef;
}

sub download {
	my ($self, $uri) = @_;

	my $download;

	if ($uri) {
		$self->get_video_uri($uri);
	}

	print "$self->{title}.$self->{ext}\n";

	if (-e "$self->{dir}$self->{title}.$self->{ext}") {
		if (!$self->{all}) {
			print "\talready exsists. download? (yes/no), $beep";
			my $anser = '';
			chomp($anser = <>);
			if ($anser =~ /^no/) { print "\tskipped.\n\n"; return }
		}

		while (-e "$self->{dir}$self->{title}.$self->{ext}") { $self->{title} .= '_' }
		print "$self->{title}.$self->{ext}\n";
	}

	print "\tdownload ... ";

	if (!$self->{progress}) {
		my $res = $self->{ua}->mirror( $self->{uri}, encode('cp932', "$self->{dir}$self->{title}.$self->{ext}") );
		print $res->is_success ? "ok." : $res->status_line, "\n\n";
	}
	else {
		$self->{title_tmp} = int rand 10000;
		while (-e "$self->{dir}$self->{title}.$self->{ext}-$self->{title_tmp}") {
			$self->{title_tmp} = int rand 10000;
		}

		my $wfh = IO::File->new(encode('cp932', "$self->{dir}$self->{title}.$self->{ext}-$self->{title_tmp}"), ">")
				or die "$self->{title}.$self->{ext}-$self->{title_tmp}: $!";

		$wfh->binmode();

		my $total = 0;
		my $res = $self->{ua}->get($self->{uri}, ':content_cb' => sub {
			my ( $chunk, $res, $proto ) = @_;
			print $wfh $chunk;
			my $size = tell $wfh;
			if ($total ||= $res->header('Content-Length')){
				printf "\r\tdownload %d/%s (%.2f%%) ... ",
					$total>102400?($size/1024,int($total/1024).'KB'):($size,int $total), $size/$total*100;
			}
			else {
				printf "\r\tdownload %s/Unknown bytes ... ", $size>102400?int($size/1024).'K':int $size;
			}
		});

		undef $wfh;

		unless ($res->is_success) {
			unlink encode('cp932', "$self->{dir}$self->{title}.$self->{ext}-$self->{title_tmp}");
			print $res->status_line;
		}
		elsif (
			rename
				encode('cp932', "$self->{dir}$self->{title}.$self->{ext}-$self->{title_tmp}"),
				encode('cp932', "$self->{dir}$self->{title}.$self->{ext}")
		) {
			print "ok.";
		}
		else {
			print "rename error: $!";
		};

		print "\n\n";
	}
}

1;
