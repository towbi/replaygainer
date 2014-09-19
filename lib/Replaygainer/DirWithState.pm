package Replaygainer::DirWithState;

use Modern::Perl;
use namespace::autoclean;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class qw(Dir File);

enum GainModes => [qw(album track)];

has path       => (is => 'ro', isa => 'Path::Class::Dir', required => 1, coerce => 1);
has gain_mode  => (is => 'rw', isa => 'GainModes');
has processing => (is => 'rw', isa => 'Bool');
has processed  => (is => 'rw', isa => 'Bool');

sub can_be_processed {
    my $self = shift;

    return (defined $self->gain_mode and not $self->processed);
}

__PACKAGE__->meta->make_immutable;

1;
