# WebFetch::Input::SiteNews
# ABSTRACT: download and save SiteNews headlines from a local file
#
# Copyright (c) 1998-2022 Ian Kluft. This program is free software; you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License Version 3. See  https://www.gnu.org/licenses/gpl-3.0-standalone.html

# pragmas to silence some warnings from Perl::Critic
## no critic (Modules::RequireExplicitPackage)
# This solves a catch-22 where parts of Perl::Critic want both package and use-strict to be first
use strict;
use warnings;
use utf8;
## use critic (Modules::RequireExplicitPackage)

package WebFetch::Input::SiteNews;

use base "WebFetch";

use Carp;
use DateTime;
use DateTime::Format::ISO8601;

=encoding utf8

=cut

# set defaults
my ( $cat_priorities, $now );
my @Options = ( "short=s", "long=s", );
my $Usage   = "--short short-output-file --long long-output-file";

# configuration parameters
my $num_links = 5;

# functions for access to internal data for testing
sub _config_params
{
    return { Options => \@Options, Usage => $Usage, num_links => $num_links };
}
sub _cat_priorities { return $cat_priorities; }

# no user-servicable parts beyond this point

# register capabilities with WebFetch
__PACKAGE__->module_register( _config_params(), "cmdline", "input:sitenews" );

=head1 SYNOPSIS

In perl scripts:

C<use WebFetch::Input::SiteNews;>

From the command line:

C<perl -w -MWebFetch::Input::SiteNews -e "&fetch_main" -- --dir directory
     --source news-file --short short-form-output-file
     --long long-form-output-file>

=head1 DESCRIPTION

This module gets the current headlines from a site-local file.

The I<--source> parameter specifies a file name which contains news to be
posted.  See L<"FILE FORMAT"> below for details on contents to put in the
file.  I<--source> may be specified more than once, allowing a single news
output to come from more than one input.  For example, one file could be
manually maintained in CVS or RCS and another could be entered from a
web form.

After this runs, the file C<site_news.html> will be created or replaced.
If there already was a C<site_news.html> file, it will be moved to
C<Osite_news.html>.

=cut

# constants for state names
sub initial_state { return 0; }
sub attr_state    { return 1; }
sub text_state    { return 2; }

# fetch() is the WebFetch API call point to run this module
sub fetch
{
    my ($self) = @_;

    # set parameters for WebFetch routines
    if ( not defined $self->{num_links} ) {
        $self->{num_links} = WebFetch->config("num_links");
    }
    if ( not defined $self->{style} ) {
        $self->{style} = {};
        $self->{style}{para} = 1;
    }

    # set up Webfetch Embedding API data
    $self->{actions} = {};
    $self->data->add_fields( "date", "title", "priority", "expired",
        "position", "label", "url", "category", "text" );

    # defined which fields match to which "well-known field names"
    $self->data->add_wk_names(
        "title"    => "title",
        "url"      => "url",
        "date"     => "date",
        "summary"  => "text",
        "category" => "category"
    );

    # process the links

    # get local time for various date comparisons
    $now = DateTime->now;

    # parse data file
    if ( ( exists $self->{sources} ) and ( ref $self->{sources} eq "ARRAY" ) ) {
        foreach my $source ( @{ $self->{sources} } ) {
            $self->parse_input($source);
        }
    }

    # set parameters for the short news format
    if ( defined $self->{short_path} ) {

        # create the HTML actions list
        $self->{actions}{html} = [];

        # create the HTML-generation parameters
        my $params = {};
        $params = {};
        $params->{sort_func} = sub {
            my ( $a, $b ) = @_;

            # sort/compare news entries for the short display
            # sorting priority:
            #   expiration status first (expired items last)
            #   priority second (category/age combo)
            #   label third (chronological order)

            # check expirations first
            my $exp_fnum = $self->fname2fnum("expired");
            ( $a->[$exp_fnum] and not $b->[$exp_fnum] ) and return 1;
            ( not $a->[$exp_fnum] and $b->[$exp_fnum] ) and return -1;

            # compare priority - posting category w/ age penalty
            my $pri_fnum = $self->fname2fnum("priority");
            if ( $a->[$pri_fnum] != $b->[$pri_fnum] ) {
                return $a->[$pri_fnum] <=> $b->[$pri_fnum];
            }

            # otherwise sort by label (chronological order)
            my $lbl_fnum = $self->fname2fnum("label");
            return $a->[$lbl_fnum] cmp $b->[$lbl_fnum];
        };
        $params->{filter_func} = sub {

            # filter: skip expired items
            my $exp_fnum = $self->fname2fnum("expired");
            return not $_[$exp_fnum];
        };
        $params->{format_func} = sub {

            # generate HTML text
            my $txt_fnum = $self->fname2fnum("text");
            my $pri_fnum = $self->fname2fnum("priority");
            return $_[$txt_fnum] . "\n<!--- priority " . $_[$pri_fnum] . " --->";
        };

        # put parameters for fmt_handler_html() on the html list
        push @{ $self->{actions}{html} }, [ $self->{short_path}, $params ];
    }

    # set parameters for the long news format
    if ( defined $self->{long_path} ) {

        # create the SiteNews-specific action list
        # It will use WebFetch::Input::SiteNews::fmt_handler_sitenews_long()
        # which is defined in this file
        $self->{actions}{sitenews_long} = [];

        # put parameters for fmt_handler_sitenews_long() on the list
        push @{ $self->{actions}{sitenews_long} }, [ $self->{long_path} ];
    }
    return;
}

# inner portion of input parsing - called by parse_input()
# read SiteNews text file and parse it into news items to return to caller
sub parse_input_inner
{
    my ( $self, $news_data_fd ) = @_;
    my @news_items;
    my $position = 0;
    my $state    = initial_state;    # before first entry
    my ($current);
    $cat_priorities = {};            # priorities for sorting
    while (<$news_data_fd>) {
        chomp;
        /^\s*\#/x and next;          # skip comments
        /^\s*$/x  and next;          # skip blank lines

        if (/^[^\s]/x) {

            # found attribute line
            if ( $state == initial_state ) {
                if (/^categories:\s*(.*)/x) {
                    my @cats = split( ' ', $1 );
                    my ($i);
                    $cat_priorities->{"default"} = 999;
                    for ( $i = 0 ; $i <= $#cats ; $i++ ) {
                        $cat_priorities->{ $cats[$i] } = $i + 1;
                    }
                    next;
                } elsif (/^(\w+):\s*(.*)/x) {
                    $self->{$1} = $2;
                }
            }
            if ( $state == initial_state or $state == text_state ) {

                # found first attribute of a new entry
                if (/^([^=]+)=(.*)/x) {
                    $current             = {};
                    $current->{position} = $position++;
                    $current->{$1}       = $2;
                    push( @news_items, $current );
                    $state = attr_state;
                }
            } elsif ( $state == attr_state ) {

                # found a followup attribute
                if (/^([^=]+)=(.*)/x) {
                    $current->{$1} = $2;
                }
            }
        } else {

            # found text line
            if ( $state == initial_state ) {

                # cannot accept text before any attributes
                next;
            } elsif ( $state == attr_state or $state == text_state ) {
                if ( defined $current->{text} ) {
                    $current->{text} .= "\n$_";
                } else {
                    $current->{text} = $_;
                }
                $state = text_state;
            }
        }
    }
    return @news_items;
}

# parse input file
sub parse_input
{
    my ( $self, $input ) = @_;

    # parse data file
    my $news_data;
    if ( not open( $news_data, "<", $input ) ) {
        croak "$0: failed to open $input: $!\n";
    }
    my @news_items = $self->parse_input_inner($news_data);
    close $news_data;

    # translate parsed news into the WebFetch Embedding API data table
    my ( %label_hash, $pos );
    $pos = 0;
    foreach my $item (@news_items) {

        # collect fields for the data record
        my $title    = ( defined $item->{title} )    ? $item->{title}    : "";
        my $posted   = ( defined $item->{posted} )   ? $item->{posted}   : "";
        my $category = ( defined $item->{category} ) ? $item->{category} : "";
        my $text     = ( defined $item->{text} )     ? $item->{text}     : "";
        my $url_prefix =
            ( defined $self->{url_prefix} ) ? $self->{url_prefix} : "";

# timestamp processing using optional locale and time_zone from SiteNews file's global settings at the top
        my ( %dt_opts, $dt, $time_str, $anchor_time );
        foreach my $dt_key (qw(locale time_zone)) {
            if ( exists $self->{$dt_key} ) {
                $dt_opts{$dt_key} = $self->{$dt_key};
            }
        }
        if ($posted) {
            $dt          = WebFetch::parse_time( \%dt_opts, $posted );
            $time_str    = WebFetch::gen_timestamp( \%dt_opts, $dt );
            $anchor_time = WebFetch::anchor_timestr( \%dt_opts, $dt );
        } else {
            $time_str    = "undated";
            $anchor_time = "0000-undated";
        }

        # generate an intra-page link label
        my ( $label, $count );
        $count = 0;
        while ( ( $label = $anchor_time . "-" . sprintf( "%03d", $count ) )
            and defined $label_hash{$label} )
        {
            $count++;
        }
        $label_hash{$label} = 1;

        # generate data record for output
        $self->data->add_record( $time_str, $title, priority($item),
            expired($item), $pos, $label, $url_prefix . "#" . $label,
            $category,      $text );
        $pos++;
    }
    return;
}

#
# utility functions
#

# function to detect if a news entry is expired
sub expired
{
    my ($entry) = @_;
    return 0 if not exists $entry->{expires};
    return 0 if not defined $entry->{expires};
    return $entry->{expires} < $now;
}

# function to get the priority value from
sub priority
{
    my ($entry) = @_;

    return 999 if not exists $entry->{posted};
    return 999 if not defined $entry->{posted};
    my $age   = ( $entry->{posted}->subtract_datetime($now) )->delta_days();
    my $bonus = 0;

    if ( $age <= 2 ) {
        $bonus -= 2 - $age;
    }
    if (    ( defined $entry->{category} )
        and ( defined $cat_priorities->{ $entry->{category} } ) )
    {
        my $cat_pri =
            ( exists $cat_priorities->{ $entry->{category} } )
            ? $cat_priorities->{ $entry->{category} }
            : 0;
        return $cat_pri + $age * 0.025 + $bonus;
    } else {
        return $cat_priorities->{"default"} + $age * 0.025 + $bonus;
    }
}

1;
__END__
# POD docs follow

=head1 FILE FORMAT

The WebFetch::Input::SiteNews data format is used to set up news for the
local web site and allow other sites to import it via WebFetch.
The file is plain text containing comments and the news items.

There are three forms of outputs generated from these news files.

The I<"short news" output> is a small number (5 by default)
of HTML text and links used for display in a small news window.
This list takes into account expiration dates and
priorities to pick which news entries are displayed and in what order.

The I<"long news" output> lists all the news entries chronologically.
It does not take expiration or priority into account.
It is intended for a comprehensive site news list.

The I<export modes> make news items available in formats other web sites
can retrieve to post news about your site.  They are chronological
listings that omit expired items.
They do not take priorities into account.

=over 4

=item global parameters

Lines coming before the first news item can set global parameters.

=over 4

=item categories

A line before the first news item beginning with "categories:" contains a 
whitespace-delimited list of news category names in order from highest
to lowest priority.
These priority names are used by the news item attributes and
then for sorting "short news" list items.

=back

=item data lines

Non-blank non-indented non-comment lines are I<data lines>.
Each data line contains a I<name=value> pair.
Each group of consecutive data lines is followed by an arbitrary number
of indented lines which contain HTML text for the news entry.

The recognized attributes are as follows:

=over 4

=item category

used for prioritization, values are set by the categories global parameter
(required)

=item posted

date posted, format is a numerical date YYYYMMDD (required)

=item expires

expiration date, format is a numerical date YYYYMMDD (optional)

=item title

shorter title for use in news exports to other sites,
otherwise the whole news text will be used (optional)

=back

=item text lines

Intended lines are HTML text for the news item.

=item comments

Comments are lines beginning with "#".
They are ignored so they can be used for human-readable information.

=back

Note that the "short news" list has some modifications to
priorities based on the age of the news item,
so that the short list will favor newer items when
they're the same priority.
There is a sorting "priority bonus" for items less than a
day old, which increases their priority by two priority levels.
Day-old news items get a bonus of one priority level.
All news items also "decay" in priority slightly every day,
dropping a whole priority level every 40 days.

=head1 SEE ALSO

L<WebFetch>
L<https://github.com/ikluft/WebFetch>

=head1 BUGS AND LIMITATIONS

Please report bugs via GitHub at L<https://github.com/ikluft/WebFetch/issues>

Patches and enhancements may be submitted via a pull request at L<https://github.com/ikluft/WebFetch/pulls>

=cut
