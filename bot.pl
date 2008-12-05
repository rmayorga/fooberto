#!/usr/bin/perl
use warnings;
use strict;
use POE;
use POE::Component::IRC;
use Net::Google;
use WWW::Wikipedia;
use constant LOCAL_GOOGLE_KEY => "PqCJzeJQFHL/2AjeinchN3PyJoC2xUaM";

#should go in the conffile too
my $logfile = "./foobot.log";
#open(LOG,">>$logfile") || die("This file will not open!");
sub CHANNEL () { "#rm-bot" }

my ($irc) = POE::Component::IRC->spawn();

POE::Session->create(
    inline_states => {
        _start     => \&bot_start,
        irc_001    => \&on_connect,
        irc_public => \&on_public,
    },
);

# The bot session has started.  Register this bot with the "magnet"
# IRC component.  Select a nickname.  Connect to a server.
sub bot_start {
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $irc->yield( register => "all" );

    #my $nick = 'usepoe' . $$ % 1000;
# nick and alternative nick and params should go in a config file
	$irc->yield( connect =>
          { Nick => 'foobot',
            Username => 'foobot',
            Ircname  => 'Fooberto',
            Server   => 'irc.freenode.net',
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
    
    # capture command char (also this should go on the config file)
    my $commandchar = "@";
# not using ^^^^ yet should be, TODO

    if ( ($msg =~ m/^@/) || ($msg =~ m/^foobot(,|;|:).+/ ) ) {
	#default'ing usenick, I know, is ugly FIXME
	my $usenick = 'no';
	$usenick = "yes" if $msg =~ m/^foobot(,|;|:).+/;
	$msg =~ s/(^@|^foobot(,|;|:)\s+)//;
	# Commands come whit the 	
	
	for ($msg) {
		#default ping command
		if ($msg =~ m/ping/i) {
			#$irc->yield( privmsg => CHANNEL, "hola $nick");
			&say("pong!", $nick, $usenick);
		}
		# fortune cookies
		elsif ($msg =~ m/fortune/i) {
		    my $out = &fortune();
		    &say($out, $nick, $usenick);
		}
		elsif ($msg =~ m/google/i) {
		   $msg =~ s/google//i;
		   if (length($msg) >= 1) {
		        my $out = &google($msg);
			&say($out, $nick, $usenick);
		   }
		}
		elsif ($msg =~ m/decifrar/i) {
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
		elsif ($msg =~ m/definir/i) {
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
		else { $irc->yield( privmsg => CHANNEL, "$msg.- comando no existe"); }
	}
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

sub chanlog {
	my $logme = shift;
	open(LOG,">>$logfile") || die("This file will not open!");
	print LOG "$logme\n";
	close(LOG)
}


$poe_kernel->run();
exit 0;

