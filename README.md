# Tezos Batch Payments

All-in-one script for bakers to securely batch delegator reward payments.

Made with :heart: by<br/>
<a href='https://figment.network'><img alt='Figment Networks' src='https://figment.network/figment-logo.png' height='32px' align='bottom' /></a>


----


## Disclaimer

Please use this script at your own risk, and to learn how such a task can be done. We have made reasonable efforts to at least never lose funds (eg by sending to the wrong place or by purging an intermediary/burner account that has funds), but this is all provided with _no warranty whatsoever_!


## Dependencies

- `bash` >= 4.3
- `jq` >= 1.5
- `dc` >= 1.3.95


## Usage

_First, review the script! Figment is trust-worthy, but don't take our word for it!_ Once satisfied, either [download](https://git.io/fxMmp) and run, or use this magic incantation:

    bash <( curl -sL https://git.io/fxMmp ) --help
    
This will show the various options and how to use them. For the lazy (using `tezos-client` in the current directory), here's an example of sending a donation of 1 XTZ to [Figment's Bakery](https://figment.network/tezos/bakery) :wink::

    bash <( curl -sL https://git.io/fxMmp ) --transactions tz1Scdr2HsZiQjc7bHMeBbmDRXYVvdhjJbBh=1000000


## How does it work?

First some context - we discussed and thought carefully about a sensible way to handle payments of baking rewards. Here is what we came up with:

1. The script first creates a one-time-use 'burner' address local on your machine.
1. Conceptually, you'll be wanting to send rewards from your baker account, but this is not ideal. We don't want to have a 'spending ledger' for our main baking account outside of our bank vault. So how to fund the burner? To facilitate this, we setup a 'float' ledger which holds some reasonable amount of upcoming rewards we will need to pay out in the short term. This float ledger can be cloned and provided to the people who need to handle payouts.
1. The script asks you to fund the burner account with the total amount from your specified transactions. Then you paste the operation hash which the script then uses to wait for confirmation.
1. Next, a simulation is run which essentially is just an injection of all transactions to a special endpoint that doesn't check the signature.
1. If the simulation passes, we can start sending pages of transactions. Currently we are grouping them into 100 transaction operations. We decided on that because a) it's plenty (tons, really) of headroom for the 16k maximum per operation, and b) we will be showing a TzScan link to the operation on our [delegator dashboard](https://figment.network/tezos/bakery), and more than 100 transactions makes the page really long.
1. Each page is forged, signed, pre-applied (another check), injected, and then again we wait for confirmation.
1. At the end, we list out the operation hashes for reference.
1. At this point the one-time-use burner can be purged, but for safety we don't do this unless you pass `--unsafe` to the command, so that if things went horribly wrong we won't purge an account which has funds (!)


## Example

Here I'm on an Alphanet node and sending 2 addresses 1 XTZ each:

``` plain
$ bash <( curl -s https://git.io/fx17m ) --transactions tz1fHfqyAUzgyCbXs31uEjtsZ7TYaVrNr36i=1000000,tz1QYaYj9G9B2LoNj4DGrnBr1jNpb5R6VdT6=1000000
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


## Other Uses

If you check out the usage into by running `--help` you'll find several handy options.

For example:

- If you're using the docker script on the machine you're doing payouts with, you can use the `--docker NETWORK` (e.g. `mainnet`) option.
- If you have a lot of transactions you don't have to pass them all on the command line. Make a file with one `ADDR=AMOUNT` per line and use `--transactions-file path-to-file`.
- `--check` will simply confirm the transactions were passed correctly and report the total number of addresses and XTZ required.
- This is a generic payment batching tool, as well:

  ```
  bash <( curl -sL https://git.io/fxMmp ) --use existing-alias --skip-funding --transactions ADDR1=AMOUNT1,ADDR2=AMOUNT2
  ```

  This command will not use a burner address and instead send from an existing local alias. It also won't ask that the account be funded with the total!


## Possible Issues

Currently the biggest problem is that this started as a proof-of-concept and is pure `bash`. The consistency of the Tezos RPC output is not 100% and shell scripting in general is not our favourite way to do this. We are considering a re-write in Python.

Besides that, the 'simulation' step currently just simulates _all_ transactions at once, instead of page-by-page. This seems to be required because the burner account must be revealed in the first page, but the reveal won't actually make it onto the blockchain during simulation of course. So page 2 will fail due to the public key not being revealed... We're not sure how to manage this just yet. For now we figure it's better to fail early than half-finish a batch and error out.

Finally, this is not fully 'automated' currently. It requires a human to run it and then potentially to do something with the operation hashes. We're thinking about ways to further automate this process. In theory we could keep our float unencrypted on a machine, for example... And having the operation results in a machine readable format like JSON would be needed in that case so we could still provide relevant links to delegators.


## Acknowledgments

Thanks to:
- [Bake'n'Rolls](https://bakenrolls.com/) for their helpful research and [blog post](https://medium.com/@bakenrolls/sending-multiple-transactions-in-one-batch-using-tezos-rpc-6cab3a21f254) which was instrumental in getting this running.
- [Obsidian Systems](https://obsidian.systems/) for hosting the friendliest Tezos Baking Slack Community around, where we asked plenty of questions during the process.


## Feedback Welcome

Please let us know what you think or if you have any ideas for improvements! [Join our Discord](https://discord.gg/zqBZ2UG)
