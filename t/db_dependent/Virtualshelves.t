#!/usr/bin/perl

use Modern::Perl;
use Test::More tests => 5;
use DateTime::Duration;

use C4::Context;
use Koha::DateUtils;
use Koha::Virtualshelves;
use Koha::Virtualshelfshares;
use Koha::Virtualshelfcontents;

use t::lib::TestBuilder;

my $builder = t::lib::TestBuilder->new;

my $dbh = C4::Context->dbh;
$dbh->{AutoCommit} = 0;
teardown();

subtest 'CRUD' => sub {
    plan tests => 13;
    my $patron = $builder->build({
        source => 'Borrower',
    });

    my $number_of_shelves = Koha::Virtualshelves->search->count;

    is( $number_of_shelves, 0, 'No shelves should exist' );

    my $shelf = Koha::Virtualshelf->new({
            shelfname => "my first shelf",
            owner => $patron->{borrowernumber},
            category => 1,
        }
    )->store;

    is( ref( $shelf ), 'Koha::Virtualshelf', 'The constructor should return a valid object' );

    $number_of_shelves = Koha::Virtualshelves->search->count;
    is( $number_of_shelves, 1, '1 shelf should have been inserted' );
    is( $shelf->allow_add, 0, 'The default value for allow_add should be 1' );
    is( $shelf->allow_delete_own, 1, 'The default value for allow_delete_own should be 0' );
    is( $shelf->allow_delete_other, 0, 'The default value for allow_delete_other should be 0' );
    is( output_pref($shelf->created_on), output_pref(dt_from_string), 'The creation time should have been set to today' );

    my $retrieved_shelf = Koha::Virtualshelves->find( $shelf->shelfnumber );

    is( $retrieved_shelf->shelfname, $shelf->shelfname, 'Find should correctly return the shelfname' );

    # Insert with the same name
    eval {
        $shelf = Koha::Virtualshelf->new({
                shelfname => "my first shelf",
                owner => $patron->{borrowernumber},
                category => 1,
            }
        )->store;
    };
    is( ref($@), 'Koha::Exceptions::Virtualshelves::DuplicateObject',
        'Exception on duplicate name' );
    $number_of_shelves = Koha::Virtualshelves->search->count;
    is( $number_of_shelves, 1, 'To be sure the number of shelves is still 1' );

    my $another_patron = $builder->build({
        source => 'Borrower',
    });

    $shelf = Koha::Virtualshelf->new({
            shelfname => "my first shelf",
            owner => $another_patron->{borrowernumber},
            category => 1,
        }
    )->store;
    $number_of_shelves = Koha::Virtualshelves->search->count;
    is( $number_of_shelves, 2, 'Another patron should be able to create a shelf with an existing shelfname');

    my $is_deleted = Koha::Virtualshelves->find( $shelf->shelfnumber )->delete;
    is( $is_deleted, 1, 'The shelf has been deleted correctly' );
    $number_of_shelves = Koha::Virtualshelves->search->count;
    is( $number_of_shelves, 1, 'To be sure the shelf has been deleted' );

    teardown();
};

subtest 'Sharing' => sub {
    plan tests => 18;
    my $patron_wants_to_share = $builder->build({
        source => 'Borrower',
    });
    my $share_with_me = $builder->build({
        source => 'Borrower',
    });
    my $just_another_patron = $builder->build({
        source => 'Borrower',
    });

    my $number_of_shelves_shared = Koha::Virtualshelfshares->search->count;
    is( $number_of_shelves_shared, 0, 'No shelves should exist' );

    my $shelf_to_share = Koha::Virtualshelf->new({
            shelfname => "my first shelf",
            owner => $patron_wants_to_share->{borrowernumber},
            category => 1,
        }
    )->store;

    my $shelf_not_to_share = Koha::Virtualshelf->new({
            shelfname => "my second shelf",
            owner => $patron_wants_to_share->{borrowernumber},
            category => 1,
        }
    )->store;

    my $shared_shelf = eval { $shelf_to_share->share };
    is ( ref( $@ ), 'Koha::Exceptions::Virtualshelves::InvalidKeyOnSharing', 'Do not share if no key given' );
    $shared_shelf = eval { $shelf_to_share->share('this is a valid key') };
    is( ref( $shared_shelf ), 'Koha::Virtualshelfshare', 'On sharing, the method should return a valid Koha::Virtualshelfshare object' );

    my $another_shared_shelf = eval { $shelf_to_share->share('this is another valid key') }; # Just to have 2 shares in DB

    $number_of_shelves_shared = Koha::Virtualshelfshares->search->count;
    is( $number_of_shelves_shared, 2, '2 shares should have been inserted' );

    my $is_accepted = eval {
        $shared_shelf->accept( 'this is an invalid key', $share_with_me->{borrowernumber} );
    };
    is( $is_accepted, undef, 'The share should have not been accepted if the key is invalid' );
    is( ref( $@ ), 'Koha::Exceptions::Virtualshelves::InvalidInviteKey', 'accept with an invalid key should raise an exception' );

    $is_accepted = $shared_shelf->accept( 'this is a valid key', $share_with_me->{borrowernumber} );
    ok( defined($is_accepted), 'The share should have been accepted if the key valid' );

    is( $shelf_to_share->is_shared, 1, 'first shelf is shared' );
    is( $shelf_not_to_share->is_shared, 0, 'second shelf is not shared' );

    is( $shelf_to_share->is_shared_with( $patron_wants_to_share->{borrowernumber} ), 0 , "The shelf should not be shared with the owner" );
    is( $shelf_to_share->is_shared_with( $share_with_me->{borrowernumber} ), 1 , "The shelf should be shared with share_with_me" );
    is( $shelf_to_share->is_shared_with( $just_another_patron->{borrowernumber} ), 0, "The shelf should not be shared with just_another_patron" );

    is( $shelf_to_share->remove_share( $just_another_patron->{borrowernumber} ), 0, 'No share should be removed if the share has not been done with this patron' );
    $number_of_shelves_shared = Koha::Virtualshelfshares->search->count;
    is( $number_of_shelves_shared, 2, 'To be sure no shares have been removed' );

    is( $shelf_not_to_share->remove_share( $share_with_me->{borrowernumber} ), 0, '0 share should have been removed if the shelf is not share' );
    $number_of_shelves_shared = Koha::Virtualshelfshares->search->count;
    is( $number_of_shelves_shared, 2, 'To be sure no shares have been removed' );

    is( $shelf_to_share->remove_share( $share_with_me->{borrowernumber} ), 1, '1 share should have been removed if the shelf was shared with this patron' );
    $number_of_shelves_shared = Koha::Virtualshelfshares->search->count;
    is( $number_of_shelves_shared, 1, 'To be sure the share has been removed' );

    teardown();
};

subtest 'Shelf content' => sub {

    plan tests => 18;
    my $patron1 = $builder->build( { source => 'Borrower', } );
    my $patron2 = $builder->build( { source => 'Borrower', } );
    my $biblio1 = $builder->build( { source => 'Biblio', } );
    my $biblio2 = $builder->build( { source => 'Biblio', } );
    my $biblio3 = $builder->build( { source => 'Biblio', } );
    my $biblio4 = $builder->build( { source => 'Biblio', } );
    my $number_of_contents = Koha::Virtualshelfcontents->search->count;

    is( $number_of_contents, 0, 'No content should exist' );

    my $dt_yesterday = dt_from_string->subtract_duration( DateTime::Duration->new( days => 1 ) );
    my $shelf = Koha::Virtualshelf->new(
        {   shelfname    => "my first shelf",
            owner        => $patron1->{borrowernumber},
            category     => 1,
            lastmodified => $dt_yesterday,
        }
    )->store;

    $shelf = Koha::Virtualshelves->find( $shelf->shelfnumber );
    is( output_pref( dt_from_string $shelf->lastmodified ), output_pref($dt_yesterday), 'The lastmodified has been set to yesterday, will be useful for another test later' );
    my $content1 = $shelf->add_biblio( $biblio1->{biblionumber}, $patron1->{borrowernumber} );
    is( ref($content1), 'Koha::Virtualshelfcontent', 'add_biblio to a shelf should return a Koha::Virtualshelfcontent object if inserted' );
    $shelf = Koha::Virtualshelves->find( $shelf->shelfnumber );
    is( output_pref( dt_from_string( $shelf->lastmodified ) ), output_pref(dt_from_string), 'Adding a biblio to a shelf should update the lastmodified for the shelf' );
    my $content2 = $shelf->add_biblio( $biblio2->{biblionumber}, $patron1->{borrowernumber} );
    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 2, '2 biblio should have been inserted' );

    my $content1_bis = $shelf->add_biblio( $biblio1->{biblionumber}, $patron1->{borrowernumber} );
    is( $content1_bis, undef, 'add_biblio should return undef on duplicate' );    # Or an exception ?
    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 2, 'The biblio should not have been duplicated' );

    $shelf = Koha::Virtualshelves->find( $shelf->shelfnumber );
    my $contents = $shelf->get_contents;
    is( $contents->count, 2, 'There are 2 biblios on this shelf' );

    # Patron 2 will try to remove a content
    # allow_add = 0, allow_delete_own = 1, allow_delete_other = 0 => Default values
    my $number_of_deleted_biblios = $shelf->remove_biblios( { biblionumbers => [ $biblio1->{biblionumber} ], borrowernumber => $patron2->{borrowernumber} } );
    is( $number_of_deleted_biblios, 0, 'Patron 2 removed nothing' );
    # Now try with patron 1
    $number_of_deleted_biblios = $shelf->remove_biblios( { biblionumbers => [ $biblio1->{biblionumber} ], borrowernumber => $patron1->{borrowernumber} } );
    is( $number_of_deleted_biblios, 1, 'Patron 1 removed biblio' );

    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 1, 'To be sure the content has been deleted' );

    # allow_delete_own = 0
    $shelf->allow_delete_own(0);
    $shelf->store;
    $number_of_deleted_biblios = $shelf->remove_biblios( { biblionumbers => [ $biblio2->{biblionumber} ], borrowernumber => $patron1->{borrowernumber} } );
    is( $number_of_deleted_biblios, 1, 'Patron 1 removed another biblio' );
    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 0, 'The biblio should have been deleted to the shelf by the patron, it is his own content (allow_delete_own=0)' );
    $shelf->add_biblio( $biblio2->{biblionumber}, $patron1->{borrowernumber} );

    # allow_add = 1, allow_delete_own = 1
    $shelf->allow_add(1);
    $shelf->allow_delete_own(1);
    $shelf->store;

    my $content3 = $shelf->add_biblio( $biblio3->{biblionumber}, $patron2->{borrowernumber} );
    my $content4 = $shelf->add_biblio( $biblio4->{biblionumber}, $patron2->{borrowernumber} );

    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 3, 'The biblio should have been added to the shelf by the patron 2' );

    $number_of_deleted_biblios = $shelf->remove_biblios( { biblionumbers => [ $biblio3->{biblionumber} ], borrowernumber => $patron2->{borrowernumber} } );
    is( $number_of_deleted_biblios, 1, 'Biblio 3 deleted by patron 2' );
    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 2, 'The biblio should have been deleted to the shelf by the patron, it is his own content (allow_delete_own=1) ' );

    # allow_add = 1, allow_delete_own = 1, allow_delete_other = 1
    $shelf->allow_delete_other(1);
    $shelf->store;

    $number_of_deleted_biblios = $shelf->remove_biblios( { biblionumbers => [ $biblio2->{biblionumber} ], borrowernumber => $patron2->{borrowernumber} } );
    is( $number_of_deleted_biblios, 1, 'Biblio 2 deleted by patron 2' );
    $number_of_contents = Koha::Virtualshelfcontents->search->count;
    is( $number_of_contents, 1, 'The biblio should have been deleted to the shelf by the patron 2, even if it is not his own content (allow_delete_other=1)' );

    teardown();
};

subtest 'Shelf permissions' => sub {

    plan tests => 40;
    my $patron1 = $builder->build( { source => 'Borrower', value => { flags => '2096766' } } ); # 2096766 is everything checked but not superlibrarian
    my $patron2 = $builder->build( { source => 'Borrower', value => { flags => '1048190' } } ); # 1048190 is everything checked but not superlibrarian and delete_public_lists
    my $biblio1 = $builder->build( { source => 'Biblio', } );
    my $biblio2 = $builder->build( { source => 'Biblio', } );
    my $biblio3 = $builder->build( { source => 'Biblio', } );
    my $biblio4 = $builder->build( { source => 'Biblio', } );


    my $public_shelf = Koha::Virtualshelf->new(
        {   shelfname    => "my first shelf",
            owner        => $patron1->{borrowernumber},
            category     => 2,
            allow_add          => 0,
            allow_delete_own   => 0,
            allow_delete_other => 0,
        }
    )->store;

    is( $public_shelf->can_be_viewed( $patron1->{borrowernumber} ), 1, 'The owner should be able to view his public list' );
    is( $public_shelf->can_be_viewed( $patron2->{borrowernumber} ), 1, 'Public list should be viewed by someone else' );

    is( $public_shelf->can_be_deleted( $patron1->{borrowernumber} ), 1, 'The owner should be able to delete his list' );
    is( $public_shelf->can_be_deleted( $patron2->{borrowernumber} ), 0, 'Public list should not be deleted by someone else' );

    is( $public_shelf->can_be_managed( $patron1->{borrowernumber} ), 1, 'The owner should be able to manage his list' );
    is( $public_shelf->can_be_managed( $patron2->{borrowernumber} ), 0, 'Public list should not be managed by someone else' );

    is( $public_shelf->can_biblios_be_added( $patron1->{borrowernumber} ), 1, 'The owner should be able to add biblios to his list' );
    is( $public_shelf->can_biblios_be_added( $patron2->{borrowernumber} ), 0, 'Public list should not be modified (add) by someone else' );

    is( $public_shelf->can_biblios_be_removed( $patron1->{borrowernumber} ), 1, 'The owner should be able to remove biblios to his list' );
    is( $public_shelf->can_biblios_be_removed( $patron2->{borrowernumber} ), 0, 'Public list should not be modified (remove) by someone else' );


    $public_shelf->allow_add(1);
    $public_shelf->allow_delete_own(1);
    $public_shelf->allow_delete_other(1);
    $public_shelf->store;

    is( $public_shelf->can_be_viewed( $patron1->{borrowernumber} ), 1, 'The owner should be able to view his public list' );
    is( $public_shelf->can_be_viewed( $patron2->{borrowernumber} ), 1, 'Public list should be viewed by someone else' );

    is( $public_shelf->can_be_deleted( $patron1->{borrowernumber} ), 1, 'The owner should be able to delete his list' );
    is( $public_shelf->can_be_deleted( $patron2->{borrowernumber} ), 0, 'Public list should not be deleted by someone else' );

    is( $public_shelf->can_be_managed( $patron1->{borrowernumber} ), 1, 'The owner should be able to manage his list' );
    is( $public_shelf->can_be_managed( $patron2->{borrowernumber} ), 0, 'Public list should not be managed by someone else' );

    is( $public_shelf->can_biblios_be_added( $patron1->{borrowernumber} ), 1, 'The owner should be able to add biblios to his list' );
    is( $public_shelf->can_biblios_be_added( $patron2->{borrowernumber} ), 1, 'Public list should not be modified (add) by someone else' );

    is( $public_shelf->can_biblios_be_removed( $patron1->{borrowernumber} ), 1, 'The owner should be able to remove biblios to his list' );
    is( $public_shelf->can_biblios_be_removed( $patron2->{borrowernumber} ), 1, 'Public list should not be modified (remove) by someone else' );


    my $private_shelf = Koha::Virtualshelf->new(
        {   shelfname    => "my first shelf",
            owner        => $patron1->{borrowernumber},
            category     => 1,
            allow_add          => 0,
            allow_delete_own   => 0,
            allow_delete_other => 0,
        }
    )->store;

    is( $private_shelf->can_be_viewed( $patron1->{borrowernumber} ), 1, 'The owner should be able to view his list' );
    is( $private_shelf->can_be_viewed( $patron2->{borrowernumber} ), 0, 'Private list should not be viewed by someone else' );

    is( $private_shelf->can_be_deleted( $patron1->{borrowernumber} ), 1, 'The owner should be able to delete his list' );
    is( $private_shelf->can_be_deleted( $patron2->{borrowernumber} ), 0, 'Private list should not be deleted by someone else' );

    is( $private_shelf->can_be_managed( $patron1->{borrowernumber} ), 1, 'The owner should be able to manage his list' );
    is( $private_shelf->can_be_managed( $patron2->{borrowernumber} ), 0, 'Private list should not be managed by someone else' );

    is( $private_shelf->can_biblios_be_added( $patron1->{borrowernumber} ), 1, 'The owner should be able to add biblios to his list' );
    is( $private_shelf->can_biblios_be_added( $patron2->{borrowernumber} ), 0, 'Private list should not be modified (add) by someone else' );

    is( $private_shelf->can_biblios_be_removed( $patron1->{borrowernumber} ), 1, 'The owner should be able to remove biblios to his list' );
    is( $private_shelf->can_biblios_be_removed( $patron2->{borrowernumber} ), 0, 'Private list should not be modified (remove) by someone else' );


    $private_shelf->allow_add(1);
    $private_shelf->allow_delete_own(1);
    $private_shelf->allow_delete_other(1);
    $private_shelf->store;

    is( $private_shelf->can_be_viewed( $patron1->{borrowernumber} ), 1, 'The owner should be able to view his list' );
    is( $private_shelf->can_be_viewed( $patron2->{borrowernumber} ), 0, 'Private list should not be viewed by someone else' );

    is( $private_shelf->can_be_deleted( $patron1->{borrowernumber} ), 1, 'The owner should be able to delete his list' );
    is( $private_shelf->can_be_deleted( $patron2->{borrowernumber} ), 0, 'Private list should not be deleted by someone else' );

    is( $private_shelf->can_be_managed( $patron1->{borrowernumber} ), 1, 'The owner should be able to manage his list' );
    is( $private_shelf->can_be_managed( $patron2->{borrowernumber} ), 0, 'Private list should not be managed by someone else' );

    is( $private_shelf->can_biblios_be_added( $patron1->{borrowernumber} ), 1, 'The owner should be able to add biblios to his list' );
    is( $private_shelf->can_biblios_be_added( $patron2->{borrowernumber} ), 1, 'Private list could be modified (add) by someone else # individual check done later' );

    is( $private_shelf->can_biblios_be_removed( $patron1->{borrowernumber} ), 1, 'The owner should be able to remove biblios to his list' );
    is( $private_shelf->can_biblios_be_removed( $patron2->{borrowernumber} ), 1, 'Private list could be modified (remove) by someone else # individual check done later' );

    teardown();
};

subtest 'Get shelves' => sub {
    plan tests => 4;
    my $patron1 = $builder->build({
        source => 'Borrower',
    });
    my $patron2 = $builder->build({
        source => 'Borrower',
    });

    my $private_shelf1_1 = Koha::Virtualshelf->new({
            shelfname => "private shelf 1 for patron 1",
            owner => $patron1->{borrowernumber},
            category => 1,
        }
    )->store;
    my $private_shelf1_2 = Koha::Virtualshelf->new({
            shelfname => "private shelf 2 for patron 1",
            owner => $patron1->{borrowernumber},
            category => 1,
        }
    )->store;
    my $private_shelf2_1 = Koha::Virtualshelf->new({
            shelfname => "private shelf 1 for patron 2",
            owner => $patron2->{borrowernumber},
            category => 1,
        }
    )->store;
    my $public_shelf1_1 = Koha::Virtualshelf->new({
            shelfname => "public shelf 1 for patron 1",
            owner => $patron1->{borrowernumber},
            category => 2,
        }
    )->store;
    my $public_shelf1_2 = Koha::Virtualshelf->new({
            shelfname => "public shelf 2 for patron 1",
            owner => $patron1->{borrowernumber},
            category => 2,
        }
    )->store;

    my $private_shelves = Koha::Virtualshelves->get_private_shelves;
    is( $private_shelves->count, 0, 'Without borrowernumber given, get_private_shelves should not return any shelf' );
    $private_shelves = Koha::Virtualshelves->get_private_shelves({ borrowernumber => $patron1->{borrowernumber} });
    is( $private_shelves->count, 2, 'get_private_shelves should return all shelves for a given patron' );

    $private_shelf2_1->share('a key')->accept('a key', $patron1->{borrowernumber});
    $private_shelves = Koha::Virtualshelves->get_private_shelves({ borrowernumber => $patron1->{borrowernumber} });
    is( $private_shelves->count, 3, 'get_private_shelves should return all shelves for a given patron, even the shared ones' );

    my $public_shelves = Koha::Virtualshelves->get_public_shelves;
    is( $public_shelves->count, 2, 'get_public_shelves should return all public shelves, no matter who is the owner' );

    teardown();
};

sub teardown {
    $dbh->do(q|DELETE FROM virtualshelfshares|);
    $dbh->do(q|DELETE FROM virtualshelfcontents|);
    $dbh->do(q|DELETE FROM virtualshelves|);
}
