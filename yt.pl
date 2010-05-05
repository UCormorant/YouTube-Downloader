#!perl

use utf8;
use strict;
use warnings;
use Readonly;

our ($CHARSET, $youtube, $playlist, $playlist_ajax);
Readonly $CHARSET  => 'cp932';
Readonly $youtube  => 'http://www.youtube.com/';
Readonly $playlist => $youtube . 'view_play_list';
Readonly $playlist_ajax => $youtube . 'list_ajax?p=%s&action_get_playlist=1';

binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";
binmode STDERR => ":encoding($CHARSET)";

use Encode;
use WWW::YouTube::Download;

$| = 1;

my (@args) = my ($arg) = shift || '-';
die <<"_HELP_" if !$arg;
Usage: $0 video_id, url or url_list
_HELP_

chomp(@args = <>) if $arg eq '-';

my $encode = find_encoding($CHARSET);
my $encode_utf8 = find_encoding('utf8');
my $ua = LWP::UserAgent->new();
my $client = WWW::YouTube::Download->new(ua => $ua);

main(@args);


sub main {
	my @args = @_;

	for my $target (@args) {
		if ($target =~ /$playlist/) {
			my $l = ($target =~ /\bp=([^&]+)/)[0];
			my $res = $ua->get(sprintf("$playlist_ajax", $l));
			main(map { m!\b(watch\?v=[^&]+)! ? "$youtube$1" : () } split /\r?\n|\r/, $encode_utf8->decode($res->content));
			next;
		}
		my $data = $client->prepare_download($target);
		(my $title = $data->{title}) =~ s![\\/:*?"<>|]!_!g;
		$title = $title . '_' . $data->{video_id} . $data->{suffix};
		print "$title\n";
		$client->download($target, {
				file_name => $title,
				verbose   => 1,
		});
	}
}

1;

