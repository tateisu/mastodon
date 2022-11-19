#!/usr/bin/perl
use strict;
use warnings;
use feature qw(say);
use Image::Info qw(image_info dim);
use Data::Dump qw(dump);

my $inFile = shift or die "usage: $0 infile\n";

my $bytes;
{
	open(my $fh,"<:raw",$inFile) or die "$inFile $!";
	local $/ = undef;
	$bytes = <$fh>;
	close($fh) or die "$inFile $!";
}

my $pos = 0;
sub readBytes($){
	my($len)=@_;
	my $rv = substr($bytes,$pos,$len);
	$pos += length $rv;
	return $rv;
}

my($zero,$type,$numImage)= unpack "vvv",readBytes 6;
say "zero=$zero, type=$type, numImage=$numImage";

for (my $i = 0; $i < $numImage; ++$i){
	my($w,$h,$c,$reserved,$plane,$bits,$size,$offset)=
		unpack "CCCCvvVV",readBytes 16;
	say "dic[$i]: w=$w,h=$h,c=$c,reserved=$reserved,plane=$plane,bits=$bits,size=$size,offset=$offset";
	
	my $imageBytes = substr($bytes,$offset,$size);
	my $header = substr($imageBytes,0,2);
	say $header;
	if( $imageBytes =~ /\ABM/ ){
        say "BITMAPFILEHEADER";
    }else{
    	my $info = image_info( \$imageBytes );
    	say dump $info;
    }
}

