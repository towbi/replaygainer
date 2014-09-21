package Replaygainer::Worker;

use Moose::Role;

has condvar => (
    is      => 'ro',
    isa     => 'AnyEvent::CondVar',
);

requires 'work';

after work => sub {
    my $self = shift;

    $self->condvar->send();
};

1;
