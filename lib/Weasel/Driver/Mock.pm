
=head1 NAME

Weasel::Driver::Mock - Weasel driver for testing purposes

=head1 VERSION

0.01

=head1 SYNOPSIS

  use Weasel;
  use Weasel::Session;
  use Weasel::Driver::Mock;

  my %opts = (
    states => [
       { cmd => 'get', args => [ 'http://localhost/index' ] },
       { cmd => 'find', args => [ '//div[@id="your-id"]' ] },
    ],
  );
  my $weasel = Weasel->new(
       default_session => 'default',
       sessions => {
          default => Weasel::Session->new(
            driver => Weasel::Driver::Mock->new(%opts),
          ),
       });

  $weasel->session->get('http://localhost/index');


=head1 DESCRIPTION

This module implements the L<Weasel::DriverRole> protocol,
mimicing a true web driver session. The concept has been
very much inspired by DBD::Mock.

The C<states> attribute of a Weasel::Driver::Mock object contains
a reference to an array of hashes. Each hash describes a C<state>.

   [ {
        cmd => 'get', args => [ 'http://localhost/index' ]
     },
     {
        cmd => 'find', args => [ '//div[@id="help-me"]' ],
        ret => {
           id => 'abc',
        },
     },
     {
        cmd => 'find_all', args => [ '//div' ],
        ret_array => [
           { id => 'abc' },
           { id => 'def' },
        ],
     },
     {
         cmd => 'click', args => [ 'abc' ],
         err => 'Element not visible on the page',
     },
     ...
   ]

=head2 STATES

A state is a hash where its keys have the following meaning:

=over

=item cmd (required)

The name of the function called (e.g. 'find', 'find_all' or 'get').

=item args (optional)

The expected list of arguments passed to the called function. When not
provided, the arguments of the call are not validated.

Note that this list excludes any file handles passed in.

=item ret (or ret_array) (optional)

Specifies the value to be returned from the called function, or,
in case of C<ret_array>, the values to be returned.

=item err (optional)

When a state specifies an C<err> key, the called function (if it is
the correct one) die with the value as the argument to C<die>.

=item content (or content_base64 or content_from_file) (optional)

Provides the content to be written to the file handle when the called
function accepts a file handle argument.

The string provided as value of C<content> will be printed to the handle.
The string provided as the value of C<content_base64> will be passed to
C<MIME::Base64::decode>. The decoded content is then written to the handle.
The string provided as the value of C<content_from_file> is taken as a file
name. The content of the file will be copied into the file handle using
C<File::Copy::cp>.

=back


=cut


=head1 DEPENDENCIES


=cut


package Weasel::Driver::Mock;

use strict;
use warnings;

use namespace::autoclean;

use Carp;
use Data::Compare;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Copy "cp";
use Time::HiRes;
use Weasel::DriverRole;

use Moose;
with 'Weasel::DriverRole';

our $VERSION = '0.01';


=head1 ATTRIBUTES

=over

=item states

=cut

has states => (is => 'ro', isa => 'ArrayRef', default => sub { [] });

has _remaining_states => (is => 'rw', isa => 'ArrayRef');

=back

=head1 IMPLEMENTATION OF Weasel::DriverRole

For the documentation of the methods in this section,
see L<Weasel::DriverRole>.

=over

=item implements

=cut

sub implements {
    return '0.02';
}


=item start

A few capabilities can be specified in t/.pherkin.yaml
Some can even be specified as environment variables,
they will be expanded here if present.

=cut

sub start {
    my $self = shift;

    $self->_remaining_states([ @{$self->states} ]);

    return $self->started(1);
}

=item stop

=cut

sub stop {
    my $self = shift;

    carp "Web driver has states left while stop() called"
        if scalar @{$self->_remaining_states};

    return $self->started(0);
}

=item find_all

=cut

sub find_all {
    my ($self, @args) = @_;

    my @rv = $self->_check_state('find_all', \@args);
    return wantarray ? @rv : \@rv;
}

=item get

=cut

sub get {
    my ($self, @args) = @_;

    return $self->_check_state('get', \@args);
}

=item wait_for

=cut

sub wait_for {
    my ($self, $callback, %args) = @_;

    # Do NOT use Selenium::Waiter, it eats all exceptions!
    my $end = time() + $args{retry_timeout};
    my $rv;
    do {
        $rv = $callback->();
        return $rv if $rv;

        sleep $args{poll_delay};
    } while (time() <= $end);

    return;
}


=item clear

=cut

sub clear {
    my ($self, @args) = @_;

    return $self->_check_state('clear', \@args);
}

=item click

=cut

sub click {
    my ($self, @args) = @_;

    return $self->_check_state('click', \@args);
}

=item dblclick

=cut

sub dblclick {
    my ($self, @args) = @_;

    return $self->_check_state('dblclick', \@args);
}

=item execute_script

=cut

sub execute_script {
    my ($self, @args) = @_;

    return $self->_check_state('execute_script', \@args);
}

=item get_attribute($id, $att_name)

=cut

sub get_attribute {
    my ($self, @args) = @_;

    return $self->_check_state('get_attribute', \@args);
}

=item get_page_source($fh)

=cut

sub get_page_source {
    my ($self,$fh) = @_;

    $self->_check_state('get_page_source', [], $fh);
    return;
}

=item get_text($id)

=cut

sub get_text {
    my ($self, @args) = @_;

    return $self->_check_state('get_text', \@args);
}

=item is_displayed($id)

=cut

sub is_displayed {
    my ($self, @args) = @_;

    return $self->_check_state('is_displayed', \@args);
}

=item set_attribute($id, $att_name, $value)

=cut

sub set_attribute {
    my ($self, @args) = @_;

    return $self->_check_state('set_attribute', \@args);
}

=item get_selected($id)

=cut

sub get_selected {
    my ($self, @args) = @_;

    return $self->_check_state('get_selected', \@args);
}

=item set_selected($id, $value)

=cut

sub set_selected {
    my ($self, @args) = @_;

    return $self->_check_state('set_selected', \@args);
}

=item screenshot($fh)

=cut

sub screenshot {
    my ($self,$fh) = @_;

    $self->_check_state('screenshot', [], $fh);
    return;
}

=item send_keys($element_id, @keys)

=cut

sub send_keys {
    my ($self, @args) = @_;

    return $self->_check_state('send_keys', \@args);
}

=item tag_name($elem)

=cut

sub tag_name {
    my ($self, @args) = @_;

    return $self->_check_state('tag_name', \@args);
}

=back

=head1 SUBROUTINES/METHODS

This module implements the following methods in addition to the
Weasel::DriverRole protocol methods:

=over

=item set_wait_timeout

Sets the C<wait_timeut> attribute of the object.

=cut

sub set_wait_timeout {
    my ($self, @args) = @_;
    my ($value) = @args;

    $self->_check_state('set_wait_timeout', \@args);
    return $self->_set_wait_timeout($value);
}

=item set_window_size

Sets the C<window_size> attribute of the object.

=cut

sub set_window_size {
    my ($self, @args) = @_;

    return $self->_check_state('set_window_size', \@args);
}

=back

=cut

# PRIVATE IMPLEMENTATIONS

my $cmp = Data::Compare->new;

sub _check_state {
    my $self = shift;
    my ($cmd, $args, $fh) = @_;

    croak "States exhausted while '$cmd' called"
        if ! @{$self->_remaining_states};

    my $expect = shift @{$self->_remaining_states};
    croak "Mismatch between expected ($expect->{cmd}) and actual ($cmd) driver command"
        if $expect->{cmd} ne $cmd;

    if ($expect->{args}) {
        if (! $cmp->Cmp($expect->{args}, $args)) {
            croak("Mismatch between expected and actual command arguments;"
                  . " expected:\n" . Dumper($expect->{args})
                  . "\ngot:\n" Dumper($args))
        }
    }

    if ($fh) {
        if (defined $expect->{content}) { # empty string is false but defined
            print $fh $expect->{content}
                or croak "Can't write provided content to file handle for command $cmd: $!";
        }
        elsif ($expect->{content_from_file}) {
            cp $expect->{content_from_file}, $fh
                or die "Can't copy $expect->{content_from_file} into file handle for command $cmd: $!";
        }
        elsif ($expect->{content_base64}) {
            print $fh MIME::Base64::decode($expect->{content_base64})
                or croak "Can't write provided base64 content to file handle for command $cmd: $!";
        }
        else {
            croak "Output handle provided, but one of content/content_from_file/content_base64 missing";
        }
    }
    elsif ($expect->{content} or $expect->{content_from_file}
           or $expect->{content_base64}) {
        croak "Content provided for command $cmd, but output handle missing";
    }

    die $expect->{err} if $expect->{err};

    return @{$expect->{ret_array}} if $expect->{ret_array};
    return $expect->{ret};
}


__PACKAGE__->meta()->make_immutable();

=head1 AUTHOR

Erik Huelsmann

=head1 CONTRIBUTORS

Erik Huelsmann

=head1 MAINTAINERS

Erik Huelsmann

=head1 BUGS AND LIMITATIONS

Bugs can be filed in the GitHub issue tracker for the
Weasel::Driver::Mock project:
 L<https://github.com/perl-weasel/weasel-driver-mock/issues>

=head1 SOURCE

The source code repository for Weasel::Driver::Mock is at
 L<https://github.com/perl-weasel/weasel-driver-mock>

=head1 SUPPORT

Community support is available through
L<perl-weasel@googlegroups.com|mailto:perl-weasel@googlegroups.com>.

=head1 LICENSE AND COPYRIGHT

 (C) 2019  Erik Huelsmann

Licensed under the same terms as Perl.

=cut

1;

