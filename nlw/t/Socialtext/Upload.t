#!perl
use warnings;
use strict;
use Test::Socialtext tests => 43;
use Test::Socialtext::Fatal;
use Socialtext::SQL qw/:txn :exec :time/;
use File::Temp qw/tempdir tempfile/;
use File::Copy qw/copy move/;
use DateTime;

use ok 'Socialtext::Upload';

fixtures(qw(db));

clean_filenames: {
    my $filename = Socialtext::Upload->clean_filename('a.txt');
    is 'a.txt', $filename, 'regular filename set ok';
    $filename = Socialtext::Upload->clean_filename('bab\\a.txt');
    is 'a.txt', $filename, 'pre-backslash trimmed';
    $filename = Socialtext::Upload->clean_filename('bab\\a.txt\\');
    is 'a.txt', $filename, 'trailing backslash trimmed';
    $filename = Socialtext::Upload->clean_filename('bab/a.txt');
    is 'a.txt', $filename, 'pre-slash trimmed';
    $filename = Socialtext::Upload->clean_filename('bab/a.txt/');
    is 'a.txt', $filename, 'trailing slash trimmed';
}

check_fk_constraints: {
    my $sth = sql_execute(q{
        SELECT DISTINCT constraint_name
        FROM information_schema.referential_constraints
        NATURAL JOIN information_schema.constraint_table_usage
        NATURAL JOIN information_schema.constraint_column_usage
        WHERE table_name = 'attachment'
          AND column_name = 'attachment_id'
          AND delete_rule <> 'RESTRICT'
    });
    my $rows = $sth->fetchall_arrayref({}) || [];
    is(@$rows, 0,
        "all FKs on attachment.attachment_id are ON DELETE RESTRICT");
    if (@$rows) {
        diag "\n";
        diag "The following constraints don't specify ON DELETE RESTRICT.\n";
        diag "Please change them so that they do and check Perl codes\n\n";
        diag "* $_->{constraint_name}" for @$rows;
        diag "\n";
    }
}

my $test_body = "Some attachment data\n$^T\n";
my $user = create_test_user();
my $tmp = File::Temp->new(CLEANUP => 1);
print $tmp $test_body;
close $tmp;

my $creation_dt = DateTime->new(
    year => 2010, month => 1, day => 1,
    hour => 0, minute => 0, second => 0,
    nanosecond => '123000000', # to test round-tripping to/from Pg
    time_zone => 'UTC',
);
my $creation_time = sql_format_timestamptz($creation_dt);
my $creation_timestamp = $creation_dt->epoch;

create_fails_without_tempfile: {
    like exception {
        my $blah = Socialtext::Upload->Create(
            creator => $user,
            filename => "fancy pants.txt",
            mime_type => 'text/plain; charset=UTF-8',
        );
    }, qr/temp_filename/, "can't create Uploads without a tempfile";
}

my $ul;
create: {
    is exception { 
        $ul = Socialtext::Upload->Create(
            created_at => $creation_time,
            creator => $user,
            temp_filename => "$tmp",
            filename => "ultra super happy go-time fancy pants.txt",
            mime_type => 'text/plain; charset=UTF-8',
        );
    }, undef, "created upload";
    isa_ok $ul, 'Socialtext::Upload';
    ok $ul->is_temporary, "is temporary";
    is $ul->filename, "ultra super happy go-time fancy pants.txt";
    is $ul->short_name, "ultra_super_happ...txt";
    # doesn't really test much:
    is $ul->clean_filename, "ultra super happy go-time fancy pants.txt";
    ok -f $ul->disk_filename, "file exists in storage";
    is -s $ul->disk_filename, length($test_body),
        "storage file has all the content";
    my $data = do { local (@ARGV,$/) = ($ul->disk_filename); <> };
    is $data, $test_body, "file has exact contents";

    ok $ul->created_at == $creation_dt, "correct DateTime on object";
    is((stat $ul->disk_filename)[9], $creation_timestamp,
        "mtime on disk is correct");

    my $blahb;
    sql_singleblob(\$blahb,q{
        SELECT body FROM attachment WHERE attachment_id = ?
    }, $ul->attachment_id);
    is $blahb, $test_body, "db has all the content";
}

make_permanent_fails: {
    # the idea here is that the calling code will stage the upload then try to
    # do something else.  If that fails, the guard is triggered, otherwise the
    # caller should ->cancel the guard.
    ok $ul->is_temporary;
    is exception {
        sql_txn {
            my $guard = $ul->make_permanent(actor => $user, guard=>1);
            die "rollback $^T\n";
        };
    }, "rollback $^T\n", "make_permanent fails";
    ok $ul->is_temporary, "still temporary";
    ok !-f $ul->disk_filename, "file got removed from storage";
}

make_permanent: {
    unlink $ul->disk_filename; # pretend to be tmpreaper
    ok $ul->is_temporary, "temporary before make_permanent";

    is exception {
        $ul->make_permanent(actor => $user);
    }, undef, "made permanent";

    ok !$ul->is_temporary, "no longer temporary";
    ok -f $ul->disk_filename, "make_permanent cached contents to disk";
    my $data = do { local (@ARGV,$/) = ($ul->disk_filename); <> };
    is $data, $test_body, "slurped contents are good";
    my $data2;
    $ul->binary_contents(\$data2);
    is $data2, $test_body, "binary contents are good";
    is((stat $ul->disk_filename)[9], $creation_timestamp,
        "mtime on cached file is correct");
}

ensure_stored: {
    unlink $ul->disk_filename;

    is exception { $ul->ensure_stored }, undef, "ensured storage";
    ok -f $ul->disk_filename && -s _, "upload restored to disk";
    my $data = do { local (@ARGV,$/) = ($ul->disk_filename); <> };
    is $data, $test_body, "stored contents are good";
    is((stat $ul->disk_filename)[9], $creation_timestamp,
        "mtime on cached file is correct");
}

binary_contents: {
    unlink $ul->disk_filename;
    my $data2;
    is exception { $ul->binary_contents(\$data2) }, undef;
    is $data2, $test_body, "blob is good";
    ok !-f $ul->disk_filename, "file is NOT restored by binary_contents";

    $ul->ensure_stored();
    ok -f $ul->disk_filename, "file was restored by ensure_stored";
    is exception { $ul->binary_contents(\$data2) }, undef;
    is $data2, $test_body, "blob is good after ensure_stored";
    is((stat $ul->disk_filename)[9], $creation_timestamp,
        "mtime on cached file is correct");
}

pass "done";