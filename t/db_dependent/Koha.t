#!/usr/bin/perl
#
# This is to test C4/Koha
# It requires a working Koha database with the sample data

use Modern::Perl;
use C4::Context;
use Koha::DateUtils qw(dt_from_string);
use Koha::AuthorisedValue;

use Test::More tests => 9;
use DateTime::Format::MySQL;

BEGIN {
    use_ok('C4::Koha', qw( :DEFAULT GetDailyQuote GetItemTypesByCategory GetItemTypesCategorized));
    use_ok('C4::Members');
}

my $dbh = C4::Context->dbh;
$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

subtest 'Authorized Values Tests' => sub {
    plan tests => 7;

    my $data = {
        category            => 'CATEGORY',
        authorised_value    => 'AUTHORISED_VALUE',
        lib                 => 'LIB',
        lib_opac            => 'LIBOPAC',
        imageurl            => 'IMAGEURL'
    };


# Insert an entry into authorised_value table
    my $insert_success = Koha::AuthorisedValue->new(
        {   category         => $data->{category},
            authorised_value => $data->{authorised_value},
            lib              => $data->{lib},
            lib_opac         => $data->{lib_opac},
            imageurl         => $data->{imageurl}
        }
    )->store;
    ok( $insert_success, "Insert data in database" );


# Tests
    SKIP: {
        skip "INSERT failed", 4 unless $insert_success;

        is ( GetAuthorisedValueByCode($data->{category}, $data->{authorised_value}), $data->{lib}, "GetAuthorisedValueByCode" );

        my $sortdet=C4::Members::GetSortDetails("lost", "3");
        is ($sortdet, "Lost and Paid For", "lost and paid works");

        my $sortdet2=C4::Members::GetSortDetails("loc", "child");
        is ($sortdet2, "Children's Area", "Child area works");

        my $sortdet3=C4::Members::GetSortDetails("withdrawn", "1");
        is ($sortdet3, "Withdrawn", "Withdrawn works");
    }

# Clean up
    if($insert_success){
        my $query = "DELETE FROM authorised_values WHERE category=? AND authorised_value=? AND lib=? AND lib_opac=? AND imageurl=?;";
        my $sth = $dbh->prepare($query);
        $sth->execute($data->{category}, $data->{authorised_value}, $data->{lib}, $data->{lib_opac}, $data->{imageurl});
    }

    SKIP: {
        eval { require Test::Deep; import Test::Deep; };
        skip "Test::Deep required to run the GetAuthorisedValues() tests.", 2 if $@;
        Koha::AuthorisedValue->new(
            {   category         => 'BUG10656',
                authorised_value => 'ZZZ',
                lib              => 'Z_STAFF',
                lib_opac         => 'A_PUBLIC',
                imageurl         => ''
            }
        )->store;
        Koha::AuthorisedValue->new(
            {   category         => 'BUG10656',
                authorised_value => 'AAA',
                lib              => 'A_STAFF',
                lib_opac         => 'Z_PUBLIC',
                imageurl         => ''
            }
        )->store;

        # the next one sets lib_opac to NULL; in that case, the staff
        # display value is meant to be used.
        Koha::AuthorisedValue->new(
            {   category         => 'BUG10656',
                authorised_value => 'DDD',
                lib              => 'D_STAFF',
                lib_opac         => undef,
                imageurl         => ''
            }
        )->store;

        my $authvals = GetAuthorisedValues('BUG10656');
        cmp_deeply(
            $authvals,
            [
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'AAA',
                    lib => 'A_STAFF',
                    lib_opac => 'Z_PUBLIC',
                    imageurl => '',
                },
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'DDD',
                    lib => 'D_STAFF',
                    lib_opac => undef,
                    imageurl => '',
                },
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'ZZZ',
                    lib => 'Z_STAFF',
                    lib_opac => 'A_PUBLIC',
                    imageurl => '',
                },
            ],
            'list of authorised values in staff mode sorted by staff label (bug 10656)'
        );
        $authvals = GetAuthorisedValues('BUG10656', 1);
        cmp_deeply(
            $authvals,
            [
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'ZZZ',
                    lib => 'A_PUBLIC',
                    lib_opac => 'A_PUBLIC',
                    imageurl => '',
                },
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'DDD',
                    lib => 'D_STAFF',
                    lib_opac => undef,
                    imageurl => '',
                },
                {
                    id => ignore(),
                    category => 'BUG10656',
                    authorised_value => 'AAA',
                    lib => 'Z_PUBLIC',
                    lib_opac => 'Z_PUBLIC',
                    imageurl => '',
                },
            ],
            'list of authorised values in OPAC mode sorted by OPAC label (bug 10656)'
        );
    }

};

subtest 'Itemtype info Tests' => sub {
    like ( getitemtypeinfo('BK')->{'imageurl'}, qr/intranet-tmpl/, 'getitemtypeinfo on unspecified interface returns intranet imageurl (legacy behavior)' );
    like ( getitemtypeinfo('BK', 'intranet')->{'imageurl'}, qr/intranet-tmpl/, 'getitemtypeinfo on "intranet" interface returns intranet imageurl' );
    like ( getitemtypeinfo('BK', 'opac')->{'imageurl'}, qr/opac-tmpl/, 'getitemtypeinfo on "opac" interface returns opac imageurl' );
};

### test for C4::Koha->GetDailyQuote()
SKIP:
    {
        eval { require Test::Deep; import Test::Deep; };
        skip "Test::Deep required to run the GetDailyQuote tests.", 1 if $@;

        subtest 'Daily Quotes Test' => sub {
            plan tests => 4;

            SKIP: {

                skip "C4::Koha can't \'GetDailyQuote\'!", 3 unless can_ok('C4::Koha','GetDailyQuote');

# Fill the quote table with the default needed and a spare
$dbh->do("DELETE FROM quotes WHERE id=3 OR id=25;");
my $sql = "INSERT INTO quotes (id,source,text,timestamp) VALUES
(25,'Richard Nixon','When the President does it, that means that it is not illegal.','0000-00-00 00:00:00'),
(3,'Abraham Lincoln','Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.','0000-00-00 00:00:00');";
$dbh->do($sql);

                my $expected_quote = {
                    id          => 3,
                    source      => 'Abraham Lincoln',
                    text        => 'Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.',
                    timestamp   => re('\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}'),   #'0000-00-00 00:00:00',
                };

# test quote retrieval based on id

                my $quote = GetDailyQuote('id'=>3);
                cmp_deeply ($quote, $expected_quote, "Got a quote based on id.") or
                    diag('Be sure to run this test on a clean install of sample data.');

# test quote retrieval based on today's date

                my $query = 'UPDATE quotes SET timestamp = ? WHERE id = ?';
                my $sth = C4::Context->dbh->prepare($query);
                $sth->execute(DateTime::Format::MySQL->format_datetime( dt_from_string() ), $expected_quote->{'id'});

                DateTime::Format::MySQL->format_datetime( dt_from_string() ) =~ m/(\d{4}-\d{2}-\d{2})/;
                $expected_quote->{'timestamp'} = re("^$1");

#        $expected_quote->{'timestamp'} = DateTime::Format::MySQL->format_datetime( dt_from_string() );   # update the timestamp of expected quote data

                $quote = GetDailyQuote(); # this is the "default" mode of selection
                cmp_deeply ($quote, $expected_quote, "Got a quote based on today's date.") or
                    diag('Be sure to run this test on a clean install of sample data.');

# test random quote retrieval

                $quote = GetDailyQuote('random'=>1);
                ok ($quote, "Got a random quote.");
            }
        };
}


subtest 'ISBN tests' => sub {
    plan tests => 6;

    my $isbn13  = "9780330356473";
    my $isbn13D = "978-0-330-35647-3";
    my $isbn10  = "033035647X";
    my $isbn10D = "0-330-35647-X";
    is( xml_escape(undef), '',
        'xml_escape() returns empty string on undef input' );
    my $str = q{'"&<>'};
    is(
        xml_escape($str),
        '&apos;&quot;&amp;&lt;&gt;&apos;',
        'xml_escape() works as expected'
    );
    is( $str, q{'"&<>'}, '... and does not change input in place' );
    is( C4::Koha::_isbn_cleanup('0-590-35340-3'),
        '0590353403', '_isbn_cleanup removes hyphens' );
    is( C4::Koha::_isbn_cleanup('0590353403 (pbk.)'),
        '0590353403', '_isbn_cleanup removes parenthetical' );
    is( C4::Koha::_isbn_cleanup('978-0-321-49694-2'),
        '0321496949', '_isbn_cleanup converts ISBN-13 to ISBN-10' );

};

subtest 'GetFrameworksLoop() tests' => sub {
    plan tests => 6;

    $dbh->do("DELETE FROM biblio_framework");

    my $frameworksloop = GetFrameworksLoop();
    is ( scalar(@$frameworksloop), 0, 'No frameworks' );

    $dbh->do("INSERT INTO biblio_framework ( frameworkcode, frameworktext ) VALUES ( 'A', 'Third framework'  )");
    $dbh->do("INSERT INTO biblio_framework ( frameworkcode, frameworktext ) VALUES ( 'B', 'Second framework' )");
    $dbh->do("INSERT INTO biblio_framework ( frameworkcode, frameworktext ) VALUES ( 'C', 'First framework'  )");

    $frameworksloop = GetFrameworksLoop();
    is ( scalar(@$frameworksloop), 3, 'All frameworks' );
    is ( scalar ( grep { defined $_->{'selected'} } @$frameworksloop ), 0, 'None selected' );

    $frameworksloop = GetFrameworksLoop( 'B' );
    is ( scalar ( grep { defined $_->{'selected'} } @$frameworksloop ), 1, 'One selected' );
    my @descriptions = map { $_->{'description'} } @$frameworksloop;
    is ( $descriptions[0], 'First framework', 'Ordered result' );
    cmp_deeply(
        $frameworksloop,
        [
            {
                'value' => 'C',
                'description' => 'First framework',
                'selected' => undef,
            },
            {
                'value' => 'B',
                'description' => 'Second framework',
                'selected' => 1,                # selected
            },
            {
                'value' => 'A',
                'description' => 'Third framework',
                'selected' => undef,
            }
        ],
        'Full check, sorted by description with selected val (Bug 12675)'
    );
};

subtest 'GetItemTypesByCategory GetItemTypesCategorized test' => sub{
    plan tests => 7;

    my $insertGroup = Koha::AuthorisedValue->new(
        {   category         => 'ITEMTYPECAT',
            authorised_value => 'Quertyware',
        }
    )->store;

    ok($insertGroup, "Create group Qwertyware");

    my $query = "INSERT into itemtypes (itemtype, description, searchcategory, hideinopac) values (?,?,?,?)";
    my $insertSth = C4::Context->dbh->prepare($query);
    $insertSth->execute('BKghjklo1', 'One type of book', '', 0);
    $insertSth->execute('BKghjklo2', 'Another type of book', 'Qwertyware', 0);
    $insertSth->execute('BKghjklo3', 'Yet another type of book', 'Qwertyware', 0);

    # Azertyware should not exist.
    my @results = GetItemTypesByCategory('Azertyware');
    is(scalar @results, 0, 'GetItemTypesByCategory: Invalid category returns nothing');

    @results = GetItemTypesByCategory('Qwertyware');
    my @expected = ( 'BKghjklo2', 'BKghjklo3' );
    is_deeply(\@results,\@expected,'GetItemTypesByCategory: valid category returns itemtypes');

    # add more data since GetItemTypesCategorized's search is more subtle
    $insertGroup = Koha::AuthorisedValue->new(
        {   category         => 'ITEMTYPECAT',
            authorised_value => 'Varyheavybook',
        }
    )->store;

    $insertSth->execute('BKghjklo4', 'Another hidden book', 'Veryheavybook', 1);

    my $hrCat = GetItemTypesCategorized();
    ok(exists $hrCat->{Qwertyware}, 'GetItemTypesCategorized: fully visible category exists');
    ok($hrCat->{Veryheavybook} &&
       $hrCat->{Veryheavybook}->{hideinopac}==1, 'GetItemTypesCategorized: non-visible category hidden' );

    $insertSth->execute('BKghjklo5', 'An hidden book', 'Qwertyware', 1);
    $hrCat = GetItemTypesCategorized();
    ok(exists $hrCat->{Qwertyware}, 'GetItemTypesCategorized: partially visible category exists');

    my @only = ( 'BKghjklo1', 'BKghjklo2', 'BKghjklo3', 'BKghjklo4', 'BKghjklo5', 'Qwertyware', 'Veryheavybook' );
    @results = ();
    foreach my $key (@only) {
        push @results, $key if exists $hrCat->{$key};
    }
    @expected = ( 'BKghjklo1', 'Qwertyware', 'Veryheavybook' );
    is_deeply(\@results,\@expected, 'GetItemTypesCategorized: grouped and ungrouped items returned as expected.');
};

subtest 'GetItemTypes test' => sub {
    plan tests => 1;
    $dbh->do(q|DELETE FROM itemtypes|);
    $dbh->do(q|INSERT INTO itemtypes(itemtype, description) VALUES ('a', 'aa desc'), ('b', 'zz desc'), ('d', 'dd desc'), ('c', 'yy desc')|);
    my $itemtypes = C4::Koha::GetItemTypes( style => 'array' );
    $itemtypes = [ map { $_->{itemtype} } @$itemtypes ];
    is_deeply( $itemtypes, [ 'a', 'd', 'c', 'b' ], 'GetItemTypes(array) should return itemtypes ordered by description');
};

$dbh->rollback();
