#!/usr/local/bin/perl

use utf8;
use strict;
use warnings;

use constant CHARSET => 'cp932';

binmode STDIN  => ":encoding(".CHARSET.")";
binmode STDOUT => ":encoding(".CHARSET.")";
binmode STDERR => ":encoding(".CHARSET.")";

use Encode;
use File::Copy qw(copy);
use File::Path qw(make_path);
use Path::Class;
use Getopt::Long;


local $| = 1;

our $PROGRAM_NAME = 'YoutubeDownloader';
our $VERSION      = '0.3.0';

my (
	@link, $list, $dir, $all, $test,
	$verbose, $fmt, $beep, $help, $avoid, $temp,
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
	"r|avoid-fragmenting" => \$avoid,
);

$list ||= 'yt.txt';
$dir  ||= './';
$fmt  ||= 0;
$beep = $beep ? "\a" : '';

print <<"_HELP_" and exit if $help;
$PROGRAM_NAME - Ver. $VERSION
$0 [-a | --list <downloadlist_filename>] [-d | --directory <downloaddir>] [-l | --href <URL>]
  -l or --href: input URLs. (ex. -l URL -l URL -l URL ...)
  -a or --list: list of target. input filename. default is 'yt.txt'.
  -d or --download: download directory. input dirname. default is current.
  -v: show download progress indication.
  -f: set &fmt. default is undefind. if you set this option without arguments, use -f=18.
          ( 5=[320x180 H.263 flv],  6=[480x270 H.263 flv],
            7=[176x144 ? 3gp],     13=[176x144 MPEG4 3gp],
           18=[480x270 H.264 mp4], 22=[1280x720 H.264 mp4],
           34=[320x180 H.264 flv], 35=[640x380 H.264 flv]  )
  -b: beep when some errors have happened.
  -r: avoid extreme fragmenting of videos.
  -t: test mode.
  -h: this is.
_HELP_

my $enc = find_encoding(CHARSET);
$list = $enc->decode($list);
$dir  = $enc->decode($dir );

main();


sub main {
	my $yt = YouTube::VideoURI->new(dir => $dir, all => $all, progress => $verbose, fmt => $fmt);
	my @lines = map { split /\s+/ } @link;

	my $TEMP_DIR = File::Spec->tmpdir;

	if ($avoid) {
		if (-d $TEMP_DIR) {
			if (not -d "$TEMP_DIR/$PROGRAM_NAME") {
				make_path("$TEMP_DIR/$PROGRAM_NAME", { varbose => 1, mode => 755, })
			}
			$temp = "$TEMP_DIR/$PROGRAM_NAME";
		}
		else {
			warn "'$TEMP_DIR'(ENV: TEMP or TMP) is not found. 'avoid-fragmenting' is turned off.\n";
		}
	}

	unless (@lines) {
		my $fh = file($list)->open('<:utf8') or die "cannot open '$list'\n";
		@lines = $fh->getlines;
	}

	print "test mode start. \n\n" if $test;

	for (@lines) {
		chomp $_;
		if ($test) {
			print "get_video_uri: ",(/[?&]v=([^&=]+)/)[0],"... ";

			$yt->get_video_uri($_);

			print "ok.\n", "\tdownload uri: " . $yt->uri . "\n\n";
		}
		else {
			download($yt, $_);

		}
	}

	print "test mode end. \n" if $test;
	print "complete works.\n";
}

sub _path {
	my ($s, $a, $t) = @_;
	my $dir = $a ? $temp : $s->dir;
	my $tmp = (!$a and $t) ? "-$s->{title_tmp}" : "";

	file( $enc->encode($dir), $enc->encode(join('', $s->title, ".", $s->ext, $tmp)) );
}

sub download {
	my ($self, $uri) = @_;

	my $download;

	if ($uri) {
		$self->get_video_uri($uri);
	}

	print $self->title, '.', $self->ext, "\n";

	if (-e _path($self)) {
		if (!$self->{all}) {
			my $anser = '';
			while ($anser !~ /^y(?:es)?$|^no?$/) {
				print "\talready exists. download? (yes/no), $beep";
				chomp($anser = <>);
			}
			if ($anser =~ /^n/) { print "\tskipped.\n\n"; return }
		}

		while (-e _path($self)) { $self->{title} .= '_' }
		print $enc->decode( _path($self)->basename ), "\n";
	}

	print "\tdownload ... ";

	if (!$self->{progress}) {
		my $res = $self->{ua}->mirror( $self->{uri}, _path($self, $avoid) );
		print $res->is_success ? "ok." : $res->status_line, "\n";
		if ($res->is_success and $avoid) {
			print "\tcopy from TEMP ... ";
			if ( copy(_path($self, $avoid), _path($self)) ) {
				print "ok.\n"; unlink _path($self, $avoid);
			}
			else {
				print "error: $!\n";
			}
		}
		print "\n";
	}
	else {
		if (!$avoid) {
			$self->{title_tmp} = int rand 10000;
			while (-e _path($self)) {
				$self->{title_tmp} = int rand 10000;
			}
		}

		my $file = _path($self, $avoid, 1);
		my $wfh = $file->open(">") or die "$file: $!";

		$wfh->binmode();

		my $total = 0;
		my $res = $self->{ua}->get($self->{uri}, ':content_cb' => sub {
			my ( $chunk, $res, $proto ) = @_;
			print $wfh $chunk;
			my $size = $wfh->tell;
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
			unlink _path($self, $avoid, 1);
			print $res->status_line;
		}
		elsif (!$avoid) {
			print rename(_path($self, $avoid, 1), _path($self)) ? "ok." : "rename error: $!";
		}
		else {
			print "ok.\n", "\tcopy from TEMP ... "
			      , copy(_path($self, $avoid, 1), _path($self)) ? "ok." : "error: $!";
			unlink _path($self, $avoid, 1);
		}

		print "\n\n";
	}
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
use Encode qw(decode_utf8);
use LWP::UserAgent;


our $VERSION = '0.2.0';

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

	my $res = $self->{ua}->get($uri);
	croak($res->status_line) if $res->is_error;

	my $content = decode_utf8($res->content);

	if ($content =~ /video_id=([^&]*).*?&t=([^&]*)(?:.*?&title=(.*)';)?/) {
		$self->{uri}  = "http://www.youtube.com/get_video?video_id=$1&t=$2";
		$self->{uri} .= "&fmt=$self->{fmt}" if $self->{fmt};
		$self->{title} = $3 || '_';
		$self->{title} =~ s!&amp;!&!g;
		$self->{title} =~ s![\\/:*?"<>|]!_!g;
	}

	$self->{uri};
}

sub uri {
	return shift->{uri} || undef;
}

sub dir {
	return shift->{dir} || undef;
}

sub title {
	return shift->{title} || undef;
}

sub ext {
	return shift->{ext} || undef;
}


1;
