use strict;

use vars qw( $BASE );

sub show_start
{
	my $tpl_menu            = &load_template('core', 'menu.htm');
	my $tpl_menu_part       = &load_template('core', 'menu_part.htm');

	my $top_menu = "";
	my %menu_entry;

	my $stmnt = "SELECT * FROM right_group JOIN mitarbeiter_group ON rgr_grp = mgr_grp WHERE mgr_mit = $user_hash{'mit'}";
	my $sth = $DBH->prepare($stmnt);
        $sth->execute || die DBI->errstr;
	my $rights = $sth->fetchall_hashref(['rgr_do']) || die $!;

	my $stmnt = "SELECT * FROM menu LEFT JOIN do ON men_do = do WHERE men_active = 'Y'";
	my $sth = $DBH->prepare($stmnt);
	$sth->execute || die DBI->errstr;

	my $menu_entry = $sth->fetchall_hashref(['men_sort','men_parent','men']) || die $!;

	foreach my $sort (sort keys %{$menu_entry})
	{
		foreach my $parent_menu (keys %{$menu_entry->{$sort}->{'0'}})
		{
        	        my $menu_parts = "";
			my $sub_menu_counter = 0;

			if($menu_entry->{$sort}->{$parent_menu} ne '')
			{
				foreach my $menu (keys %{$menu_entry->{$sort}->{$parent_menu}})
				{
					if($rights->{$menu_entry->{$sort}->{$parent_menu}->{$menu}->{'men_do'}} ne '')
					{
						$menu_parts .= $tpl_menu_part;
						$menu_parts =~ s/\$\$([a-zA-Z_0-9]+)\$\$/$menu_entry->{$sort}->{$parent_menu}->{$menu}->{$1}/sg;
						$sub_menu_counter++;
					}
				}
			}

			if($sub_menu_counter > 0)
			{
				$top_menu .= $tpl_menu;
				$top_menu =~ s/\$\$menu_part\$\$/$menu_parts/sg;
				$top_menu =~ s/\$\$([a-zA-Z_0-9]+)\$\$/$menu_entry->{$sort}->{'0'}->{$parent_menu}->{$1}/sg;
			}
		}
	}

	$data{'top_menu'} = $top_menu;

        # Startseite anzeigen
        &html_parser('core','start.htm');
}

1;
