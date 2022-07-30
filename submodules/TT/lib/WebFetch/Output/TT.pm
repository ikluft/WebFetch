# WebFetch::Output::TT
# ABSTRACT: save data from WebFetch via the Perl Template Toolkit
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

package WebFetch::Output::TT;

use strict;
use base "WebFetch";

use Carp;
use Template;

# define exceptions/errors
use Exception::Class (
	"WebFetch::Output::TT::Exception::Template" => {
		isa => "WebFetch::TracedException",
		alias => "throw_template",
		description => "error during template processing",
	},

);

=encoding utf8

=cut

# set defaults
my @Options = ( "template=s", "tt_include:s" );
my $Usage = "--template template-file [--tt_include include-path]";

# no user-servicable parts beyond this point

# register capabilities with WebFetch
__PACKAGE__->module_register( {Options => \@Options, Usage => \$Usage}, "cmdline", "output:tt" );

=head1 SYNOPSIS

In perl scripts:

C<use WebFetch::Output::TT;>

From the command line:

C<perl -w -MWebFetch::Output::TT -e "&fetch_main" --
     [...WebFetch input options...] --dir directory
     --dest_format tt --dest dest-path --template tt-file >

=head1 DESCRIPTION

This module saves output via the Perl Template Toolkit.

=over 4

=item $obj->fmt_handler_tt( $filename )

This function formats the data according to the Perl Template Toolkit
template provided in the --template parameter.

=back

=cut

# Perl Template Toolkit format handler
sub fmt_handler_tt
{
	my $self = shift;
	my $filename = shift;
	my $output;

        # configure and create template object
        my %tt_config = (
                ABSOLUTE => 1,
                RELATIVE => 1,
        );
        if ( exists $self->{tt_include}) {
                $tt_config{INCLUDE_PATH} = $self->{tt_include}
        }
        my $template = Template->new( \%tt_config );

        # process template
        $template->process( $self->{template}, { data => $self->{data}},
		\$output, { binmode => ':utf8'} )
		or throw_template $template->error();

	$self->raw_savable( $filename, $output );
	return 1;
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
