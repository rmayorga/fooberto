#!/usr/bin/perl
use warnings;
use strict;
use integer;
use POE;
use POE::Component::IRC;
use Net::Google;
use SOAP::Lite;

use WWW::Wikipedia;
use constant LOCAL_GOOGLE_KEY => "PqCJzeJQFHL/2AjeinchN3PyJoC2xUaM";
use Config::Simple;
use Getopt::Std;
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
use DBI;
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

sub CHANNEL () { "$bconf{$bchan}" }

my ($irc) = POE::Component::IRC->spawn();

POE::Session->create(
    inline_states => {
        _start     => \&bot_start,
        irc_001    => \&on_connect,
        irc_public => \&on_public,
	irc_msg    => \&on_public, 
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

   # print ouput to screen and also log it
    my $ts = scalar localtime;
    print " [$ts] <$nick:$channel> $msg\n";
#chanlog
    &chanlog(" [$ts] <$nick:$channel> $msg");
# catch users correcting words
    &correctuser($msg, $nick);

#ignoring un-polite-users
    my $ignore = &catchignore("$nick", "$msg");
    if (!$ignore) { $msg = '' }


#log at sqlite to (FIXME use the same chanlog function)
    &dblog("$nick", "$msg");

# karma catcher
    &karmacatch($nick, $msg);
    # capture command char (also this should go on the config file)

    if ( ($msg =~ m/^$bconf{$bcomm}/) || ($msg =~ m/^$bconf{$bnick}(,|;|:).+/ ) ) {
	#default'ing usenick, I know, is ugly FIXME
	my $usenick = 'no';
	$usenick = "yes" if $msg =~ m/^$bconf{$bnick}(,|;|:).+/;
	$msg =~ s/(^$bconf{$bcomm}|^$bconf{$bnick}(,|;|:)\s+)//;
	# Commands come whit the 	
	
	for ($msg) {
		#default ping command
		if ($msg =~ m/^ping/i) {
			&say("pong!", $nick, $usenick);
		}
		# fortune cookies
		elsif ($msg =~ m/^fortune/i) {
		    my $out = &fortune();
		    &say($out, $nick, $usenick);
		}
		elsif ($msg =~ m/^google/i) {
		   $msg =~ s/google//i;
		   if (length($msg) >= 1) {
		        my $out = &google($msg);
			&say($out, $nick, $usenick);
		   }
		}
		elsif ($msg =~ m/^decifrar/i) {
		   $msg =~ s/decifrar//i;
		   if (length($msg) >= 1) {
		        my $out = &decifrar($msg);
			if ($out) {
			    &say($out, $nick, $usenick);
			} else {
			   &say("no soy perfecto, pero creo que $msg esta bien", $nick, $usenick);
			}
		   }
		}
		elsif ($msg =~ m/^definir/i) {
		   $msg =~ s/definir//i;
		   if (length($msg) >= 1) {
		        my $out = &definir($msg);
			if ($out) {
			    &say($out, $nick, $usenick);
			} else {
			   &say("err, no encontre $msg", $nick, $usenick);
			}
		   }
		}
		elsif ($msg =~ m/^visto/i) {
		   $msg =~ s/visto//i;
		   if (length($msg) >= 1) {
			$msg =~ s/\ +//g;
			my @seen = &dbuexist($msg);
			if ($seen[0]) {
			    my $msout = "Parece que $msg, andaba aquí el $seen[0], lo último que salio de su teclado fue $seen[1]";
			    &say($msout, $nick, $usenick);
			} else {
			   &say("ese ser mitologico núnca entro a este antro de perdición", $nick, $usenick);
			}
		   }
		}
		elsif ($msg =~ m/^karma/i) {
		   $msg =~ s/karma//i;
		   if (length($msg) >= 1) {
			$msg =~ s/\ +//g;
			my @seen = &dbuexist($msg);
			if ($seen[0]) {
			    my $karma = &getkarma($msg);
			    if ($karma < 0 ) {
				    &say("ese tal $msg esta mal, $karma", $nick, $usenick);
			    } elsif ( $karma > 0) { 
				    &say("parece que $msg se porta bien, $karma", $nick, $usenick);
			    } elsif ( $karma == 0 ) { &say("creo que $msg es _neutral_ , $karma", $nick, $usenick); }
			} 
		   }
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
		elsif ($msg =~ m/^olvidar/i) {
		   $msg =~ s/olvidar//i;
		   $msg =~ s/\ +//g;
		   if (length($msg) >= 1) {
			   my $isfact = &fffact("$msg");
			   if ($isfact) {
			   	&forgetfact($nick, $msg)  #unless( !$isfact);
			   }
		   }
		}
		elsif ($msg =~ m/^identify/i) {
		   $msg =~ s/identify//i;
		   $msg =~ s/\ +//g;
		   if (length($msg) >= 1) {
			   my $ok = &authen($nick, "$msg");
		   }
		}
		elsif ($msg =~ m/^action/i) {
		   my $add;
		   $msg =~ s/^action//i;
		   $msg =~ s/^\ +//g;
		   if ($msg =~m/list/) { &actionlist($nick); $add = 'no'; }
		   if ($msg =~s/^random//) { &actionlist($msg, $channel); $add = 'no'; } 
		   my $check = &checkauth($nick);
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
				&say ($bug, $nick, $usenick) unless (!$bug);
			}
		}
		elsif ($msg=~ s/^debian pack//) {
			$msg =~ s/^\ //;
			if (length($msg) >=1 ) {
				my $pack = &querypack($msg);
				&say ($pack, $nick, $usenick) unless (!$pack);
			}
		}
		elsif ($msg=~ s/^debian paquete//) {
			$msg =~ s/^\ //;
			if (length($msg) >=1 ) {
				my $pack = &searchpack($msg);
				&say ($pack, $nick, $usenick) unless (!$pack);
			}
		}
		elsif ($msg =~ m/^quote/i) {
		   $msg =~ s/quote//i;
		   $msg =~ s/^\ +//g;
		   if (length($msg) >= 1) {
			   my $check = &checkauth($nick);
			   if ($msg =~ m/^add/) {
				   if ($check) {
					   $msg =~ s/^add//;
					   &quoteadd("$msg", $nick);
				   }
			   } elsif ($msg =~ m/^random/) {
				   $msg =~ s/^random//;
				   my $randqu = &quotegetrand();
				   &say("\"$randqu\"", $nick, $usenick);
			   }
		   }
		}
		elsif ($msg =~ s/\?$//) {
		   if (length($msg) >= 1) {
			    my @probability ="$bconf{$probab}"; 
			    my @prob = split("//",$probability[0]);
			    &say($prob[ int rand @prob ], $nick, $usenick) unless ($usenick eq 'no');
			}
		}
		elsif ($msg =~ s/^saludar//) {
			$msg =~ s/^\ +//;
		   if (length($msg) >= 1) {
			   if(&dbuexist($msg)) {
			       my $num = `cat es-words | wc -l`;
			       my $rand = int rand $num;
			       my $gayw = `head -$rand es-words | tail -1`;
			       &say("$msg: gay de $gayw", $nick, 'no');
			   }
			}
		}
		elsif ($msg =~ s/^calendar//) {
			$msg =~ s/^\ +//;
			my $cnum = `calendar | wc -l`;
			my $crand = int rand $cnum;
			my $calen = `calendar | head -$crand  | tail -1`;
			&say("$calen", $nick, $usenick);
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
				&say("$prob[ int rand @prob ] $msg es $isfact", $nick, $usenick);

		  	}	
		}
	}
    }

}
# TODO get rid of system commands and use perl
sub searchpack {
	my $pack = shift;
	my $dist = $pack;
	my $packs;
	my $msgout;
	if ($pack =~ m/(^stable)|(^testing)|(^unstable)/) {
		$dist =~ s/\ \w.+//;
		$pack =~ s/^.+\ //;
		foreach (`for i in \$(ls debian-packages/*-$dist.gz) ; do zcat \$i | grep "Package: $pack" ; done`) {
			chomp($_);
			$packs .= $_;
		}
	}
	if(!$packs) { return undef }
	$packs =~ s/Package://g;
	$packs =~ s/^\ +//;
	if ($packs eq $pack) { $msgout = "El paquete existe y se llama tal como lo escribiste" }
	else { $msgout = "podría ser: ". substr($packs, 0, 70) . " ...?"; }
	return $msgout;

}

# TODO get rid of system commands and use perl
sub querypack {
	my $pack = shift; ##Put all these in config file TODO
	my @dists = ("main-stable", "contrib-stable", "nonfree-stable",
	             "main-testing", "contrib-testing", "nonfree-testing",
		     "main-unstable", "contrib-unstable", "nonfree-unstable");
	my $msgout;
	my $version;
	foreach (@dists) {
		$version = `for i in \$(ls debian-packages/$_.gz) ; do zcat \$i | grep -A 6 "Package: $pack" | grep Version ; done`;
		if ($version) {
			chomp($version);
			chomp($_);
			$msgout .= " $_->$version";
		}
	}
	return $msgout
}





sub querybug {
	my $bug = shift;
	my $soap = SOAP::Lite->uri('Debbugs/SOAP')->proxy('http://bugs.debian.org/cgi-bin/soap.cgi');
	my $refbug = $soap->get_status($bug)->result->{$bug};
	my $msgout;
	if ($refbug->{id}) {
		$msgout = "paquete: $refbug->{package}, bug: $refbug->{subject}, severidad: $refbug->{severity}, url: http://bugs.debian.org/$bug";
		$msgout .= " resuelto por: $refbug->{done}" unless (!$refbug->{done});
		return $msgout;
	} else { return undef}

}

sub addignore {
	my ($nick, $msg) = @_;
        my $sth = $dbh->prepare
            ("INSERT INTO igno (nick, date, who, text) VALUES ('$msg', date('now'), '$nick', 'ig')");
        $sth->execute();

}

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


sub actionlist {
	my ($nick, $channel) = @_;; 
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
	&say ("@rest", "$nick", "no") unless $channel; 
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
		}
	}
}

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
	    my @chan = split(/\//, $msg);
	    $rowi =~ s/$chan[1]/$chan[2]/g;
	    &say("$nick en realidad quería decir \"$rowi\"", $nick, "no");
      }
}

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
	if ($given !~ m/$giver/i) { 
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

sub definir {
#TODO this have some problems when the word has UTF-8 chars, like 'ratón'
	my $word = shift;
	my $wiki = WWW::Wikipedia->new();
	$wiki->language( 'es' );
	my $result = $wiki->search ($word) ;
	my $out; 
	if ($result) {
	   if ($result->text()){
		$out = $result->text();
	   } else { return }
	   $out =~ s/\n+/ /g;
	   $out =~ s/\{.+.\}|<!.+->//g;
	   $out =~ s/<ref>(.*?)<\/ref>//g;
	   $out =~ s/\[\[.+\]\]//gi;
	   $out =~ s/(.*?).\]\]//g;
	   $out = substr($out, 0, 199);
	   return "$out...";
	}
}
sub decifrar {
	my $search = shift;
	my $goo = Net::Google->new(key=>LOCAL_GOOGLE_KEY);
	my $word = $goo->spelling(phrase=>$search)->suggest();
	return $word;
}

sub google {
	my $search = shift;
	my $goo = Net::Google->new(key=>LOCAL_GOOGLE_KEY);
	my $goosh = $goo->search();
	$goosh->query($search);
	$goosh->lr(qw(es en));
	$goosh->max_results(1);

	my $answer;
	foreach (@{$goosh->results()}) {
		$answer = $_->URL();
	}
	return $answer;
}
sub fortune {
	my $fortune = `fortune  -a -n 160 -s`;
	return $fortune;
}

sub say {
	my ($msg, $nick, $usenick ) = @_;
	if ($usenick eq 'yes') {
		$irc->yield( privmsg => CHANNEL, "$nick: $msg");
	} else {
		$irc->yield( privmsg => CHANNEL, "$msg");
	}
	return
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


$poe_kernel->run();
exit 0;

