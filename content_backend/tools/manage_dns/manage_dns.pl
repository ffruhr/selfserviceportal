#!/usr/bin/perl
use strict;
use PowerDNS::Backend::MySQL;
use Net::IP;
use NetAddr::IP;

sub pdns_connect
{
        my $pdns_conf = {  db_user                 =>      $Conf::pdns_conf{'db_user'},
                        db_pass                 =>      $Conf::pdns_conf{'db_pass'},
                        db_name                 =>      $Conf::pdns_conf{'db_name'},
                        db_port                 =>      $Conf::pdns_conf{'db_port'},
                        db_host                 =>      $Conf::pdns_conf{'db_host'},
                        mysql_print_error       =>      $Conf::pdns_conf{'mysql_print_error'},
                        mysql_warn              =>      $Conf::pdns_conf{'mysql_warn'},
                        mysql_auto_commit       =>      $Conf::pdns_conf{'mysql_auto_commit'},
                        mysql_auto_reconnect    =>      $Conf::pdns_conf{'mysql_auto_reconnect'},
                        lock_name               =>      $Conf::pdns_conf{'lock_name'},
                        lock_timeout            =>      $Conf::pdns_conf{'lock_timeout'}
        };

        return PowerDNS::Backend::MySQL->new($pdns_conf);
}

sub dns_domain_list
{
        my $pdns = &pdns_connect();
        my %table_content;

        my $ip4_select_stmnt = "SELECT ui4_ip FROM user_ip4 WHERE ui4_mit = ?";
        my $ip4_select_sth = $DBH->prepare($ip4_select_stmnt);
        $ip4_select_sth->execute($user_hash{'mit'}) || &abort(DBI->errstr);

        while(my $ip4_ref = $ip4_select_sth->fetchrow_hashref())
        {
                for my $domain(keys(%Community::communities))
                {
                        $table_content{${$pdns->find_record_by_content(\$ip4_ref->{'ui4_ip'}, \$domain)}[0]}{'ip4'} = $ip4_ref->{'ui4_ip'};
                }
        }

        my $ip6_select_stmnt = "SELECT ui6_ip FROM user_ip6 WHERE ui6_mit = ?";
        my $ip6_select_sth = $DBH->prepare($ip6_select_stmnt);
        $ip6_select_sth->execute($user_hash{'mit'}) || &abort(DBI->errstr);

        while(my $ip6_ref = $ip6_select_sth->fetchrow_hashref())
        {
                for my $domain(keys(%Community::communities))
                {
                        $table_content{${$pdns->find_record_by_content(\$ip6_ref->{'ui6_ip'}, \$domain)}[0]}{'ip6'} = $ip6_ref->{'ui6_ip'};
                }
        }

        my $table_part_orig = &load_template('manage_dns', 'dns_domain_list_table_part.htm');

        for my $hostname(keys %table_content)
        {
                my $tpl_part = $table_part_orig;
                $tpl_part =~ s/\$\$hostname\$\$/$hostname/;
                $tpl_part =~ s/\$\$(.+?)\$\$/$table_content{$hostname}{$1}/g;
                $data{'dns_domain_list_tbody'} .= $tpl_part;
        }

        &html_parser('manage_dns', 'dns_domain_list.htm');
}

sub dns_domain_add
{
        my $remote_ip = NetAddr::IP->new(remote_addr());

        for my $community(keys %Community::communities)
        {
                my $selected_community;
                if($remote_ip->version() == 4)
                {
                        my $subnet = NetAddr::IP->new($Community::communities{$community}{'ip4_subnet'});
                        if($remote_ip->within($subnet))
                        {
                                $selected_community = 'selected';
                        }
                }
                elsif($remote_ip->version() == 6)
                {
                        my $subnet = NetAddr::IP->new($Community::communities{$community}{'ip6_subnet'});
                        if($remote_ip->within($subnet))
                        {
                                $selected_community = 'selected';
                        }
                }

                $data{'select_communities'} .= "<option value=\"$Community::communities{$community}{'tld'}\" $selected_community>$Community::communities{$community}{'name'}</option>";
                $data{'select_tld'} .= "<option value=\"$Community::communities{$community}{'tld'}\">.$Community::communities{$community}{'tld'}</option>";
        }

        my $ip4_stmnt = "SELECT * FROM user_ip4 WHERE ui4_mit = ?";
        my $ip4_sth = $DBH->prepare($ip4_stmnt);
        my $ip4_rc = $ip4_sth->execute($user_hash{'mit'}) || &abort(DBI->errstr);

        if($ip4_rc > 0) {
                while(my $ip4_ref = $ip4_sth->fetchrow_hashref()) {
                        $data{'select_ipv4'} .= "<option>$ip4_ref->{'ui4_ip'}</option>";
                }
        }

        my $ip6_stmnt = "SELECT * FROM user_ip6 WHERE ui6_mit = ?";
        my $ip6_sth = $DBH->prepare($ip6_stmnt);
        my $ip6_rc = $ip6_sth->execute($user_hash{'mit'}) || &abort(DBI->errstr);

        if($ip6_rc > 0) {
                while(my $ip6_ref = $ip6_sth->fetchrow_hashref()) {
                        $data{'select_ipv6'} .= "<option>$ip6_ref->{'ui6_ip'}</option>";
                }
        }
  
	&html_parser('manage_dns','dns_domain_add.htm');
}

sub dns_add_record
{
        my $pdns_conf = {  db_user                 =>      $Conf::pdns_conf{'db_user'},
                        db_pass                 =>      $Conf::pdns_conf{'db_pass'},
                        db_name                 =>      $Conf::pdns_conf{'db_name'},
                        db_port                 =>      $Conf::pdns_conf{'db_port'},
                        db_host                 =>      $Conf::pdns_conf{'db_host'},
                        mysql_print_error       =>      $Conf::pdns_conf{'mysql_print_error'},
                        mysql_warn              =>      $Conf::pdns_conf{'mysql_warn'},
                        mysql_auto_commit       =>      $Conf::pdns_conf{'mysql_auto_commit'},
                        mysql_auto_reconnect    =>      $Conf::pdns_conf{'mysql_auto_reconnect'},
                        lock_name               =>      $Conf::pdns_conf{'lock_name'},
                        lock_timeout            =>      $Conf::pdns_conf{'lock_timeout'}
        };

        my $pdns = PowerDNS::Backend::MySQL->new($pdns_conf);

        my %params;
        for(param()) { $params{$_} = param($_); }

        my $return;
        $return->{'status'} = 0;

        if($params{'comm'} eq 'default')
        {
                $return->{'status'} = 1;
                $return->{'msg'} .= "Community muss ausgewählt sein<br>";
        }

        if($params{'record'} eq 'default')
        {
                $return->{'status'} = 1;
                $return->{'msg'} .= "Domain darf nicht leer sein<br>";
        }

        if($params{'domain'} eq 'default')
        {
                $return->{'status'} = 1;
                $return->{'msg'} .= "TLD muss ausgewählt sein<br>";
        }

        if($return->{'status'} == 0)
        {
                if($params{'ip4'} eq 'default')
                {
                        $params{'ip4'} = get_new_ip4($params{'comm'});
                }
                if($params{'ip6'} eq 'default')
                {
                        $params{'ip6'} = get_new_ip6($params{'comm'});
                }

                my @rr4 = ($params{'record'}.'.'.$params{'domain'},'A',$params{'ip4'}, 86400);
                my @rr6 = ($params{'record'}.'.'.$params{'domain'},'AAAA',$params{'ip6'}, 86400);

                if($pdns->add_record(\@rr4, \$params{'domain'}) && $pdns->add_record(\@rr6, \$params{'domain'}))
                {
                        my $ip4_select_stmnt = "SELECT ui4 FROM user_ip4 WHERE ui4_ip = ? && ui4_mit = ?";
                        my $ip4_select_sth = $DBH->prepare($ip4_select_stmnt);
                        my $ip4_select_rc = $ip4_select_sth->execute($params{'ip4'}, $user_hash{'mit'}) || &abort(DBI->errstr);

                        if($ip4_select_rc < 1) { 
                                my $ip4_insert_stmnt = "INSERT INTO user_ip4 SET ui4_ip = ?, ui4_mit = ?";
                                my $ip4_sth = $DBH->prepare($ip4_insert_stmnt);
                                $ip4_sth->execute($params{'ip4'}, $user_hash{'mit'}) || &abort(DBI->errstr);
                        }

                        my $ip6_select_stmnt = "SELECT ui6 FROM user_ip6 WHERE ui6_ip = ? && ui6_mit = ?";
                        my $ip6_select_sth = $DBH->prepare($ip6_select_stmnt);
                        my $ip6_select_rc = $ip6_select_sth->execute($params{'ip6'}, $user_hash{'mit'}) || &abort(DBI->errstr);

                        if($ip6_select_rc < 1) {
                                my $ip6_insert_stmnt = "INSERT INTO user_ip6 SET ui6_ip = ?, ui6_mit = ?";
                                my $ip6_sth = $DBH->prepare($ip6_insert_stmnt);
                                $ip6_sth->execute($params{'ip6'}, $user_hash{'mit'}) || &abort(DBI->errstr);
                        }
                }
                else
                {
                        $return->{'status'} = 1;
                        $return->{'msg'} = "Konnte Eintrag nicht anlegen<br>";
                }

                $return->{'ip4'} = $params{'ip4'};
                $return->{'ip6'} = $params{'ip6'};
                $return->{'record'} = $params{'record'};
                $return->{'tld'} = $params{'domain'};

        }
        else
        {
                print "Content-Type: application/json\n\n";
                print to_json($return);
        }


        print "Content-Type: application/json\n\n";
        print to_json($return);
}

sub get_new_ip4
{
        my($comm) = @_;

        my $pdns_conf = {  db_user                 =>      $Conf::pdns_conf{'db_user'},
                        db_pass                 =>      $Conf::pdns_conf{'db_pass'},
                        db_name                 =>      $Conf::pdns_conf{'db_name'},
                        db_port                 =>      $Conf::pdns_conf{'db_port'},
                        db_host                 =>      $Conf::pdns_conf{'db_host'},
                        mysql_print_error       =>      $Conf::pdns_conf{'mysql_print_error'},
                        mysql_warn              =>      $Conf::pdns_conf{'mysql_warn'},
                        mysql_auto_commit       =>      $Conf::pdns_conf{'mysql_auto_commit'},
                        mysql_auto_reconnect    =>      $Conf::pdns_conf{'mysql_auto_reconnect'},
                        lock_name               =>      $Conf::pdns_conf{'lock_name'},
                        lock_timeout            =>      $Conf::pdns_conf{'lock_timeout'}
        };

        my $pdns = PowerDNS::Backend::MySQL->new($pdns_conf);

        for my $ip_range(@{$Community::communities{$comm}{'ip4_range'}})
        {
                my $ip_manager = Net::IP->new($ip_range);

                while(++$ip_manager)
                {
                        my $current_ip = $ip_manager->ip();
                        if(scalar(@{$pdns->find_record_by_content(\$current_ip, \$comm)}) > 0)
                        {
                                next;
                        }
                        else
                        {
                                return $ip_manager->ip();
                        }
                }
        }

}

sub get_new_ip6
{
        my($comm) = @_;

        my $pdns_conf = {  db_user                 =>      $Conf::pdns_conf{'db_user'},
                        db_pass                 =>      $Conf::pdns_conf{'db_pass'},
                        db_name                 =>      $Conf::pdns_conf{'db_name'},
                        db_port                 =>      $Conf::pdns_conf{'db_port'},
                        db_host                 =>      $Conf::pdns_conf{'db_host'},
                        mysql_print_error       =>      $Conf::pdns_conf{'mysql_print_error'},
                        mysql_warn              =>      $Conf::pdns_conf{'mysql_warn'},
                        mysql_auto_commit       =>      $Conf::pdns_conf{'mysql_auto_commit'},
                        mysql_auto_reconnect    =>      $Conf::pdns_conf{'mysql_auto_reconnect'},
                        lock_name               =>      $Conf::pdns_conf{'lock_name'},
                        lock_timeout            =>      $Conf::pdns_conf{'lock_timeout'}
        };

        my $pdns = PowerDNS::Backend::MySQL->new($pdns_conf);

        for my $ip_range(@{$Community::communities{$comm}{'ip6_range'}})
        {
                my $ip_manager = Net::IP->new($ip_range);

                while(++$ip_manager)
                {
                        my $current_ip = $ip_manager->ip();
                        if(scalar(@{$pdns->find_record_by_content(\$current_ip, \$comm)}) > 0)
                        {
                                next;
                        }
                        else
                        {
                                return $ip_manager->ip();
                        }
                }
        }
}

sub dns_check_record
{
        my $pdns_conf = {  db_user                 =>      $Conf::pdns_conf{'db_user'},
                        db_pass                 =>      $Conf::pdns_conf{'db_pass'},
                        db_name                 =>      $Conf::pdns_conf{'db_name'},
                        db_port                 =>      $Conf::pdns_conf{'db_port'},
                        db_host                 =>      $Conf::pdns_conf{'db_host'},
                        mysql_print_error       =>      $Conf::pdns_conf{'mysql_print_error'},
                        mysql_warn              =>      $Conf::pdns_conf{'mysql_warn'},
                        mysql_auto_commit       =>      $Conf::pdns_conf{'mysql_auto_commit'},
                        mysql_auto_reconnect    =>      $Conf::pdns_conf{'mysql_auto_reconnect'},
                        lock_name               =>      $Conf::pdns_conf{'lock_name'},
                        lock_timeout            =>      $Conf::pdns_conf{'lock_timeout'}
        };

        my $pdns = PowerDNS::Backend::MySQL->new($pdns_conf);

        my %params;
        for(param()) { $params{$_} = param($_) }

        $params{'record'} = $params{'record'}.'.'.$params{'domain'};
        $params{'domain'} =~ s/^\.//;

        my $record_check = $pdns->find_record_by_name(\$params{'record'} , \$params{'domain'});

        my $return;
        if($record_check->[0] && $record_check->[0] != 0)
        {
                $return->{'status'} = 1;
        }
        else
        {
                $return->{'status'} = 0;
        }

        print "Content-Type: application/json\n\n";
        print to_json($return);
}

1;