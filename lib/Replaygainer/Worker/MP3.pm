package Replaygainer::Worker::MP3;

use Moose;

with 'Replaygainer::Worker';

sub work {
    sleep 3;
}

__PACKAGE__->meta->make_immutable;

1;
