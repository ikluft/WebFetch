#
# WebFetch::Data::Record - WebFetch Embedding API data record
#
# Copyright (c) 2009 Ian Kluft. This program is free software; you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License Version 3. See  https://www.gnu.org/licenses/gpl-3.0-standalone.html
#

# pragmas to silence some warnings from Perl::Critic
## no critic (Modules::RequireExplicitPackage)
# This solves a catch-22 where parts of Perl::Critic want both package and use-strict to be first
use strict;
use warnings;
use utf8;
## use critic (Modules::RequireExplicitPackage)

package WebFetch::Data::Record;

use strict;
use warnings;
use base qw( WebFetch );

# define exceptions/errors
use Exception::Class (
	'WebFetch::Data::Record::Exception::AutoloadFailure' => {
                isa => 'WebFetch::TracedException',
		alias => 'throw_autoload_fail',
                description => "AUTOLOAD failed to handle function call",
        },

);

# no user-servicable parts beyond this point
=encoding utf8

=head1 NAME

WebFetch::Data::Record - Object for management of WebFetch data records/rows

=head1 SYNOPSIS

C<use WebFetch::Data::Record;>

C<WebFetch::Data::Record->mk_field_accessor( $field_name, ... );
$value = $obj-E<gt>bynum( $num );
$value = $obj->fieldname;
$obj->fieldname( $value );
>

=head1 DESCRIPTION

This module provides read-only access to a single record of the WebFetch data.

=cut

our $AUTOLOAD;

# initialization
sub init
{
	my $self = shift;

	# save parameters
	$self->{obj} = shift;
	$self->{num} = shift;
	$self->{recref} = $self->{obj}{records}[$self->{num}];

	# signal WebFetch that Data subclasses do not provide a fetch function
	$self->{no_fetch} = 1;
	$self->SUPER::init( @_ );

	# make accessor functions
	my $field;
	my $class = ref( $self );
	foreach $field ( @{$self->{obj}{fields}}) {
		$class->mk_field_accessor( $field );
	}
	foreach $field ( keys %{$self->{obj}{wk_names}}) {
		$class->mk_field_accessor( $field );
	}
	
	return $self;
}

# shortcut function to top-level WebFetch object data
sub data { return $_[0]->{obj}; }

=over 4

=item $value = $obj->bynum( $field_num );

Returns the value of the field located by the field number provided.
The first field is numbered 0.

=cut

# get a field by number
sub bynum
{
	my $self = shift;
	my $f = shift;

	WebFetch::debug "bynum $f";
	return $self->{recref}[$f];
}

=item $value = $obj->byname( $field_name );

Returns the value of the named field.

=cut

# get a field by name
sub byname
{
	my $self = shift;
	my $fname = shift;
	my $obj = $self->{obj};
	my $f;

	WebFetch::debug "byname ".(( defined $fname ) ? $fname : "undef");
	( defined $fname ) or return undef;
	if ( exists $obj->{findex}{$fname}) {
		$f = $obj->{findex}{$fname};
		return $self->{recref}[$f];
	}
	return undef;
}

=item $class->mk_field_accessor( $field_name, ... );

Creates accessor functions for each field name provided.

=cut

# make field accessor/mutator functions
sub mk_field_accessor
{
	my $class = shift;
	my $name;
	
	foreach $name ( @_ ) {
		no strict 'refs';
		$class->can( $name ) and next; # skip if function exists!

		# make a closure which keeps value of $name from this call
		# keep generic so code can use more than one data type per run
		*{$class."::".$name} = sub {
			my $self = shift;
			my $value = shift;
			my $obj = $self->{obj};
			my $recref = $self->{recref};
			my $f;
			if ( exists $obj->{findex}{$name}) {
				$f = $obj->{findex}{$name};
				if ( defined $value ) {
					my $tmp = $recref->[$f];
					$recref->[$f] = $value;
					return $tmp;
				} else {
					return $recref->[$f];
				}
			} elsif ( exists $obj->{wk_names}{$name}) {
				my $wk = $obj->{wk_names}{$name};
				$f = $obj->{findex}{$wk};
				if ( defined $value ) {
					my $tmp = $recref->[$f];
					$recref->[$f] = $value;
					return $tmp;
				} else {
					return $recref->[$f];
				}
			} else {
				return undef;
			}
		};
	}
}

=item accessor functions

Accessor functions are created for field names and
well-known names as they are defined.

So a field named "title" can be accessed by an object method of the same
name, like $obj->title .

=back

=cut

# AUTOLOAD function to provide field accessors/mutators
sub AUTOLOAD
{
	my $self = shift;
	my $type = ref($self) or throw_autoload_fail "self is not an object";

	my $name = $AUTOLOAD;
	$name =~ s/.*://;   # strip fully-qualified portion, just want function

	# decline all-caps names - reserved for special Perl functions
	( $name =~ /^[A-Z]+$/ ) and return;

	WebFetch::debug __PACKAGE__."::AUTOLOAD $name";
	if (( exists $self->{obj}{findex}{$name})
		or ( exists $self->{obj}{wk_names}{$name}))
	{
		$type->mk_field_accessor( $name );
                return $self->$name(@_);
	} else {
		throw_autoload_fail "no such function or field $name";
	}
}

1;
__END__

=head1 SEE ALSO

L<WebFetch>
L<https://github.com/ikluft/WebFetch>

=head1 BUGS AND LIMITATIONS

Please report bugs via GitHub at L<https://github.com/ikluft/WebFetch/issues>

Patches and enhancements may be submitted via a pull request at L<https://github.com/ikluft/WebFetch/pulls>

=cut
