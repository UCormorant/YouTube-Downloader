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
our $VERSION      = '0.4.0';

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
  -a or --list: list of target. input a filename or a playlist URL. default is 'yt.txt'.
  -d or --download: download directory. input dirname. default is current.
  -v: show download progress indication.
  -f: set &fmt. default is undefind. if you set this option without arguments, use -f=18.
          ( 5=[320x180 H.263 flv],  6=[480x270 H.263 flv],
            7=[176x144 ? 3gp],     13=[176x144 MPEG4 3gp],
           18=[480x270 H.264 mp4], 22=[1280x720 H.264 mp4],
           34=[320x180 H.264 flv], 35=[640x380 H.264 flv]  )
  -s: download while disregarding any notices.
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
#	my $yt = Video::YouTube->new();
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
		if ($list =~ m!^https?://!) {
			@lines = Video::YouTube->new->get_video_uri($list)->uris;
		}
		else {
			my $fh = file($enc->encode($list))->open('<:utf8') or die "cannot open '$list'\n";
			@lines = $fh->getlines;
		}
	}

	print "test mode start. \n\n" if $test;

	for (@lines) {
		chomp $_;
		if ($test) {
			print "get_video_uri: ",(/[?&]v=([^&=]+)/)[0],"... ";

			my $yt = Video::YouTube::URI->new($_, fmt => $fmt);

			print "ok.\n", "\tdownload uri: " . $yt->uri . "\n\n";
		}
		else {
			download(Video::YouTube::URI->new($_, fmt => $fmt));
		}
	}

	print "test mode end. \n" if $test;
	print "complete works.\n";
}

sub _path {
	my ($s, $a, $t) = @_;
	my $DIR = $a ? $temp : $dir;
	my $TMP = (!$a and $t) ? "-$s->{title_tmp}" : "";

	file( $enc->encode($DIR), $enc->encode(join('', $s->title, ".", $s->ext, $TMP)) );
}

sub download {
	my ($self, %opt) = @_;

	my $download;

	print $self->title, '.', $self->ext, "\n";

	if (-e _path($self)) {
		if (!$all) {
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

	if (!$verbose) {
		my $res = $self->{ua}->mirror( $self->uri, _path($self, $avoid) );
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
		my $res = $self->{ua}->get($self->uri, ':content_cb' => sub {
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


package Video::YouTube;

use utf8;
use strict;
use warnings;

use Encode qw(decode_utf8);
use LWP::UserAgent;

our $VERSION = '0.3.0';

sub new {
	my $class  = shift;
	my %opt    = @_;

	return bless({
		ua  => ($opt{ua} or LWP::UserAgent->new),
		def_fmt => $opt{fmt},
	}, $class);
}

sub get_video_uri {
	my ($self, $uri, %opt) = @_;
	$opt{ua} ||= $self->{ua};

	my $res = $self->{ua}->get($uri);
	croak($res->status_line) if $res->is_error;

	my $content = decode_utf8($res->content);
	my %u; $u{''}++;
	while (!$u{
		my $next = ($content =~ m!<a[^>]+?href="([^"]+)"[^>]+?class="pagerNotCurrent"[^>]+>!ig)[-1] || ''
	}++) {
		push(@{$self->{uris}}, ($content =~ /<a id="video-long-title-[^"]+"\s*href="([^"]+)"/ig));
		my $res = $self->{ua}->get($next);
		croak($res->status_line) if $res->is_error;
		$content = decode_utf8($res->content);
	}

#	push(@{$self->{uris}}, Video::YouTube::URI->new($uri, %opt));

	$self;
}

sub uris {
	my $uris = shift->{uris};
	return wantarray ? @{$uris} : $uris;
}


package Video::YouTube::URI;

use utf8;
use strict;
use warnings;

use Carp;
use URI;
use Encode qw(decode_utf8);
use LWP::UserAgent;

sub new {
	my $self = bless { fmt => 0 }, shift;
	my $uri = shift;
	my %opt = @_;
	$self->{ua} = $opt{ua} || LWP::UserAgent->new;

	$uri = "http://www.youtube.com/$uri" if $uri !~ /^http/;
	my $uri_c = URI->new($uri);
	my %params = $uri_c->query_form;
	$params{v} ||= '';
	croak("Malformed URL or missing parameter") if ($params{v} eq '');

	my $res = $self->{ua}->get($uri);
	croak($res->status_line) if $res->is_error;

	my $content = decode_utf8($res->content);

	if ($content =~ /video_id=([^&]*).*?&t=([^&]*)(?:.*?&title=(.*)';)?/) {
		$self->{uri}  = "http://www.youtube.com/get_video?video_id=$1&t=$2";
		$self->{title} = $3 || '_';
		$self->{title} =~ s!&amp;!&!g;
		$self->{title} =~ s![\\/:*?"<>|]!_!g;
	}

	$self->fmt($opt{fmt});

	$self;
}

sub uri {
	return shift->{uri} || undef;
}

sub title {
	return shift->{title} || undef;
}

sub ext {
	my $self = shift;
	return ($self->fmt ==  7 or $self->fmt == 13) ? '3gp'
	     : ($self->fmt == 18 or $self->fmt == 22) ? 'mp4'
	                                              : 'flv';
}

sub fmt {
	my ($self, $fmt) = @_;
	if ($fmt && $self->is_defined($fmt)) {
		$self->{uri} .= "&fmt=$fmt";
		$self->{fmt} = $fmt;
	}

	$self->{fmt} = 0 unless exists $self->{fmt};
	return $self->{fmt};
}

sub is_defined {
	my ($self, $fmt) = @_;
	my $uri = $self->{uri} . ($fmt ? "&fmt=$fmt" : '');
	return $self->{ua}->head($uri)->is_success;
}


1;
