#!/usr/bin/perl
use strict;

use Digest::MD5 qw/md5_hex/;

use vars qw ( $BASE $DBH %data %user_hash $cookie %mail);

sub auth_session_check
{
        my $stmnt = "DELETE FROM session WHERE ses_update < now() - interval 3 hour";
        my $sth = $DBH->prepare($stmnt);
        $sth->execute;

        if(param('do') eq 'login_ex')
        {
            &login_ex();
            exit;
        }
        elsif(param('do') eq 'register')
        {
            &register();
            exit;
        }
        elsif(param('do') eq 'register_ex')
        {
            &register_ex();
            exit;
        }
        elsif(param('do') eq 'activation')
        {
            &activate_user();
            exit;
        }
        else
        {
                my %user_data = &read_cookie();

                if($user_data{'mit'} == 0)
                {
                        &html_parser('core', 'login.htm');
                        exit;
                }
                else
                {
                        my $stmnt = "UPDATE session SET ses_update = now() WHERE ses = $user_data{'ses'}";
                        my $sth = $DBH->prepare($stmnt);
                        $sth->execute || die $DBH->errstr;
                        $data{'user_name'} = "Willkommen $user_data{'usr_name'}";
						$user_hash{'mit'} = $user_data{'mit'};
                }
        }
}

sub activate_user
{
    my $activation_hash = param('activation');

    my $update_stmnt = "UPDATE mitarbeiter SET mit_active = 'Y' WHERE mit_activation = ?";
    my $update_sth = $DBH->prepare($update_stmnt);
    my $rc = $update_sth->execute($activation_hash) || die DBI->errstr;

    if($rc == 1)
    {
        $data{'status'} = "Aktivierung erfolgreich";
    }
    else
    {
        $data{'status'} = "Es ist ein Fehler aufgetreten.";
    }
    &html_parser('core', 'activation_success.htm');
}

sub register_ex
{
    my %params;
    for(param()) { $params{$_} = param($_); }

    if(&check_mail($params{'login_email'}))
    {
        if($params{'user'} ne '')
        {
            if(&check_username($params{'user'}))
            {
                if($params{'pwd'} ne '')
                {
                    if($params{'pwd'} eq $params{'pwd_retype'})
                    {
                        use MIME::Lite;
                        use Crypt::PBKDF2;

                        my $pbkdf2 = Crypt::PBKDF2->new(
                            hash_class => 'HMACSHA2',
                            hash_args => {
                                    sha_size => 512,
                            },
                            iterations => 1000,      
                            output_len => 50,        
                            salt_len => 8,           
                        );

                        my $pwd = $pbkdf2->generate($params{'pwd'});


                        my $insert_stmnt = "INSERT INTO mitarbeiter
                                            SET
                                                mit_login = ?,
                                                mit_level = 1,
                                                mit_pw = ?,
                                                mit_mail = ?,
                                                mit_active = 'N',
                                                mit_activation = md5(CONCAT(NOW(),?))";
                        my $insert_sth = $DBH->prepare($insert_stmnt);
                        $insert_sth->execute($params{'user'}, $pwd, $params{'login_mail'}, $params{'user'}) || die DBI->errstr;

                        my $id = $insert_sth->{mysql_insertid};

                        my $insert_group_stmnt = "INSERT INTO mitarbeiter_group VALUES($id,1)";
                        my $insert_group_sth = $DBH->prepare($insert_group_stmnt);
                        $insert_group_sth->execute() || die DBI->errstr;


                        my $select_stmnt = "SELECT mit_activation FROM mitarbeiter WHERE mit_login = ?";
                        my $select_sth = $DBH->prepare($select_stmnt);
                        $select_sth->execute($params{'user'}) || die DBI->errstr;

                        my $activation_hash = $select_sth->fetchrow_hashref()->{'mit_activation'};

                        my $mail_content = "Um deinen Account zu aktivieren folge bitte dem Link: http://ssp.freifunk.ruhr/?do=activation&activation=$activation_hash";

                        my $msg = MIME::Lite->new(
                            From     => 'ssp@freifunk-ruhrgebiet.de',
                            To       => $params{'login_email'},
                            Subject  => 'SelfServicePortal - Account - Activation',
                            Data     => $mail_content
                        );

                        $msg->send('smtp', $Conf::mail{'host'}, Timeout => 60, AuthUser => $Conf::mail{'user'}, AuthPass => $Conf::mail{'pwd'}) || die $!;


                        $data{'status'} = "Wir haben dir eine eMail zur Account-Aktivierung an $params{'login_email'} geschickt";
                    }
                    else
                    {
                        $data{'status'} = "Passw&ouml;rter stimmen nicht &uuml;berein";
                    }
                }
                else
                {
                    $data{'status'} = "Passwort darf nicht leer sein";
                }
            }
            else
            {
                $data{'status'} = "Username schon vorhanden";
            }
        }
        else
        {
            $data{'status'} = "Username darf nicht leer sein";
        }
    }
    else 
    {
        $data{'status'} = "Email - Format ung&uuml;ltig";
    }
    
    &html_parser('core', 'register_ex.htm');
}

sub check_username
{
    my($username)= @_;

    my $stmnt = "SELECT mit FROM mitarbeiter WHERE mit_login = ?";
    my $sth = $DBH->prepare($stmnt);
    my $rc = $sth->execute($username) || &abort(DBI->errstr);

    if($rc > 0)
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

sub check_mail
{
    my($mail) = @_;
    use Email::Valid;

    if(Email::Valid->address($mail))
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub register
{
    &html_parser('core', 'register.htm');
}

sub login
{
        &html_parser('core', 'login.htm');
}


sub login_ex
{
        my %parameter;
        my $user = param('user');
        my $pwd = param('pwd');

        my $stmnt = "SELECT * FROM mitarbeiter WHERE mit_login = ? && mit_level = 1 && mit_active = 'Y'";
        my $sth = $DBH->prepare($stmnt);
        my $rc = $sth->execute($user);

        if($rc == 1)
        {
                while(my $ref = $sth->fetchrow_hashref())
                {
#                        $data{'user_name'} = "Willkommen $ref->{'mit_name'}";
			
			use Crypt::PBKDF2;
			my $pbkdf2 = Crypt::PBKDF2->new(
        			hash_class => 'HMACSHA2',
			        hash_args => {
		        	        sha_size => 512,
			        },
			        iterations => 1000,      
			        output_len => 50,        
			        salt_len => 8,           
    			);

			if($pbkdf2->validate($ref->{'mit_pw'}, $pwd))
			{
	                        &write_cookie($ref->{'mit'});
			}
			else
			{
				&html_parser('core', 'login.htm');
		                exit;
			} 
                }
                
                require "$BASE/core/manage_start.pl"; &show_start();
                exit;
        }
        else
        {
                &html_parser('core', 'login.htm');
                exit;
        }
}


sub write_cookie
{
        my $usr = shift;

        my $cookie_ident = int(rand(900000)) + 100000;
        my $cookie_content = "$usr" . 'A' . md5_hex($cookie_ident);


        my $cgi = new CGI;
        $cookie = $cgi->cookie(-name => 'bude_zeit', -value => $cookie_content, -expires => '+3d', -path => '/');
        print $cgi->header(-cookie=>$cookie);

        my $md5_ua = md5_hex($ENV{'HTTP_USER_AGENT'});

        my $stmnt = "INSERT INTO session SET ses_mit = '$usr', ses_key = '$cookie_ident', ses_update = now(), ses_user_agent = '$md5_ua'";
        my $sth = $DBH->prepare($stmnt);
        $sth->execute || die $DBH->errstr;

		$user_hash{'mit'} = $usr;
}


sub read_cookie
{
        my $cgi = new CGI;
        my $cookie = $cgi->cookie(-name => 'bude_zeit');
        my $usr;
        if($cookie =~ /^(\d+?)A(.+?)$/)
        {
                $usr = $1;

                my $stmnt = "SELECT * FROM session JOIN mitarbeiter ON ses_mit = mit WHERE ses_mit = $usr AND md5(ses_key) = '$2' AND mit_level = 1";
                my $sth = $DBH->prepare($stmnt);
                my $rc = $sth->execute;
                my %ses_data;

                while(my $ref = $sth->fetchrow_hashref()){%ses_data = %{$ref}}
                if($ses_data{ses_user_agent} eq md5_hex($ENV{'HTTP_USER_AGENT'}))
                {
                        return %ses_data;
                }
                else
                {
                        $ses_data{'mit'} = 0;
                        return %ses_data;
                }
        }
}


sub back_logout
{
        my %usr_data = &read_cookie;

        my $stmnt = "DELETE FROM session WHERE ses = $usr_data{'ses'}";
        my $sth = $DBH->prepare($stmnt);
        $sth->execute || die $DBH->errstr;

        my $cgi = new CGI;
        $cookie = $cgi->cookie(-name => 'bude_zeit', -value => 'logout', -expires => '+1s', -path => '/');
        print $cgi->header(-cookie=>$cookie);


        &login;
}

1;
