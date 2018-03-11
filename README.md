# blockchain
Simple Perl implementation of blockchain

SYNOPSIS

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

DESCRIPTION

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
