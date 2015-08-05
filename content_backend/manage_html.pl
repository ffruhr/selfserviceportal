use strict;
use DBI;

use vars qw( %data $DBH %trans $BASE $LANG $cookie );

sub html_parser
{
        my ($verz, $file) = @_;

        if ($file eq '') { &abort("HTML-Seite existiert nicht: $file"); }
        if ($verz eq '') { &abort("Verzeichnis existiert nicht: $verz"); }

        my $template = "$Conf::verz{$verz}/$file";

        open(HTM, $template) or &abort("Unfaehig Datei zu oeffnen: $Conf::verz{$verz}/$file");
        my $htm = join('',<HTM>);
        close(HTM);

        $htm =~ s/\$\$([a-zA-Z_0-9]+)\$\$/$data{$1}/g;
        $htm =~ s/\&\&(\w*)\&(\w*)\&([a-zA-Z0-9\._\/]*)\&\&/show_part($1,$2,$3)/eg;
        $htm =~ s/\&\$(\d*)\&\$/$Conf::trans_adm{$LANG}{$1}/g;

        if ($Conf::intern{'vtemp_retonly'} == 1)
        {
                $Conf::intern{'vtemp_retonly'} = 0;
                return $htm;
        }
	else
        {
		unless($cookie) { print "Content-Type: text/html\n\n"; }
                print "$htm";
        }
}


sub show_part
{
        my($cmd,$p1,$p2) = @_;

        if($cmd eq 'include')
        {
                $Conf::intern{'vtemp_retonly'}=1;
                return html_parser($p1,'/'.$p2);
        }
}


sub load_template
{
	my($verz, $file) = @_;

	if($verz eq '') { &abort("Kein Verzeichnis uebergeben"); }
	if($file eq '') { &abort("Kein Template uebergeben."); }

	my $template = "$Conf::verz{$verz}/$file";

	my $htm = "";
	
	if(-e $template)
	{
		open(HTM, $template) or &abort("Datei kann nicht geoeffnet werden: $template");
		$htm = join('',<HTM>);
		close(HTM);

	}
	else { &abort("Das Template ($template) existiert nicht."); }

	return $htm;
}

1;
