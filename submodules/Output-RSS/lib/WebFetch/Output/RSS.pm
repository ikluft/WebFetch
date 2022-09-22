# WebFetch::Output::RSS
# ABSTRACT: get headlines for WebFetch from RSS feed
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

package WebFetch::Output::RSS;

use base "WebFetch";

use WebFetch "0.15.3";
use Readonly;
use Carp;
use Try::Tiny;
use XML::RSS;

# no user-servicable parts beyond this point

# register capabilities with WebFetch
__PACKAGE__->module_register( { Options => \@Options, Usage => \$Usage }, "cmdline", "output:rss_out" );

=encoding utf8

=head1 SYNOPSIS

In perl scripts:

C<use WebFetch::Output::RSS;>

From the command line:

C<perl -w -MWebFetch::Output::RSS -e "&fetch_main" --
     [...WebFetch input options...] --dir directory
     --dest_format rss_out --dest dest-path >

=head1 DESCRIPTION

This module saves output via the Perl Template Toolkit.

=over 4

=item $obj->fmt_handler_rss_out( $filename )

This function formats the data according to the Perl Template Toolkit
template provided in the --template parameter.

=back

=cut

# RSS-output format handler
sub fmt_handler_rss_out
{
    my $self     = shift;
    my $filename = shift;

    # TODO
    WebFetch::Exception->throw( error => "unreleased code - function not implemented" );
}

1;
__END__
# POD docs follow

=head1 SEE ALSO

L<WebFetch>
L<https://github.com/ikluft/WebFetch>

=head1 BUGS AND LIMITATIONS

Please report bugs via GitHub at L<https://github.com/ikluft/WebFetch/issues>

Patches and enhancements may be submitted via a pull request at L<https://github.com/ikluft/WebFetch/pulls>

=cut
