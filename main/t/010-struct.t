#!/usr/bin/env perl
# 010-struct.t - recycling 1999 example code as a test loading a struct
# Copyright (c) 1999,2022 Ian Kluft
use strict;
use warnings;
use utf8;
use Carp;
use File::Temp;
use WebFetch::Input::PerlStruct;
use WebFetch::Data::Store;
use Test::More tests => 3;
use Test::Exception;

# sample data from 1999 example - the URLs long since no longer exist
my $content = [
	{
	"url" => "http://www.svlug.org/news.shtml#19990410-000",
	"title" => "EHeadlines puts SVLUG news on your Enlightenment desktop"
	},
	{
	"url" => "http://www.svlug.org/news.shtml#19990408-000",
	"title" => "SVLUG has released WebFetch 0.04"
	},
	{
	"url" => "http://www.svlug.org/news.shtml#19990402-000",
	"title" => "comp.os.linux.announce and CNN Linux news added to SVLUG home page"
	},
	{
	"url" => "http://www.svlug.org/news.shtml#19990330-000",
	"title" => "SVLUG Editorial on Competition for DNS"
	},
	{
	"url" => "http://www.svlug.org/news.shtml#19990329-000",
	"title" => "Linux 2.2.5 released"
	},
	{
	"url" => "http://www.svlug.org/news.shtml#19990310-000",
	"title" => "Marc Merlin's LinuxWorld Report and Pictures"
	}
];

# set up temporary directory
#my $tmpdir = File::Temp->newdir();

# instantiate test object
my @params = (
	"content" => WebFetch::Data::Store->new($content),
    #"dir" => $tmpdir,
	"dir" => ".",
	"dest" => "perlstruct.txt",
    "dest_format" => "dump",
);
print STDERR "params: ".int(@params)."\n";
my $obj;
lives_ok( sub {$obj = WebFetch::Input::PerlStruct->new(@params)}, "instantiate WebFetch::Input::PerlStruct");
isa_ok($obj, "WebFetch::Input::PerlStruct");

# export content to file
my $exitcode = $obj->run();
if ($exitcode) {
	foreach my $savable ( @{$obj->{savable}}) {
		(ref $savable eq "HASH") or next;
		if ( defined $savable->{error}) {
			print STDERR "WebFetch: (in "
				.$obj->{dir}.") error saving "
				.$savable->{file}.": "
				.$savable->{error}."\n"
		}
	}
}
is($exitcode, 0, "run() method returned 1");
