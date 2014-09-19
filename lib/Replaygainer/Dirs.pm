package Replaygainer::Dirs;

use Modern::Perl;
use namespace::autoclean;

use Moose;
use Data::Dumper;

use Replaygainer::DirWithState;

has dirs => (is => 'ro', isa => 'HashRef[DirWithState]');

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    return $class->$orig( dirs => {} );
};

sub get_fresh_dirs {
    my $self = shift;
    
    return grep {!$_->can_be_processed} values %{$self->dirs};
}

sub get_processable_dirs {
    my $self = shift;

    return grep {$_->can_be_processed} values %{$self->dirs};
}

sub get_processable_dir {
    my $self = shift;

    foreach my $dir (values %{$self->dirs}) {
        return $dir if $dir->can_be_processed;
    }
}

sub add {
    my $self = shift;
    my $dir = shift;

    $self->dirs->{$dir->path} = $dir unless defined $self->dirs->{$dir->path};
}

sub path_known {
    my $self = shift;
    my $path = shift;

    return defined $self->dirs->{$path};
}

__PACKAGE__->meta->make_immutable;

1;
