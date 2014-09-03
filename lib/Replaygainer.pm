package Replaygainer;
# ABSTRACT: Easy to use cmdline tool to apply replaygain to a music collection

$Replaygainer::VERSION = '0.3';

$Replaygainer::EXIFTOOL_TAGS = {
    MIMETYPE => 'MIMEType',
    USER_DEFINED_TEXT => 'UserDefinedText',
    REPLAYGAIN_TRACK_GAIN => [ 'ReplaygainTrackGain', 'replaygain_track_gain' ],
};

1;

