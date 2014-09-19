package Replaygainer::AudioFileInfo;

use Modern::Perl;
use namespace::autoclean;

use Moose;
use MooseX::Types::Path::Class qw(Dir File);

use Replaygainer;
use Replaygainer::Util qw(zip2);
use Data::Dumper qw(Dumper);

has 'mimetype'              => (is => 'ro', isa => 'Str',  required => 1);
has 'dir'                   => (is => 'ro', isa => 'Path::Class::Dir',  required => 1, coerce => 1);
has 'file'                  => (is => 'ro', isa => 'Path::Class::File', required => 1, coerce => 1);
has 'user_defined_text'     => (is => 'ro', isa => 'ArrayRef[Str]');
has 'replaygain_track_gain' => (is => 'ro', isa => 'ArrayRef[Str]');

# replaygain track gain tag in user defined text
my $UDF_REPLAYGAIN_TRACK_GAIN_TAG = '((replaygain_track_gain))';

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    my $param = shift;

    sub extract_arrayref {
        my $tag = shift;
        my $param = shift;

        if (!ref($tag)) {
            return [map { $param->{$_} } grep { /$tag/i } sort keys %$param];
        }
        else {
            if (ref($tag) eq 'ARRAY') {
                my $tags_regex = join '|', @$tag;
                return [map { $param->{$_} } grep { /$tags_regex/i } sort keys %$param];
            }
            else {
                die "foooock.\n";
            }
        }
    }

    sub extract_one {
        my $tag = shift;
        my $param = shift;
        my $occurences = grep { /$tag/i } sort keys %$param;

        return $param->{$tag} if $occurences == 1;

        die "Could not extract exactly one value with key '$tag' because $occurences occurences were found.\n";
    }

    return $class->$orig(
        mimetype => extract_one($Replaygainer::EXIFTOOL_TAGS->{MIMETYPE}, $param),
        user_defined_text => extract_arrayref(
            $Replaygainer::EXIFTOOL_TAGS->{USER_DEFINED_TEXT}, $param),
        replaygain_track_gain => extract_arrayref(
            $Replaygainer::EXIFTOOL_TAGS->{REPLAYGAIN_TRACK_GAIN}, $param),
        dir => $param->{dir},
        file => $param->{file},

    );
};

sub BUILD {
    my $self = shift;

    unless ($self->mimetype =~ /audio\//) {
        die sprintf "Can't construct %s from file with mime type '%s'.\n",
            __PACKAGE__, $self->mimetype;
    }
}

sub has_replaygain_track_gain {
    my $self = shift;

    return (grep /$UDF_REPLAYGAIN_TRACK_GAIN_TAG/, @{$self->user_defined_text}
        or grep /\d/, @{$self->replaygain_track_gain});
}

sub full_path {
    my $self = shift;

    return sprintf "%s/%s", $self->dir, $self->file;
}

__PACKAGE__->meta->make_immutable;

1;

