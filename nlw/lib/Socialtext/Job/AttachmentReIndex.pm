package Socialtext::Job::AttachmentReIndex;
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job::AttachmentIndex';

override 'retry_delay' => sub {12 * 60 * 60};
override 'max_retries' => sub {14};

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::Job::AttachmentReIndex - do it again

=head1 SYNOPSIS

  use Socialtext::JobCreator;
  Socialtext::JobCreator->index_attachment(
    $attachment, $config,
    attachment_job_class => 'Socialtext::Job::AttachmentReIndex'
  );

=head1 DESCRIPTION

Exactly like AttachmentIndex but with retries.

=cut