package Socialtext::CodeSyntaxPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use Class::Field qw(const);

sub class_id { 'code' }
const class_title    => 'CodeSyntaxPlugin';

our %Brushes = (
    as3 => 'AS3',
    actionscript3 => 'AS3',
    bash => 'Bash',
    shell => 'Bash',
    cf => 'ColdFusion',
    coldfusion => 'ColdFusion',
    csharp => 'CSharp',
    cpp => 'Cpp',
    c => 'Cpp',
    css => 'Css',
    delphi => 'Delphi',
    pascal => 'Delphi',
    diff => 'Diff',
    patch => 'Diff',
    erlang => 'Erlang',
    groovy => 'Groovy',
    js => 'JScript',
    javascript => 'JScript',
    java => 'Java',
    javafx => 'JavaFX',
    perl => 'Perl',
    php => 'Php',
    powershell => 'PowerShell',
    py => 'Python',
    python => 'Python',
    ruby => 'Ruby',
    scala => 'Scala',
    sql => 'Sql',
    vb => 'Vb',
    xml => 'Xml',
    html => 'Xml',
    xhtml => 'Xml',
    xslt => 'Xml',
    yaml => 'Yaml',
    json => 'Yaml',
);

our %Brush_aliases = (
    json => 'yaml',
);

sub register {
    my $self = shift;
    my $registry = shift;
    for my $key (%Brushes) {
        my $pkg = "Socialtext::CodeSyntaxPlugin::Wafl::$key";

        no strict 'refs';
        push @{"$pkg\::ISA"}, 'Socialtext::Formatter::WaflBlock';
        *{"$pkg\::html"} = \&__html__;
        *{"$pkg\::wafl_id"} = sub { "${key}_code" };
        $registry->add(wafl => $pkg->wafl_id => $pkg);
    }
}

sub __html__ {
    my $self = shift;
    my $method = $self->method;
    (my $type = $method) =~ s/^(.+?)_code$/$1/;
    my $string = $self->block_text;
    my $js_base  = "/static/skin/common/javascript/SyntaxHighlighter";
    my $css_base = "/static/skin/common/css/SyntaxHighlighter";
    my $brush = $Socialtext::CodeSyntaxPlugin::Brushes{$type};
    if (my $t = $Brush_aliases{$type}) {
        $type = $t;
    }

    # Skip traversing
    $self->units([]);

    return <<EOT;
<script type="text/javascript" src="$js_base/shCore.js"></script>
<script type="text/javascript" src="$js_base/shBrush${brush}.js"></script>
<link href="$css_base/shCore.css" rel="stylesheet" type="text/css" />
<link href="$css_base/shThemeDefault.css" rel="stylesheet" type="text/css" />
<pre class="brush: $type">
$string
</pre>
<script type="text/javascript">
     SyntaxHighlighter.all()
</script>
EOT
}

1;