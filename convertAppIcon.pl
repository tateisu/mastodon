#!/usr/bin/perl

## requirement: sudo apt-get install librsvg2-bin

use strict;
use warnings;
use feature qw(say);

my $inFile = "app/javascript/images/app-icon-juggler.svg";
my $outDir = "app/javascript/icons";

sub convertAppIcon($$){
    my($size,$prefix)=@_;
    my $cmd = qq(rsvg-convert $inFile --format=png -w $size -h $size --output=$outDir/$prefix${size}x${size}.png);
    say $cmd;
    system($cmd) and die;
}

# apple
for my $size ( 57, 60, 72, 76, 114, 120, 144, 152, 167, 180, 1024 ){
    convertAppIcon($size,"apple-touch-icon-");
}

# android
for my $size ( 36, 48, 72, 96, 144, 192, 256, 384, 512 ){
    convertAppIcon($size,"android-chrome-");
}
