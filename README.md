# Tezos Batch Payments
All-in-one script for securely batching multiple Tezos payments.


Made with :heart: by<br/>
<a href='https://figment.network'><img alt='Figment Networks' src='https://figment.network/figment-logo.png' height='32px' align='bottom' /></a>

----

## Disclaimer:

Please use this script at your own risk, and to learn how such a task can be done. We have made reasonable efforts to at least never lose funds (eg by sending to the wrong place or by purging an intermediary/burner account that has funds), but this is all provided with _no warranty whatsoever_!

## Usage:

_First, review the script! Figment is trust-worthy, but don't take our word for it!_ Then either download and run, or use this magic incantation:

    bash <( curl -s https://git.io/fx17m ) --help
    
This will show the various options and how to use them. For the lazy (using `tezos-client` in the current directory), here's an example of sending a donation of 1 XTZ to [Figment's Bakery](https://figment.network/tezos/bakery) :wink::

    bash <( curl -s https://git.io/fx17m ) --transactions tz1Scdr2HsZiQjc7bHMeBbmDRXYVvdhjJbBh=1000000

## Example:

Here I'm on an Alphanet node using the docker scripts -- sending 2 addresses 1 XTZ each:

``` plain
$ bash tezos-batch-payments.bash --docker alphanet --transactions tz1fHfqyAUzgyCbXs31uEjtsZ7TYaVrNr36i=1000000,tz1QYaYj9G9B2LoNj4DGrnBr1jNpb5R6VdT6=1000000
****************************************************************
***             Tezos Batch Payout Script                    ***
***                by Figment Networks                       ***
***              https://figment.network                     ***
*** https://github.com/figment-networks/tezos-batch-payments ***
****************************************************************

Checking node access... OK
Generating burner keys... OK

Send 2ꜩ to tz1S5fcm3DBNRejkSY11ABij7VonPaEBYoXw
Paste operation hash: ons97o2F2qEhqfnLafN6FzawYz7XyT2RudTdYkkMxyPMbJ4boS6
Waiting for confirmation... OK

Simulating... OK

Sending transactions (page 1 of 1)...
  Forging operation... OK
  Signing operation... OK
  Preapply/check operation... OK
  Injecting operation... OK
  Waiting for confirmation... OK

Operation Hashes:
  oomdkDCsLDbJNFqd8X6ftfaLLm5iGWWqhyYoNcjDVC3L1D8uoCG

Keeping burner address...
  Alias: burner-2018-10-24-28735
  Address: tz1S5fcm3DBNRejkSY11ABij7VonPaEBYoXw

DONE
```

Check out the operation [on TzScan](http://alphanet.tzscan.io/oomdkDCsLDbJNFqd8X6ftfaLLm5iGWWqhyYoNcjDVC3L1D8uoCG)

### Feedback Welcome

Please let us know what you think or if you have any ideas for improvements! [Join our Discord](https://discord.gg/zqBZ2UG)
