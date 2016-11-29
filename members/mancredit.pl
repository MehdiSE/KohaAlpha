#!/usr/bin/perl

#written 11/1/2000 by chris@katipo.oc.nz
#script to display borrowers account details


# Copyright 2000-2002 Katipo Communications
# Copyright 2010 BibLibre
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

use C4::Auth;
use C4::Output;
use CGI qw ( -utf8 );

use C4::Members;
use C4::Branch;
use C4::Accounts;
use C4::Items;
use C4::Members::Attributes qw(GetBorrowerAttributes);
use Koha::Patron::Images;

my $input=new CGI;
my $flagsrequired = { borrowers => 1, updatecharges => 1 };

my $borrowernumber=$input->param('borrowernumber');

#get borrower details
my $data=GetMember('borrowernumber' => $borrowernumber);
my $add=$input->param('add');

if ($add){
    if ( checkauth( $input, 0, $flagsrequired, 'intranet' ) ) {
        my $barcode = $input->param('barcode');
        my $itemnum;
        if ($barcode) {
            $itemnum = GetItemnumberFromBarcode($barcode);
        }
        my $desc    = $input->param('desc');
        my $note    = $input->param('note');
        my $amount  = $input->param('amount') || 0;
        $amount = -$amount;
        my $type = $input->param('type');
        manualinvoice( $borrowernumber, $itemnum, $desc, $type, $amount, $note );
        print $input->redirect("/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber");
    }
} else {
    my ($template, $loggedinuser, $cookie) = get_template_and_user(
        {
            template_name   => "members/mancredit.tt",
            query           => $input,
            type            => "intranet",
            authnotrequired => 0,
            flagsrequired   => { borrowers     => 1,
                                 updatecharges => 'remaining_permissions' },
            debug           => 1,
        }
    );
					  
    if ( $data->{'category_type'} eq 'C') {
        my  ( $catcodes, $labels ) =  GetborCatFromCatType( 'A', 'WHERE category_type = ?' );
        my $cnt = scalar(@$catcodes);
        $template->param( 'CATCODE_MULTI' => 1) if $cnt > 1;
        $template->param( 'catcode' =>    $catcodes->[0])  if $cnt == 1;
    }

    $template->param( adultborrower => 1 ) if ( $data->{category_type} eq 'A' );
    my $patron_image = Koha::Patron::Images->find($data->{borrowernumber});
    $template->param( picture => 1 ) if $patron_image;

    if (C4::Context->preference('ExtendedPatronAttributes')) {
        my $attributes = GetBorrowerAttributes($borrowernumber);
        $template->param(
            ExtendedPatronAttributes => 1,
            extendedattributes => $attributes
        );
    }

    $template->param(%$data);

    $template->param(
        finesview      => 1,
        borrowernumber => $borrowernumber,
        categoryname   => $data->{'description'},
        branchname     => GetBranchName($data->{'branchcode'}),
        is_child       => ($data->{'category_type'} eq 'C'),
        activeBorrowerRelationship => (C4::Context->preference('borrowerRelationship') ne ''),
        RoutingSerials => C4::Context->preference('RoutingSerials'),
        );
    output_html_with_http_headers $input, $cookie, $template->output;
}
