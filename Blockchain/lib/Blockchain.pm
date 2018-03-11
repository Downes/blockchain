package Blockchain;

use 5.010001;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Blockchain ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

);

our $VERSION = '0.01';


#  $Person = gRSShopper::Person->new({person_title=>'title',person_password=>'password'});
# Note that password will be encrypted in save

use JSON qw(encode_json decode_json);
use Digest::SHA qw(hmac_sha256_base64);
use LWP::Simple;
use Fcntl qw(:flock SEEK_END);

use strict;
use warnings;
our $VERSION = "1.00";

sub new {
	my($class, $args) = @_;
	my $self = bless({}, $class);
	$self->{current_transactions} = [];
	$self->{nodes} = [];
	$self->{chain} = [];

	# Retrieve stored version of the boockchain from file

	my ($chain,$current,$nodes) = $self->open();
	if ($chain) {	$self->{chain} = $chain; }
	if ($current) {	$self->{current_transactions} = $current }
	if ($nodes) {	$self->{nodes} = $nodes; }

	unless ( $self->{chain}) {
			$self->new_block(1,100);		# Initializes; previous_hash=1, proof=100
	}

	return $self;
}


# Create a new Block in the Blockchain
# :param proof: <int> The proof given by the Proof of Work algorithm
# :param previous_hash: (Optional) <str> Hash of previous Block
# :return: (object) New Block

sub new_block {

	my ($self,$proof,$previous_hash) = @_;
	$previous_hash ||= "None";

	my @chain = $self->{chain};
	my $index = $#chain;
	my @transactions = $self->{current_transactions};

#	my $self_hash = $self->hash($self->{chain}[$#chain+1]);


	my $block = {
			index => $index,
			timestamp => time,
			transactions =>  @transactions,
			proof => $proof,
			previous_hash => $previous_hash,
	};

	push @{$self->{chain}},$block;
	return $block;

}

# Creates a new transaction to go into the next mined Block
# :param sender: <str> Address of the Sender
# :param recipient: <str> Address of the Recipient
# :param amount: <int> Amount
# :return: <int> The index of the Block that will hold this transaction

sub new_transaction {

	 my ($self,$sender,$recipient,$amount) = @_;

	 push @{$self->{current_transactions}},
		{
			sender => $sender,
			recipient => $recipient,
			amount => $amount
		};

		return $#{$self->{current_transactions}} +1;
}

# Creates a SHA-256 hash of a Block
# :param block: <dict> Block
# :return: <str>

sub hash {

 my ($self,$block) = @_;


 # Canonical because we must make sure that it is ordered, or we'll have inconsistent hashes
 my $json_text = JSON::XS->new->canonical()->encode($block);
 my $digest = hmac_sha256_base64($json_text, "secret");
 # Fix padding of Base64 digests
 while (length($digest) % 4) { $digest .= '='; }
 return $digest;

}

sub last_block {

	 my ($self) = @_;
	 my @chain = $self->{chain};
	 return $self->{chain}[$#chain];

}

	#Simple Proof of Work Algorithm:
	# - Find a number p' such that hash(pp') contains leading 4 zeroes, where p is the previous p'
	# - p is the previous proof, and p' is the new proof
	#:param last_proof: <int>
	#:return: <int>

sub proof_of_work {

 my ($self,$last_proof) = @_;

	my $proof = 0;
	while ($self->valid_proof($last_proof, $proof) == 0) {
		$proof++;
	}

	return $proof;
}

# Validates the Proof: Does hash(last_proof, proof) contain 4 leading zeroes?
# :param last_proof: <int> Previous Proof
# :param proof: <int> Current Proof
# :return: <bool> True if correct, False if not.

sub valid_proof {

 my ($self,$last_proof,$proof) = @_;

	my $guess = $last_proof.$proof;
	my $digest = hmac_sha256_base64($guess, "secret");
	my $test = substr $digest, 0, 4;
	if ($test eq "0000") { return 1;} else { return 0;}

}

#	Determine if a given blockchain is valid
# :param chain: <list> A blockchain
# :return: <bool> True if valid, False if not

sub valid_chain {

	my ($self,@chain) = @_;

	my $last_block = $chain[0];
	my $current_index = 0;
	my $length = $#chain +1;


	while ($current_index < $length) {
		my $block = $chain[$current_index];
		print($last_block);
		print($block);
		return 0 unless ($block->{previous_hash} eq $self->hash($last_block));
		return 0 unless ($self->valid_proof($last_block->{proof},$block->{proof}));
		$last_block = $block;
		$current_index++;
	}
	return 1;
}

# This is our Consensus Algorithm, it resolves conflicts
# by replacing our chain with the longest one in the network.
# :return: <bool> True if our chain was replaced, False if not

sub resolve_conflicts {

	my ($self) = @_;

	my @neighbours = $self->{nodes};
	my @new_chain;
	my @chain = $self->{chain};

	# We're only looking for chains longer than ours
	my $max_length = $#chain+1;
	foreach my $node (@neighbours) {
		my $url = $node . "?cmd=chain";
		my $response = get($url);
		if ($response) {
			my $data = decode_json($response);
			my @chain = $data->{chain};
			my $length = scalar @chain;

			# Check if the length is longer and the chain is valid
			if ($length > $max_length && $self->valid_chain(@chain)) {
				$max_length = $length;
				@new_chain = @chain;
			}
		}
	}

	if (@new_chain) {
		$self->{chain} = @new_chain;
		return 1;
	}

	return 0;

}



# Add a new node to the list of nodes
# :param address: <str> Address of node. Eg. 'http://192.168.0.5:5000'
# :return: None

 sub register {

		my ($self,$url) = @_;
		unless (grep($url, @{$self->{nodes}})) {   # Ensure uniqueness of members in array
			push @{$self->{nodes}},$url;
		}

 }

 # Open the currently persisting copy of the blockchain from a file

sub open {

	my ($self) = @_;

	my $blockchain_file = "data/blockchain.json";
	open(my $fh, "$blockchain_file") || die "Could not open $blockchain_file for read";
	flock($fh, LOCK_EX) or die "Cannot lock $blockchain_file - $!\n";
	my $blockchain_data = <$fh>;
	close $fh;
	my $new_blockchain;
	if ($blockchain_data && $blockchain_data ne "null") { $new_blockchain = decode_json($blockchain_data); }
	return unless (ref $new_blockchain eq "HASH" &&  $new_blockchain->{chain});
	my $chain = $new_blockchain->{chain};
	my $current = $new_blockchain->{current_transactions};
	my $nodes = $new_blockchain->{nodes};
	return ($chain,$current,$nodes);

}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Blockchain - Perl adaptation of simple blockchain script

=head1 SYNOPSIS

  use Blockchain;
	my $blockchain = new Blockchain;

	Get the existing chain

	@chain = $blockchain->{chain};

	Create a new transaction

  $index = $blockchain->new_transaction($sender, $recipient,$amount);

	Create a new block by remaining

	Run the proof of work algorithm to get the next proof...

	$last_block = $blockchain->last_block();
	$last_proof = $last_block->{proof};
	$proof = $blockchain->proof_of_work($last_proof);

	We must receive a reward for finding the proof.
	The sender is "0" to signify that this node has mined a new coin.

	$blockchain->new_transaction(0,$node_identifier,1);

	Store hash and create the block

	$previous_hash = $blockchain->hash($last_block);
	$block = $blockchain->new_block($proof,$previous_hash);

=head1 DESCRIPTION

This is a very simply blockchain implementation based on Daniel van Flymen,
Learn Blockchains by Building One, in HackerNoon
https://hackernoon.com/learn-blockchains-by-building-one-117428612f46

Some notes:
- there is no mechanism for defining the current node (asside from whatever URL you run it at)
- instead of the typical api formulation I'm currently using GET requests
- mining test is very simple based on matching four digits
- I persist the bockchain by writing to and reading from file (it's a JSON file but the
usual mechods to save objects as JSON aren't working)

Yes, I should use Catalyst. But it feels a lot of overhead.

In other words, don't use this pro production. It is a 0.01 module

Here are examples of the script being used:

 ... /app.cgi?cmd=chain

 ... app.cgi?cmd=mine

 ... app.cgi?cmd=transaction&sender=fred&recipient=johnny&amount=444


Here's the full script I use to access the blockchain and run it:


#!/usr/bin/env perl

use strict;
use warnings;

$!++;							# CGI
use CGI;
use CGI::Carp qw(fatalsToBrowser);
my $query = new CGI;
my $vars = $query->Vars;

use JSON qw(encode_json decode_json);
use Fcntl qw(:flock SEEK_END);

print "Content-type: text/html\n\n";
print "ok ok";


use File::Basename qw(dirname);
use Cwd  qw(abs_path);
print dirname(dirname abs_path $0) . '/cgi-bin/lib';
use lib dirname(dirname abs_path $0) . '/modules/Blockchain/lib';

use Blockchain;


#----------------------------------------------------------------------------------------------------------
#
#   gRSShopper Blockchain APIs (because I can't resist playing)
#   Based on Daniel Flymen, Learn Blockchains by Building One
#   https://hackernoon.com/learn-blockchains-by-building-one-117428612f46
#
#----------------------------------------------------------------------------------------------------------


# NEW TRANSACTION
if ($vars->{cmd} eq "transaction") {

	my $blockchain = new Blockchain;
	die "Missing values in blockchain transaction" unless ($vars->{sender} && $vars->{recipient} && $vars->{amount});
	my $index = $blockchain->new_transaction($vars->{sender},$vars->{recipient},$vars->{amount});
	my $response = {message => "Transaction will be added to Block $index"};

	&blockchain_close($blockchain);

	print encode_json( $response );
	exit;
}

# MINE
elsif ($vars->{cmd} eq "mine") {

	my $blockchain = new Blockchain;
	my $node_identifier = 1;

	# We run the proof of work algorithm to get the next proof...
	my $last_block = $blockchain->last_block();
	my $last_proof = $last_block->{proof};
	my $proof = $blockchain->proof_of_work($last_proof);

	# We must receive a reward for finding the proof.
	# The sender is "0" to signify that this node has mined a new coin.
	$blockchain->new_transaction(0,$node_identifier,1);
	my $previous_hash = $blockchain->hash($last_block);
	my $block = $blockchain->new_block($proof,$previous_hash);

	my $response = {
		message => "New Block Forged",
		index => $block->{index},
		transactions =>  $block->{transactions},
		proof =>  $block->{proof},
		previous_hash => $block->{previous_hash}
	};

	&blockchain_close($blockchain);
	print encode_json( $response );
	exit;
}


# CHAIN
elsif ($vars->{cmd} eq "chain") {

	my $blockchain = new Blockchain;

	my @chain = $blockchain->{chain};

	my $response = {
			chain => $blockchain->{chain},
			length => scalar @chain,
	};

	&blockchain_close($blockchain);
	print encode_json( $response );
	exit;
}

# REGISTER
elsif ($vars->{cmd} eq "register") {

	# Only registers one node at at time; I'll fix at a future point
	unless ($vars->{node}) { die "Error: Please supply a valid node"; }


	my @nodes;
	push @nodes,$vars->{node};
	my $blockchain = new gRSShopper::Blockchain;

	foreach my $node (@nodes) {
		$blockchain->register_node($node);
	}

	my $response = {
		message => 'New nodes have been added',
		total_nodes => @nodes,
	};

	&blockchain_close($blockchain);
	print encode_json( $response );
	exit;
}

# RESOLVE
elsif ($vars->{cmd} eq "resolve") {

	my $blockchain = new Blockchain;
	my $replaced = $blockchain->resolve_conflicts();
	my $response;

	if ($replaced) {
			$response = {
					message => 'Our chain was replaced',
					new_chain => $blockchain->{chain},
			};
	} else {
			$response = {
					message => 'Our chain is authoritative',
					chain => $blockchain->{chain},
			};
	}
	&blockchain_close($blockchain);
	print encode_json( $response );

	exit;

}

# Save the updated copy of the blockchain to a file

sub blockchain_close {

	my ($blockchain) = @_;

	my $output = ();
	$output->{chain} = $blockchain->{chain};
	$output->{current_transactions} = $blockchain->{current_transactions};
	$output->{nodes} = $blockchain->{nodes};
	my $json_data = encode_json( $output );

	# None of this worked
	# our $JSON = JSON->new->utf8;
	# $JSON->convert_blessed(1);
	# my $json_data = $JSON->encode($blockchain);
	# my $json_data = JSON::to_json($blockchain, { allow_blessed => 1, allow_nonref => 1 });

	my $blockchain_file = "data/blockchain.json";
	open(my $fh, ">$blockchain_file") || die "Could not open $blockchain_file for write";
	flock($fh, LOCK_EX) or die "Cannot lock $blockchain_file - $!\n";
	print $fh $json_data;
	close $fh;

}


 print "Command $vars->{cmd} not recognized.";
 exit;



=head2 EXPORT

None by default.



=head1 SEE ALSO

Code being updated in GitHub here: https://github.com/Downes/blockchain.git

=head1 AUTHOR

Stephen Downes, E<lt>stephen@downes.caE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018 by Stephen Downes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
