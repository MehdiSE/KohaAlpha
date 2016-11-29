#!/usr/bin/perl
# Copyright 2000-2002 Katipo Communications
# Parts copyright 2008-2010 Foundations Bible College
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use strict;
use warnings;
no warnings 'redefine'; # otherwise loading up multiple plugins fills the log with subroutine redefine warnings

use C4::Context;
require C4::Barcodes::ValueBuilder;
use Koha::DateUtils;

my $DEBUG = 0;

sub plugin_javascript {
    my ($dbh,$record,$tagslib,$field_number,$tabloop) = @_;
    my $function_name= "barcode".(int(rand(100000))+1);
    my %args;

    $args{dbh} = $dbh;

# find today's date
    ($args{year}, $args{mon}, $args{day}) = split('-', output_pref({ dt => dt_from_string, dateformat => 'iso', dateonly => 1 }));
    ($args{tag},$args{subfield})       =  GetMarcFromKohaField("items.barcode", '');
    ($args{loctag},$args{locsubfield}) =  GetMarcFromKohaField("items.homebranch", '');

    my $nextnum;
    my $scr;
    my $autoBarcodeType = C4::Context->preference("autoBarcode");
    warn "Barcode type = $autoBarcodeType" if $DEBUG;
    if ((not $autoBarcodeType) or $autoBarcodeType eq 'OFF') {
# don't return a value unless we have the appropriate syspref set
        return ($function_name,
                "<script type=\"text/javascript\">
                // autoBarcodeType OFF (or not defined)
                function Focus$function_name() { return 0;}
                function  Clic$function_name() { return 0;}
                function  Blur$function_name() { return 0;}
                </script>");
    }
    if ($autoBarcodeType eq 'annual') {
        ($nextnum, $scr) = C4::Barcodes::ValueBuilder::annual::get_barcode(\%args);
    }
    elsif ($autoBarcodeType eq 'incremental') {
        ($nextnum, $scr) = C4::Barcodes::ValueBuilder::incremental::get_barcode(\%args);
    }
    elsif ($autoBarcodeType eq 'hbyymmincr') {      # Generates a barcode where hb = home branch Code, yymm = year/month catalogued, incr = incremental number, reset yearly -fbcit
        ($nextnum, $scr) = C4::Barcodes::ValueBuilder::hbyymmincr::get_barcode(\%args);
    }

# default js body (if not filled by hbyymmincr)
    $scr or $scr = <<END_OF_JS;
    if (\$('#' + id).val() == '') {
        \$('#' + id).val('$nextnum');
    }
END_OF_JS

        my $js  = <<END_OF_JS;
    <script type="text/javascript">
        //<![CDATA[

    function Clic$function_name(id) {
        $scr
            return 0;
    }
    //]]>
    </script>
END_OF_JS
        return ($function_name, $js);
}
