package Socialtext::Handler::Userd;
# @COPYRIGHT@
use Moose;
BEGIN { extends 'Socialtext::WebDaemon'; }
use Socialtext::User;
use Socialtext::WebDaemon::Util; # auto-exports
use Socialtext::Async::Wrapper; # auto-exports
use Socialtext::SQL qw/get_dbh sql_execute sql_singlevalue/;
use Socialtext::UserSet ':const';
use Socialtext::CredentialsExtractor;

use namespace::clean -except => 'meta';

has '+port' => (default => 8084);

has 'extract_q' => (
    is => 'rw', isa => 'Socialtext::Async::WorkQueue',
    lazy_build => 1
);

use constant ProcName => 'st-userd';
use constant Name => 'st-userd';

sub Getopts { }

sub ConfigForDevEnv {
    my ($class, $args) = @_;
}

augment 'run' => sub {
    my $self = shift;
    # nothing to do here yet
    inner();
};

augment 'at_fork' => sub {
    my $self = shift;
    # nothing to do here yet
    inner();
};

augment 'shutdown' => sub {
    my $self = shift;
    if ($self->has_extract_q) {
        # cancel the existing guard and allow pending jobs to be processed
        $self->guards->{extract_queue}->cancel();
        $self->extract_q->shutdown_nowait();
    }
    inner();
};

my $CRLF = "\015\012";
sub handle_request {
    my ($self,$req) = @_;

    my $path = $req->env->{PATH_INFO};
    if ($path eq '/ping') {
        $req->simple_response(
            "200 Pong",
            qq({"ping":"ok"}),
            'JSON'
        );
    }
    elsif ($path eq '/stuserd') {
        my $params = decode_json(${$req->body});
        # If we've got cached results, use those right away
        # ... *DON'T* block here; this has to be wikkid fast
        # Otherwise, enqueue a worker to extract the results and add it to my
        # cache.
        $self->extract_q->enqueue( [$params, $req] );
    }
    else {
        $req->simple_response(
            "400 Bad Request",
            qq(You send a request this server didn't understand),
        );
    }

    return;
}

sub _build_extract_q {
    my $self = shift;
    Scalar::Util::weaken $self;
    my $wq; $wq = Socialtext::Async::WorkQueue->new(
        name => 'extract',
        prio => Coro::PRIO_LOW(),
        cb => exception_wrapper(sub {
            my ($params,$req) = @_;
            return unless $self;
            $self->extract_creds($params,$req);
        }, 'extract queue error'),

        after_shutdown => sub {
            $self->cv->end if $self;
        }
    );

    $self->cv->begin;
    {
        my $wwq = $wq;
        weaken $wwq;
        $self->guards->{extract_queue} = guard {
            $wwq->drop_pending();
            $wwq->shutdown_nowait();
        };
    }
    return $wq;
}

sub extract_creds {
    my ($self, $params, $req) = @_;
    my $result;
    try {
        $result = worker_extract_creds($params);
    }
    catch {
        my $e = $_;
        trace $e;
        st_log()->error('when trying to extract creds: '.$e);
        $result = {
            code => 500,
            body => {
                'error' => 'Could not extract creds',
                'details' => $e,
            },
        };
    };

    my $json = encode_json($result->{body});
    $req->simple_response($result->{code}, \$json, 'JSON');
}

worker_function worker_extract_creds => sub {
    my $params = shift;
    my $creds  = eval {
        Socialtext::CredentialsExtractor->ExtractCredentials($params)
    };
    if ($@) {
        my $e = $@;
        st_log()->error('when trying to extract creds: '.$e);
        return {
            code  => 500,
            error => $@,
        };
    }
    return {
        code => 200,
        body => $creds,
    }
};

1;