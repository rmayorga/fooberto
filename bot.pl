#!/usr/bin/perl
use warnings;
use strict;
use integer;
use POE;
use POE::Component::IRC;
#use Net::Google; #thiw was replaced by Google::search /jmas
use Google::Search;
use SOAP::Lite;
use WWW::Wikipedia;
use Config::Simple;
use Getopt::Std;
use Pod::POM;
use DBI;
use POSIX qw(strftime);
use LWP::Simple;
use HTML::Entities;
use XML::Simple;
use Net::Identica;
use Encode;

# get the pod of this file
my $parser = Pod::POM->new();
my $pom = $parser->parse_file("bot.pl")
    || die $parser->error();
# examine any warnings raised
foreach my $warning ($parser->warnings()) {
    warn $warning, "\n";
}



=head1 NAME
An irc bot

=head1 DESCRIPTION

This is fooberto, a deeply fun irc robot.

=head2 METHODS

Fooberto implements the following methods:

=cut

# Just one option at this momment
our($opt_c);
getopts('c:');
# this is a config file
# Load Config file
my %bconf;
my $cnfile;
$cnfile = $opt_c || "bot.conf";
Config::Simple->import_from($cnfile, \%bconf);


my $bdbn = "BOT.database";
my $lgfle = "BOT.logfile";

# database should como from the config file TODO
my $dbh = DBI->connect("dbi:SQLite:dbname=$bconf{$bdbn}","","");

my $logfile = $bconf{$lgfle};


# ugly way to have the correct names, /me lazy
my $bchan = "BOT.channel";
my $buname = "BOT.username";
my $bnick = "BOT.nickname";
my $bcomm = "BOT.command";
my $birname = "BOT.ircname";
my $bserv = "BOT.server";

## other ugly option
my $probab = "RESPONSES.probable";
my $factran = "RESPONSES.facts";
my $debbranch = "DEBIAN.branches";

# more ugly options
my $bgkey = "BOT.google_key";
my $bgreferer = "BOT.google_referer";

# and even more ugly options
my $biuser = "IDENTICA.user";
my $bipass = "IDENTICA.pass";

sub CHANNEL () { "$bconf{$bchan}" }

my ($irc) = POE::Component::IRC->spawn();

POE::Session->create(
    inline_states => {
        _start     => \&bot_start,
        irc_001    => \&on_connect,
        irc_public => \&on_public,
	irc_msg    => \&on_public,
        irc_notice    => \&on_notice, 
    },
);

sub bot_start{
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $irc->yield( register => "all" );

# TODO use alternative nicknames
	$irc->yield( connect =>
          { Nick => "$bconf{$bnick}",
            Username => "$bconf{$buname}",
            Ircname  => "$bconf{$birname}",
            Server   => "$bconf{$bserv}",
            Port     => '6667',
          }
    );
}

# Creating object to manage Identi.ca API if configuration variables exist
my $identica;
if (defined ($biuser && $bipass)) {
    $identica = Net::Identica->new(
	    username => $bconf{$biuser},
	    password => $bconf{$bipass}, 
	    source => '', 
	    traits => [qw/ WrapError /]);
    $identica = undef unless $identica->verify_credentials;
} else { $identica = undef; }

# The bot has successfully connected to a server.  Join a channel.
sub on_connect {
    $irc->yield( join => CHANNEL );
}

# The bot has received a public message.  Parse it for commands, and
# respond to interesting things.
sub on_public {
    my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    #sanitize variables
    $nick = $dbh->quote($nick);
    $msg = $dbh->quote($msg);
    #take off apostrofes. This will be added by each insert comand.
    $nick =~ s/\'//g;
    $msg =~ s/\'//g;
    
   # print ouput to screen and also log it
    my $ts = strftime("%Y-%m-%dT%H:%M:%S", localtime);
    print " $ts <$nick:$channel> $msg\n";
#chanlog
    &chanlog("$ts  <$nick> $msg");
# catch users correcting words
# FIXME a user can not  correct himself in a priv channel, and
# is worst if the floods comes to the main channel
    &correctuser($msg, $nick);

#ignoring un-polite-users
    my $ignore = &catchignore("$nick", "$msg");
    if (!$ignore) { $msg = '' }


#log at sqlite to (FIXME use the same chanlog function)
    &dblog("$nick", "$msg");

# karma catcher
    &karmacatch($nick, $msg);
# pipian level catcher
    &pipiancatch($nick, $msg);
    # capture command char (also this should go on the config file)

    if ( ($msg =~ m/^$bconf{$bcomm}/) || ($msg =~ m/^$bconf{$bnick}(,|;|:).+/ ) || ($channel eq $bconf{$bnick}) ) {
	#default'ing usenick, I know, is ugly FIXME
	my $usenick = 'no';
	my $priv = 'no';
	$priv =  "yes" if $channel eq $bconf{$bnick};
	$usenick = "yes" if $msg =~ m/^$bconf{$bnick}(,|;|:).+/;
	$msg =~ s/(^$bconf{$bcomm}|^$bconf{$bnick}(,|;|:)\s+)//;
	
	
	for ($msg) {
		#default ping command
		if ($msg =~ m/^ping/i) {
			&say("pong!", $nick, $usenick, $priv);
		}
		# fortune cookies
		elsif ($msg =~ m/^fortune/i) {
		    my $out = &fortune();
		    &say($out, $nick, $usenick, $priv);
		}
		elsif ($msg =~ s/^google//i) {
		   if (length($msg) >= 1) {
		        my $out = &google($msg);
			&say($out, $nick, $usenick, $priv);
		   }
		}
		elsif ($msg =~ s/^descifrar//) {
		   if (length($msg) >= 1) {
		        my $out = &descifrar($msg);
			if ($out) {
			    &say($out, $nick, $usenick, $priv);
			} else {
			   &say("no soy perfecto, pero creo que $msg esta bien", $nick, $usenick, $priv);
			}
		   }
		}
		elsif ($msg =~ s/^definir//) {
		   if (length($msg) >= 1) {
		        my $out = &definir($msg);
			if ($out) {
			    &say("$out", $nick, $usenick, $priv);
			} else {
			   &say("err, no encontre $msg", $nick, $usenick, $priv);
			}
		   }
		}
		elsif ($msg =~ s/^visto//) {
		   if (length($msg) >= 1) {
			$msg =~ s/\ +//g;
			my @seen = &dbuexist($msg);
			if ($seen[0]) {
			    my $msout = "Parece que $msg, andaba aquí el $seen[0], lo último que salio de su teclado fue «$seen[1]»";
			    &say($msout, $nick, $usenick, $priv);
			} else {
			   &say("ese ser mitologico núnca entro a este antro de perdición", $nick, $usenick, $priv);
			}
		   }
		}
		elsif ($msg =~ s/^karma//) {
		   if (length($msg) >= 1) {
			$msg =~ s/\ +//g;
			my @seen = &dbuexist($msg);
			if ($seen[0]) {
			    my $karma = &getkarma($msg);
			    if ($karma < 0 ) {
				    &say("ese tal $msg esta mal, $karma", $nick, $usenick, $priv);
			    } elsif ( $karma > 0) { 
				    &say("parece que $msg se porta bien, $karma", $nick, $usenick, $priv);
			    } elsif ( $karma == 0 ) { &say("creo que $msg es _neutral_ , $karma", $nick, $usenick, $priv); }
			} 
		   }
		}
		elsif ($msg =~ m/^pipianometro/){
		    $msg =~ m/^pipianometro\s+(\w+)/;
		    my $searchnick = $1;
		    my @seen = &dbuexist($searchnick);
		    if ($seen[0]) {
			my $pipianlvl = &getpipianlvl($searchnick);
			if ($pipianlvl == 0){
			    &say("ese tal $searchnick no anda en cosas raras, lvl: 0", $nick, $usenick, $priv);
			}elsif ($pipianlvl > 0 && $pipianlvl <=3){
			    &say("diría que a $searchnick mas de alguna vez se la ha salido una pipianada, lvl$pipianlvl+", $nick, $usenick, $priv);
			}elsif ($pipianlvl > 3){
			    &say("Este $searchnick es un maricon sin remedio, lvl$pipianlvl+", $nick, $usenick, $priv);
			}
		    }else{
			&say("Ergg aún no conozco ese lado de $searchnick, no me preguntes.", $nick, $usenick, $priv);
		    }

#	&say("ese tal $searchnick es un pipian de nivel: $pipianlvl", $nick, $usenick, $priv);
#		    }
		}
		elsif ($msg =~ m/^aprender que.+es.+/i) {
		   $msg =~ s/aprender//i;
		   my $fact = $msg;
		   my $fulltext = $msg;
		   $fact =~ s/(que\ )|(\ es\ .+)//g;
		   $fact =~ s/^\ +//g;
		   $fulltext =~ s/(que\ $fact\ es)//g;

		   if ((length($fact) >= 1) and (length($fulltext)>=1)) {
			my $getfact = &fffact("$fact");
			if (!$getfact) {
			   &putfact("$fact", "$fulltext", "$nick");
			}
		    } 
		   
		}
		elsif ($msg =~ s/^olvidar//) {
		   $msg =~ s/\ +//g;
		   if (length($msg) >= 1) {
			   my $isfact = &fffact("$msg");
			   if ($isfact) {
			   	&forgetfact($nick, $msg)  #unless( !$isfact);
			   }
		   }
		}
		elsif ($msg =~ s/^identify//) {
		   $msg =~ s/\ +//g;
		   if (length($msg) >= 1) {
			   my $ok = &authen($nick, "$msg");
			   if ($ok) { &say ("password ok", $nick, $usenick, $priv); }
			   else { &say("errr, password equivocado", $nick, $usenick, $priv); }
		   }
		}
		elsif ($msg =~ s/^action//) {
		   my $add;
		   $msg =~ s/^\ +//g;
		   if ($msg =~m/list/) { &actionlist($nick, $usenick, $priv); $add = 'no'; }
		   if ($msg =~s/^random//) { &actionlist($msg, $usenick, $priv, $channel); $add = 'no'; }
		   if ($msg =~s/^search//) { &actionsearch($nick, $usenick, $priv, $channel,$msg); $add = 'no'; }
		   my $check = &checkauth($nick);
                   if (($check) && ($msg =~s/^olvidar//)) {
                       $msg =~ s/\ +//g;
                       &forgetaction($nick, $msg);
                       $add = 'no';
                   }
		   if (($check) && (!$add))  {
		   	if (length($msg) >= 1) {
				&actionadd($msg, $nick)
		  	 }
		   }
		}
		elsif ($msg=~ s/^ignorar//) {
			$msg =~ s/^\ //;
			my $check = &checkauth($nick);
			if($check) {
				&addignore($nick, $msg);
			}

		}
		elsif ($msg=~ s/^perdonar//) {
			$msg =~ s/^\ //;
			my $check = &checkauth($nick);
			if($check) {
				&forgetignore($msg);
			}

		}
		elsif ($msg=~ s/^debian bug//) {
			$msg =~ s/^\ //;
			if (length($msg) >=1 ) {
				my $bug = &querybug($msg);
				&say ($bug, $nick, $usenick, $priv) unless (!$bug);
			}
		}
		elsif ($msg=~ s/^debian version//) {
			$msg =~ s/^\ //;
			if (length($msg) >=1 ) {
				my $pack = &querypack($msg);
				&say ($pack, $nick, $usenick, $priv) unless (!$pack);
			}
		}
		elsif ($msg=~ s/^debian paquete//) {
			$msg =~ s/^\ //;
			if (length($msg) >=1 ) {
				my $pack = &searchpack($msg);
				&say ($pack, $nick, $usenick, $priv) unless (!$pack);
			}
		}
		elsif ($msg =~ s/^quote//) {
		   $msg =~ s/^\ +//g;
		   if (length($msg) >= 1) {
			   my $check = &checkauth($nick);
			   if ($msg =~ s/^add//) {
				   if ($check) {
					   &quoteadd("$msg", $nick);
				   }
			   } elsif ($msg =~ s/^random//) {
				   my $randqu = &quotegetrand();
                                   print "resultado del random $randqu";
				   &say("\" $randqu \"", $nick, $usenick, $priv);
			   } else {
                               my $nick_query = ( split /" "/, $msg )[0];
                               my $nickqu = &quotegetnick($nick_query);
                               if (length($nickqu) >= 1) {
                                   &say("\" $nickqu \"", $nick, $usenick, $priv);
                               }
                           }
		   }
		}
		elsif ($msg =~ s/\?$//) {
		   if (length($msg) >= 1) {
			##probabilities reached from conf_file
			    my @probability ="$bconf{$probab}"; 
			    my @prob = split("//",$probability[0]);
			    &say($prob[ int rand @prob ], $nick, $usenick, $priv) unless ($usenick eq 'no');
			}
		}
		elsif ($msg =~ s/^saludar//) {
			$msg =~ s/^\ +//;
		   if (length($msg) >= 1) {
			   if(&dbuexist($msg)) {
			       my $num = `cat es-words | wc -l`;
			       my $rand = int rand $num;
			       my $gayw = `head -$rand es-words | tail -1`;
			       &say("$msg: gay de $gayw", $nick, 'no', $priv);
			   }
			}
		}
		elsif ($msg =~ s/^calendar//) {
			$msg =~ s/^\ +//;
			my $cnum = `calendar | wc -l`;
			my $crand = int rand $cnum;
			my $calen = `calendar | head -$crand  | tail -1`;
			&say("$calen", $nick, $usenick, $priv);
		}
		elsif ($msg =~ s/^urbano//) {
                   if (length($msg) >= 1) {
                        my $out = &urbano($msg);
                        if ($out) {
                            &say("$out", $nick, $usenick, $priv);
                        } else {
                           &say("err, no encontre $msg", $nick, $usenick, $priv);
                        }
                   }
                }
		elsif ($msg =~ s/^temblor//){
                        $msg =~ s/\ +//g;
			my $out = &temblor($msg);
			if ($out) {
				&say("$out", $nick, $usenick, $priv);
			}else {
				&say("hmmm, ahí no ha temblado en los últimos 7 días", $nick, $usenick, $priv);
			}

		}
		elsif ($msg =~ m/contarle\ a\ \w.+ acerca\ de/) {
			$msg =~ s/contarle\ a\ //;
			$msg =~ s/acerca\ de//;
			$msg =~ s/^\ +//;
			my $target = $msg;
			my $about = $msg;
			$target =~ s/\ \w.+//;
			$target =~ s/\ +$//;
			$about =~ s/^$target\ +//;
			&sayto($target, $about); 
		}
		elsif ($msg =~ m/^identica say (.+)/) {
		    chomp($1);
		    if ($identica) {
			my $text = &identica_say($1);
			&say("les comento que *$nick* dijo en identi.ca: $text", $nick, $usenick, 'no') if $text;
		    } else {
			&say("el plugin de identi.ca no esta configurado :\\", $nick, $usenick, $priv);
		    }
		}
                elsif ($msg =~ s/^nickserv//) {
                    #&say("Autenticando a $nick", $nick, $usenick, $priv);#debug

                    $msg =~ s/^\ +//g;
		   if (length($msg) >= 1) {
                       my @seen = &dbuexist($msg);
                       if ($seen[0]) {
                           $irc->yield( privmsg => "NickServ", "ACC $msg");
                       }
                   }
                    else{
                        #checking with NickServ
                        $irc->yield( privmsg => "NickServ", "ACC $nick");
                    }
		}
		elsif ($msg =~ m/^identica pull$|^identica pull (\w+)/) {
		    chomp($1) if defined $1;
		    if ($identica) {
			my ($user, $dent);
			if ($1) {
			    ($user, $dent) = &identica_pull($1); 
			} else { 
			    ($user, $dent) = &identica_pull();
			}
			if ($user && $dent){
			    &say("en identi.ca \@$user dijo: $dent", $nick, $usenick, $priv);
			} else {
			    unless ($dent) {
				&say("probablemente el usuario \@$user no este registrado en identi.ca :D", $nick, $usenick, $priv);
			    } else {
				&say("ergg un error con mi conexion a identi.ca seguramente :\\", $nick, $usenick, $priv);
			    }
			}
		    } else {
			&say("el plugin de identi.ca no esta configurado :\\", $nick, $usenick, $priv);
		    }
		}
                elsif ($msg =~ s/^help//) {
                   $msg =~ s/\ +//g;
                   my $out =gethelp($msg);
                   if (length($out) >= 1){
                       &say($out, $nick, $usenick, $priv);
                   }
		}
		else {  
			$msg =~ s/^\ +//g;
			$msg =~ s/\'//g;
			my $isfact = &fffact("$msg");
			my $action = $msg;
			my $isaction = &faction($nick, $channel, "$action");
			if (!$isfact) {
				my $foo = 'no';
			} elsif ($isaction) {
				# action commands here
			} else {
				my @probability ="$bconf{$factran}";
				my @prob = split("//",$probability[0]);
				&say("$prob[ int rand @prob ] $msg es $isfact", $nick, $usenick, $priv);

		  	}	
		}
	}
    }

}

sub on_notice{
    my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    #sanitize variables
    $nick = $dbh->quote($nick);
    $msg = $dbh->quote($msg);
    #take off apostrofes. This will be added by each insert comand.
    $nick =~ s/\'//g;
    $msg =~ s/\'//g;

    #&say("Me acaban de informar nick: $nick, msg: $msg", $nick, 'no', 'no');#debug

    my @answer = split(/\s+/, $msg);

    #is this an answer to a ACC request to nickserv? (admin comand)
    if(($nick eq 'NickServ')&&( $answer[1] eq 'ACC' ))
    {
        if($answer[2] == 3){
            &say("$answer[0] se ha autenticado.", $answer[0], 'no', 'no');
            #Here you should do whatever it takes to mark this nick has identified
        }
        else{
            &say("ergg! $answer[0] no se ha autenticado con NickServ.", $answer[0], 'no', 'no');
        }
    }
}

sub sayto {
	my ($nick, $about) =@_;
	my $msg = &fffact("$about"); 
	if ($msg) {
		my @probability ="$bconf{$factran}";
		my @prob = split("//",$probability[0]);
		&say("$prob[ int rand @prob ] $about es $msg", $nick, 'no', 'yes');
	} else { return undef }
}



=over 4

=item calendar

Fechas cercanas, dignas de conmemorar con una cerveza o/.

=item saludar

Sintaxis: saludar nick 
fooberto saluda amablemente por vos 

=item visto

Sintaxis: visto nick 

=item contarle

Sintaxis: contarle a nick tema

=item debian

Las funciones Debian
debian paquete rama package_name 
debian version package_name 
debian bug bug_number : Mostrar info respecto a ese bug 

=cut

# TODO get rid of system commands and use perl
sub searchpack {
    my $pack = shift;
    my $dist = $pack;
    my $packs;
    my $msgout;

    eval #try
    {
        if ($pack =~ m/(^stable)|(^testing)|(^unstable)/) {
            $dist =~ s/\ \w.+//;
            $pack =~ s/^.+\ //;
            foreach (`for i in \$(ls debian-packages/*-$dist.gz) ; do zcat \$i | grep "Package: .*$pack*" ; done`) {
                chomp($_);
                $packs .= $_;
            }
	}
    
	if(!$packs) { return undef }
	$packs =~ s/Package://g;
	$packs =~ s/^\ +//;
	if ($packs eq $pack){ $msgout = "El paquete existe y se llama tal como lo escribiste" }
	else { $msgout = "podría ser: ". substr($packs, 0, 70) . " ...?"; }
    };
    if($@)
    {
        return undef;
    };
    return $msgout;
}

# TODO get rid of system commands and use perl
sub querypack {
    my $pack = shift; ##Put all these in config file TODO
    my @distbranch = "$bconf{$debbranch}";
    my @dists = split("//",$distbranch[0]);
    print @dists;
    my $msgout;
    my $version;

    eval #try
    { 
	foreach (@dists) {
            $version = `for i in \$(ls debian-packages/$_.gz) ; do zcat \$i | grep -A 6 "Package: $pack" | grep Version ; done`;
            if ($version) {
                chomp($version);
                chomp($_);
                $msgout .= " $_->$version";
            }
	}
    };
    if($@) #catch
    {
        return undef;
    };

    return $msgout
}

sub querybug {
    my $bug = shift;
    my $soap;
    my $refbug;
    my $msgout;
    
    eval #try
    {
        $soap = SOAP::Lite->uri('Debbugs/SOAP')->proxy('http://bugs.debian.org/cgi-bin/soap.cgi');
        $refbug = $soap->get_status($bug)->result->{$bug};
    };
    if($@)
    {
        return undef;
    };
    if ($refbug->{id}) {
        $msgout = "paquete: $refbug->{package}, bug: $refbug->{subject}, severidad: $refbug->{severity}, url: http://bugs.debian.org/$bug";
        $msgout .= " resuelto por: $refbug->{done}" unless (!$refbug->{done});
        return $msgout;
    }
    return undef;
}

=item ignorar

Sintaxis: ignorar nick

=cut

sub addignore {
	my ($nick, $msg) = @_;
        my $sth = $dbh->prepare
            ("INSERT INTO igno (nick, date, who, text) VALUES ('$msg', date('now'), '$nick', 'ig')");
        $sth->execute();

}

=item perdonar

Sintaxis: perdonar nick

=cut

sub forgetignore  {
	my $msg = shift;
        my $sth = $dbh->prepare
            ("SELECT rowid from igno where nick='$msg'");
        $sth->execute();
        my $row = $sth->fetchrow;
        $dbh->do("DELETE from igno where rowid='$row'")
}

sub catchignore {
	my ($nick, $msg) = @_;
	my $command;
	my $tmp= $msg;
	if ( ($msg =~ m/^$bconf{$bcomm}/) || ($msg =~ m/^$bconf{$bnick}(,|;|:).+/ ) ) {
		if (&checkignore($nick)) { $command = 1; }
	}
	if ($command) { return undef } else { return $msg }
}

sub checkignore {
	my $nick = shift;
	my $sth = $dbh->prepare
	   ("SELECT date from igno where nick='$nick'");
        $sth->execute();
	my $igno = $sth->fetchrow();
	if ($igno) { return 'yes' }
}

=item action

action list 
action id_accion le_hace_algo_a NICK algo_mas 
action id_accion nick
action random nick
action olvidar id_acccion

=cut

sub actionlist {
	my ($nick, $usenick, $priv, $channel) = @_;; 
	my $who = $nick; 
	$who =~ s/^\w+ //;
	my @rest;
	my $sth = $dbh->prepare
	    ("SELECT COUNT(*) from actions");
	$sth->execute();
	my $rnum = $sth->fetchrow();
	$sth = $dbh->prepare
	    ("SELECT id from actions");
	$sth->execute();
	for (1..$rnum) {
		push (@rest , $sth->fetchrow);
	}

        my $myString = "@rest";
        my $myLength = length($myString);

        if(($priv eq "yes") && ($myLength > 409)) {
            #if is priv -> take care of show the complete list
            my $myStart = 0;
            my $myEnd = 0;
            my $mySubString = "";

            while($myStart < $myLength) {
                $myEnd+=409;
                $mySubString = substr($myString, $myStart, $myEnd);
                &say ($mySubString, "$nick", $usenick, $priv) unless $channel;
                $myStart = $myEnd;
            }
        }
        else {
            #if is not priv -> just show the fist 350 characters
            &say ("@rest", "$nick", $usenick, $priv) unless $channel;
        }
        
	if ($channel) {
		$nick =~ s/^\ //;
		&faction("$nick", $channel, "$rest[int rand @rest] $nick");
	}

}
sub actionadd {
	my ($msg, $nick) = @_;
	my $actid = $msg;
	$actid =~ s/\ \w+.+//;
	my $action = $msg;
	$action  =~ s/^\w+ //;
	return undef unless $msg =~ m/NICK/;
        my $sth = $dbh->prepare
           ("INSERT INTO actions (id, date, who, action) VALUES ('$actid', datetime('now','localtime'), '$nick', '$action')");
        $sth->execute();
}

sub forgetaction {
	my ($nick, $daction) = @_;
	my $sth = $dbh->prepare
	    ("SELECT rowid from actions where id='$daction'");
	$sth->execute();
	my $row = $sth->fetchrow;
	$dbh->do("DELETE from actions where rowid='$row'") unless ($nick eq $daction);

}

sub faction {
	my ($nick, $channel, $action) = @_;
	my $msg = $action;
	my $who = $action;
	$who =~ s/^\w+ //;
	$action =~ s/\ \w+.+//;
	my $sth=$dbh->prepare
	   ("SELECT action from actions where id='$action'");
        $sth->execute();
	my $row = $sth->fetchrow;
	if ($row) {
		if (($msg!~m/\w+ \w+./) | ($msg=~m/$bconf{$bnick}/))  { 
			$row =~ s/NICK/$nick/;
			&doaction("$channel", "$row POR MAJE!");
			return undef
		}
	     $row =~ s/NICK/$who/;
	     &doaction("$channel", "$row");
	} else { return undef }

}


sub actionsearch {
    my ($nick, $usenick, $priv, $channel,$msg) = @_;;

    $msg =~s/\s//;
    my $searchSt = $msg;
    my @rest;

    if(!($searchSt cmp '')){ return  ;}

    my $sth = $dbh->prepare("SELECT COUNT(id) from actions where id like ('%$searchSt%') or action like ('%$searchSt%') ");

    $sth->execute();
    my $rnum = $sth->fetchrow();
    $sth = $dbh->prepare("SELECT id from actions where id like ('%$searchSt%') or action like ('%$searchSt%') ");

    $sth->execute();
    for (1..$rnum) {
	push (@rest , $sth->fetchrow);
    }

    my $myString = "@rest";
    my $myLength = length($myString);

    if(($priv eq "yes") && ($myLength > 409)) {
	            #if is priv -> take care of show the complete list
	my $myStart = 0;
	my $myEnd = 0;
	my $mySubString = "";

	while($myStart < $myLength) {
	    $myEnd+=409;
	    $mySubString = substr($myString, $myStart, $myEnd);
	    &say ($mySubString, "$nick", $usenick, $priv) unless $channel;
	    $myStart = $myEnd;
	}
    }
    else {
	            #if is not priv -> just show the fist 350 characters
	&say ($myString, "$nick", $usenick, $priv) ;
	#    &say ("@rest", "$nick", $usenick, $priv) unless $channel;
    }

    # if ($channel) {
    # 	$nick =~ s/^\ //;
    # 	&faction("$nick", $channel, "$rest[int rand @rest] $nick");
    # }


}


=item quote

quote add the_quote 
quote random 
quote nick 

=cut

sub quotegetrand {
	 my @rest;
	 my $sth = $dbh->prepare
	    ("select COUNT(*) from facts where tipe='quote'");
	 $sth->execute();
	 my $rown = $sth->fetchrow;
	 $sth = $dbh->prepare
	   ("SELECT fulltext from facts where tipe='quote'");
	 $sth->execute();
	 for (1..$rown) {
		 push (@rest, $sth->fetchrow())
	 }
	 my $out = $rest[int rand @rest];
	 return $out;
}

sub quotegetnick {
         my ($nick_query)  = @_;
	 my @rest;
         my $out = "";
	 my $sth = $dbh->prepare
	    ("select COUNT(*) from facts where tipe='quote' and fulltext like('%$nick_query%')");
	 $sth->execute();
	 my $rown = $sth->fetchrow;
	 $sth = $dbh->prepare
	   ("SELECT fulltext from facts where tipe='quote' and fulltext like('%$nick_query%')");
	 $sth->execute();
         if ($rown > 0) {
             for (1..$rown) {
		 push (@rest, $sth->fetchrow())
             }
             my $random = int rand @rest;
             $out = $rest[$random];
         }
	 return $out;
}

sub quoteadd {
	my ($msg, $nick)  = @_;
	my $sth = $dbh->prepare
	     ("INSERT INTO facts (tipe, date, fact, fulltext, who) values ('quote', date('now','localtime'), datetime('now','localtime'), '$msg', '$nick') ");
	 $sth->execute();

}

sub checkauth {
	my $nick = shift;
	my $sth = $dbh->prepare
	    ("SELECT perm from users where nick='$nick'");
	$sth->execute();
	my $ok = $sth->fetchrow;
	if ($ok) { return "ok" } else { return undef }
}

sub authen {
	my ($nick, $gpass) = @_;
	my $sth = $dbh->prepare
	   ("SELECT pass from users where nick='$nick'");
	$sth->execute();
	my $dbpass = $sth->fetchrow;
	if ($dbpass) {
		if ($dbpass eq $gpass) {
			$dbh->do("UPDATE users SET perm='aut' WHERE nick='$nick'");
			return "ok"; 
		} else { return undef }
	}
}

=item urbano

Definiciones de urbandictionary
Sintaxis: urbano palabra

=cut
sub urbano {
	my $msg = shift;
        my $ndy = "";      # ndy means Not defined yet, used as a flag for those non-existing definitions.
	my $out = "";
	my $url = "http://www.urbandictionary.com/define.php?term=$msg";
	my $page = get($url);
        my @definitions = ();
        foreach (split ('<td>', $page))
        {
                # Remove some garbage from the defitions
                my $content =  $_;
                $content =~ s/&\#39;/'/g;
                $content =~ s/&quot;/\"/g;
                $content =~ s/&amp;/&/g;
                $content =~ s/&lt;/</g;
                $content =~ s/&gt;/>/g;
                $content =~ s/\r//g;
                $content =~ s/<br>//g;
                $content =~ s/<br\/>//g;
                $content =~ s/<a.*?>//g;
                $content =~ s/<\/a>//g;
                $content =~ s/\n//g;
                if ($content =~ /\'not_defined_yet\'/s)
                {
                        $ndy = "err, no existe pero me suena a: ";
                }
                if ($content =~ /<div\sclass='definition'>(.*?)<\/div>/s)
                {
			push @definitions,$1;
                }
        }
        if (@definitions == 0)
        {
            return $out;
        }
	$out = $ndy.substr($definitions[int rand @definitions],0,199);
	return $out;
}

=item temblor

Sacamos el dato de temblores de la pagina USGS
Sintaxis: temblor [pais]
Si el pais no se especifica, se devuelve el ultimo temblor registrado en el mundo.

=cut
sub temblor {
	my $msg = shift;
        my $url = "";
	if  (length($msg) >= 1) {
            #to lower case
            $msg = lc($msg);
            #to first letter Uppper
            $msg = ucfirst($msg);
            $msg = quotemeta($msg);
            $url= 'http://earthquake.usgs.gov/earthquakes/catalogs/7day-M2.5.xml';
	}
        else
	{
            # I just need the XML with the latest earthquakes (last day)
            $url= 'http://earthquake.usgs.gov/earthquakes/catalogs/1day-M2.5.xml';
	}
	my $out = "";
	# Retrieve the feed, or die gracefully
	my $feed_to_parse = get ($url) or die "I can't get the feed you want";
	# Parse the XML
	my $parser = XML::Simple->new( );
	my $rss = $parser->XMLin("$feed_to_parse");

	if  (length($msg) >= 1)
	{
		foreach my $key (keys (%{$rss->{entry}}))
		{
			if ($rss->{entry}->{$key}->{'title'} =~ m/$msg/)
			{
                            my $title = $rss->{entry}->{$key}->{'title'};
                            my $date = $rss->{entry}->{$key}->{'updated'};
                            $out = $out.$title." Updated ".$date;
                            $out = $out.' || ';
                        }
		}
	}
	else
	{
		if ($feed_to_parse =~ /<entry><id>.*?<\/id><title>(.*?)<\/title><updated>(.*?)<\/updated>/s)
                {
                    $out = "Ultimo temblor: ".$1." ".$2;
                }
	}
	$out = substr($out, 0, 199);
	return $out;
}


=item corregir

Sintaxis: s/palabro/palabra/ 

=cut

# this is totaly *WRONG* this is a bad approch, /me should not try to write
# code when is a kind of drunk
sub correctuser {
# Add a check if the user exists even if try to use the regexp->FIXME
	my ($msg, $nick) = @_;
	if ($msg =~ m/^s\/.+\/$/) {
	    my $sth = $dbh->prepare
	        ("SELECT last from users where nick='$nick'");
	    $sth->execute();
	    my $rowi = $sth->fetchrow;
	    $msg =~ s/^s//;
            #This eval -if was added by jmasibre bug with s/[///
            eval{
                my @chan = split(/\//, $msg);
                $rowi =~ s/$chan[1]/$chan[2]/g;
                &say("$nick en realidad quería decir \"$rowi\"", $nick, "no", "no");
            };
            if($@)
            {
                ### catch block
		&say("$nick WTF! ¬¬", $nick, "no", "no");
            };
      }
}

=item aprender

aprender que id es definicion_de_id 
olvidar id 

=cut

sub forgetfact {
	my ($nick, $dfact) = @_;
	my $sth = $dbh->prepare
	    ("SELECT rowid from facts where fact='$dfact'");
	$sth->execute();
	my $row = $sth->fetchrow;
	$dbh->do("DELETE from facts where rowid='$row'") unless ($nick eq $dfact);

}

sub putfact {
	my ($fact, $fulltext, $nick) = @_;
	my $sth = $dbh->prepare("INSERT INTO facts (tipe, date, fact, fulltext, who) values ('fact', date('now','localtime'), '$fact', '$fulltext', '$nick') ");
	$sth->execute();
}

sub fffact {
	my $lfact = shift;
	my $sth = $dbh->prepare
	   ("SELECT fulltext from facts where fact='$lfact'");
	$sth->execute();
	my $row = $sth->fetchrow;
	if ($row) { 
		$row =~ s/^\ +//; 
		return $row 
	} else { return undef }

}

=item karma

Sintaxis: karma nick 

=cut

sub getkarma {
	my $nick = shift;
	my $sth = $dbh->prepare
	    ("SELECT karma from users where NICK='$nick'");
	$sth->execute();
	my $row = $sth->fetchrow;
	return $row;
}

sub karmacatch {
	my ($giver, $given) = @_;
	my @k = ("$giver", ($given =~ m/(\+\+|--)/));
	my $karma=0;

        #sanitize variables
        my $given_s = quotemeta($given);
        my $giver_s = quotemeta($giver);

        if ($given_s !~ m/$giver_s/i) {
		$given =~ s/(\+\+|--)//;
		push (@k, $given);
	} else { return }
	my $lucky = $given if ( &dbuexist($k[2]) );
	if ($lucky) {
	     my $sth = $dbh->prepare
	         ("SELECT karma from users where NICK='$lucky'");
	     $sth->execute();
	     my $row = $sth->fetchrow;
	     if ($k[1] eq '++') {
		     $row++;
	     } else {
		     $row--;
	     }
             $dbh->do("UPDATE users SET karma='$row' WHERE nick='$lucky'");
	}

}

sub dbuexist {
	my $nick = shift;
	if ($nick) {
	    my $sth = $dbh->prepare
	        ("SELECT seen, last from users where NICK='$nick'");
	        $sth->execute();
	        my @row = $sth->fetchrow_array;
	        if ($row[0]) {
		    return @row;
	        } else { return undef }
	}
}

sub dblog {
	my ($nick, $msg) = @_;
	$msg =~ s/'//g;
	my @seen = &dbuexist($nick); 
	if ($seen[0]) {
		$dbh->do("UPDATE users SET seen=datetime('now','localtime'), last='$msg' WHERE nick='$nick'");
	} else {
		my $sth = $dbh->prepare("INSERT INTO users (nick, seen, last) VALUES ('$nick', datetime('now','localtime'), '$msg')");
		$sth->execute();
	}
}

=item definir

Sintaxis: definir palabra 
Veamos que dice la wikipedia 

=cut

sub definir {
#TODO this have some problems when the word has UTF-8 chars, like 'ratón'
	my $word = shift;
	my $wiki = WWW::Wikipedia->new();
	$wiki->language( 'es' );
	$wiki->follow_redirects('on');
	my $result = $wiki->search ("$word") ;
	my $out; 
	if ($result) {
	   if ($result->text()){
		$out = $result->text();
	   } else { return }
	   #$out =~ s/\n+/ /g;
	   #$out =~ s/\{.+.\}|<!.+->//g;
	   #$out =~ s/<ref>(.*?)<\/ref>//g;
	   #$out =~ s/\[\[.+\]\]//gi;
	   #$out =~ s/(.*?).\]\]//g;
	   #$out = substr($out, 0, 199);
	   #### ^^^^^ those works
	   
	   $out =~  s/\n+/ /g; #remove all newlines and use spaces
	   $out =~ s/\{.+.\}|<!.+->//g; # remove html comments and wiki markdown
	   $out =~ s/<ref.+>(.*?)<\/ref>//g; # reftag
	   $out =~ s/<ref>(.*?)<\/ref>//g; # reftag
	   $out =~ s/<\w>(.{1,})<\/\w>//g; #html tags
	   $out =~ s/<sub>([0-9]{1,})<\/sub>//g;  # subs that come mostly like numbers
	   $out =~ s/\[\[.+\]\]//gi; #more wiki markdown
	   $out =~ s/(.*?).\]\]//g; #wiki stuffs
           $out = substr($out, 0, 199);



	   return "$out...";
	}
}
sub descifrar {
        #replacing soap api by the new ajax api
	# my $search = shift;
	# my $goo = Net::Google->new(key=>LOCAL_GOOGLE_KEY);
	# my $word = $goo->spelling(phrase=>$search)->suggest();
        # the new AJAX Api
        my $word = "";
        # my $search = Google::Search->Web(q => "rock", key => $local_google_key, referer => $local_google_referer);
        # my $result = $search->first;
        # if ($result) {
        #     $word = $result->uri;
        # }
        # else {
        #     $word = $search->error->reason;
        # }
        
	return $word;
}

=item google

Sintaxis: google palabra

=cut

sub google {
        #replacing soap api by the new ajax api
	#my $search = shift;
	# my $goo = Net::Google->new(key=>LOCAL_GOOGLE_KEY);
	# my $goosh = $goo->search();
	# $goosh->query($search);
	# $goosh->lr(qw(es en));
	# $goosh->max_results(1);

	#my $answer;
	# foreach (@{$goosh->results()}) {
	# 	$answer = $_->URL();
	# }
        my $local_google_key = "$bconf{$bgkey}";
        my $local_google_referer = "$bconf{$bgreferer}";

        my $search_string = shift;
        my $answer;
        my $search = Google::Search->Web(q => $search_string, key => $local_google_key, referer => $local_google_referer);
        my $result = $search->first;
        if ($result) {
            $answer = $result->uri;
        }
        else {
            if($search) {
                my $error_g = $search->error;
                if($error_g) {
                    print $error_g->reason;#debug
                    print $error_g->http_response->as_string;#debug
                    print "^^^^ debug: google function error\n";#debug
                    $answer="arrg ha ocurrido un error ¬¬";
                } else {
                    $answer="google no encuentra eso, O.o!";
                }
            }
        }
        return $answer;
}

=item fortune

Ve lo que te depara el futuro

=cut

sub fortune {
	my $fortune = `fortune  -a -n 160 -s`;
	$fortune =~ s/\s+/ /g;
	return $fortune;
}

sub say {
	my ($msg, $nick, $usenick, $priv ) = @_;
	my $channel = $bconf{$bchan};
	$channel = "$nick" if $priv eq 'yes';
	if ($usenick eq 'yes') {
		$irc->yield( privmsg => $channel, "$nick: $msg");
	} else {
		$irc->yield( privmsg => $channel, "$msg");
	}
	return
}

sub pipiancatch {
    my ($giver, $msg) = @_;
    $msg =~ m/(\w+)(,|;|:)\s+(pipian\+\+)/;
    my ($given, $action) = ($1, $3);
    my $pipianlvl = 0;
    my $creepy = $given if ( &dbuexist($given) );
    if ($creepy) {
	my $sth = $dbh->prepare
	    ("SELECT pipianlvl from users where NICK='$creepy'");
	$sth->execute();
	my $row = $sth->fetchrow;
	if ( $action =~ m/pipian\+\+/ ){
	    $row++;
	} 
	$dbh->do("UPDATE users SET pipianlvl='$row' WHERE nick='$creepy'");
    }
}

=item pipianometro

Sintaxis: pipianometro nick

=cut

sub getpipianlvl {
    my $nick = shift;
    my $sth = $dbh->prepare
	("SELECT pipianlvl from users where NICK='$nick'");
    $sth->execute();
    my $row = $sth->fetchrow;
    return $row;
}

=item identica

Las funciones de Identica
identica say mensaje
identica pull | identica pull foo

=cut

sub identica_say {
    my ($message) = @_;
    my $size = length($message);
    if ($size <= 140){
	$message = decode("utf-8", $message);
	return $message if $identica->update("$message");
    }else{
	return undef;
    }
}

sub identica_pull {
    my $nick = shift @_;
    if ($nick) {
	my $fetch = $identica->user_timeline({screen_name => $nick});
	my $last_status = shift( @$fetch );
	if ($last_status) {
	    my $dent = encode("utf-8", ${$last_status}{"text"});
	    return (${$last_status}{user}{"screen_name"}, $dent);
	} else { return ($nick, undef); }
    } else {
	my $fetch = $identica->home_timeline;
	my $last_status = shift( @$fetch );
	if ($last_status) {
	    my $dent = encode("utf-8", ${$last_status}{"text"});
	    return (${$last_status}{user}{"screen_name"}, $dent);
	} else { return (undef, undef); }
    }
}

sub doaction {
	my ($channel, $msg) = @_;
		$irc->yield( ctcp => $channel => "ACTION $msg");
	return
}
sub chanlog {
	my $logme = shift;
	open(LOG,">>$logfile") || die("This file will not open!");
	print LOG "$logme\n";
	close(LOG)
}

=item help

Sintaxis: help 
help comando
Muestra la ayuda :)

=back

=cut
sub gethelp {
        my ($msg) =@_;
        #pod help
        #ref http://search.cpan.org/~andrewf/Pod-POM-0.25/lib/Pod/POM.pm

        my $sections = $pom->head1();
        my $desc = $sections->[1];
        #See the pod (mixed with the code)
        my $doc_string = "";
        #ask just general help
        if (length($msg) < 1)
        {
            foreach my $item ($desc->head2->[0]->over->[0]->item) {
                $doc_string =  $doc_string." ".$item->title().",";
            }
        } else #ask especific help of an item
        {
            #print "ask especific help for '$msg'\n";#debug
            foreach my $item ($desc->head2->[0]->over->[0]->item) {
                $doc_string =  $item->title();
                #print "comparing '$doc_string' eq '$msg'\n";#debug
                if($doc_string eq $msg){
                    print "equal!";
                    $doc_string =  $doc_string.": ".$item->content()." ";
                    last; #stop de loop
                }
            }
        }

        #some cleanup
        $doc_string =~ s/\n+/ | /g;
        $doc_string =~ s/\| +$//g;
        $doc_string =~ s/,$/\./;
	return $doc_string;
}


$poe_kernel->run();
exit 0;

=head1 AUTHOR

This program was written by Rene Mayorga E<lt>rmayorga@debian.orgE<gt>

=cut
