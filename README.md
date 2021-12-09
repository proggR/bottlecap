# Bottlecap

**TL;DR:** its an ERC20-only BitTorrent Peer Wire Protocol inspired DEX crammed _inside_ an ERC20 token that aspires to be something more than that... a protocol for p2p capital flows, built to support industry specific on-chain reporting/processing needs :P

WIP MVP version of Deluge (described below). Left original Deluge copy/state behaviour despite a lot being culled/changed to cram an MVP into a deployable bytecode size, but the bigger picture goals remain... once Bottlecap's math/logic is tested (definitely not anywhere near correct atm, code was cranked out within 48 hours of having the idea and I haven't begun testing so its... rough to say the least :\ lol), I'll be thinking through the restructuring needed to start incorporating the added features (p2p/group handshake protected markets, and "DTermProcessor", a simple term code registry allowing for custom on-chain transaction processors that support central authorities with the same DTermProcessor constructs available to bubble term-coded events up whatever hierarchy is needed).

`contracts/Bottlecap.sol` contains the current "main". About to refactor with `BottlecapStuffed` to see if I can free up enough bytecode footprint to cram at least the p2p markets back in before cooking up a lil React app for this.

## Current public functions:
- **mint:** hash a new asset pair together, and set the initial price along with your fee (in BTTL). unlike AMMs, you're not offering up liquidity, just creating a swap offer that's sent out to the wire. this creates 2 hashes, one tracking asset A=>B offers, and the other tracking B=>A offers. this is only required for new pairs... still haven't worked out a way to incentivize doing this yet though, other than maybe just having a pool of fixed price BTTL available to minters of new markets that's super cheap?... I dunno, future problem :P
- **announce:** announce to the specific market hash which asset you want to offer (it knows, its just to ensure you're in the right place), how much you're offering, and how much of the other asset you'd like in return, along with your fee (in BTTL). unlike most exchanges, the incentives in Bottlecap are flipped and reward the Takers, meaning you get paid your fee if your offer ends up removing another offer from the wire, making hugging spot price for both the asset and BTTL fees the best bet
- **recant:** remove your Bottle (offer) from the wire

Internally, it reduces the market hashes to an Index struct tracking a numerical ID for the market, along with the direction of its pairing (since I only need 1 tree for the orderbook, I just need to know which way's "up" for each market hash :P). From there it's a simple process of attempting to fill the offer (this logic needs the most TLC before testing atm), swapping the assets if there's any agreeable Bottles on the wire, and then sending any unfilled portion to the wire.

Code is in Solidity using Hardhat and OpenZeppelin's ERC20 contract as a base (non-upradeable for now). Also makes use of the fantastic BokkyPooBahsRedBlackTreeLibrary for market data... srsly thank you for that. My brain was turning to mush trying to imagine haxx to get this done efficiently. Was about to try my hand at using tpmccallum's microslots model to cram "cost_padding_address" into a uint256... which would have not been ideal, if its even possible :\ (gave up solving that hurdle once BokkyPooBah saved me from myself). 

@TODO:
- refactor to re-use Offer struct within Bottle to reduce duplicated state (should have called Offer "Message" instead :P)
- fix fill logic/confirm direction logic is actually enforcing the correct directions... wouldn't be surprised its backwards :\
- fix SpotCheck event... definitely raised in a weird/incorrect spot
- add ERC20 hooks (balance confirmation/approve/transferFrom) so its not just internal state processing
- write out hardhat tasks required to fully test/unit tests to avoid breaking anything with further changes
- plan bots to slosh test tokens around. should be relatively straight forward comparisons looking for arbops on SpotCheck events, with semi-random initial stacks of each
- plan/make beta React app... supported features will depend on whether bytecode can be pared enough to add p2p markets back in (plsplsplspls)
- plan next iteration, which attempts to include remaining Deluge featureset in a refactor that breaks things into multiple contracts


# Fractional Deluge (XFD)

Inspired by JAK Bank's Savings Point model and BitTorrent's Peer Wire Protocol, **Deluge** is a simple DEX baked into an ERC20 token (XFD), supporting transient p2p markets, and p2p group based markets through the same marketHash based mechanisms it uses to serve its public markets in order to minimize underlying complexity. With a relatively simple and low profile state/function/event model, I propose that with work/polish, this interface could form the basis for a simple protocol for reliably fair & trustworthy direction, exchange, and accounting of capital.

Comprised solely of ~~`Peer`~~ (culled for now in Bottlecap... may/may not return in Deluge), `Offer`,`Bottle` and `Payload`, and of the 3 public functions `announce`, `whisper` and `pool`, **Deluge** is able to match market offers with current bids in a fair and efficient way, while also allowing `handshakeHash` protected transient p2p markets to be processed with the same mechanisms. Using the `Pool` struct, pre-authed or open group p2p markets are also able to be created, again leveraging the same underlying token swap mechanism.

Also includes support for the "`DTermProcessor`"/"`DTermAuth`" construct (WIP), which is a simple Interface that allows for industry/use-case specific term processors to be constructed, taking in the key transactional data from each event emitting transaction, and calling on chain functions in the appropriate DTerm implementation contract to enable for complex reporting needs to be met, including submission to industry/use-case specific delegated authorities as defined by DTermAuth records identified in each DTermProcessor contract. Intention is to architect in such a way that these DTerms could cascade, with one layer feeding into the next, bubbling relevant data up the chain of command for faster audit and reward feedback loops, and by extension just less hassle involved in the process of handling the accounting of capital flows... I dream of the day I never have to fill in a tax form, because taxes have been automagically handled ad-hoc all along. Velocity of money is important... why only process taxes quarterly/annually, and in an inefficient way that creates a cottage industry from the waste? New infrastructure built to automate the accounting trail = less waste = more profits, and we all like money, right?

Whatcha think? Anything here? BitTorrent Protocol applied to capital flows seems both doable, and worth doing... still working through the implementation, especially the p2p matchmaking element I envision trying to tee up markets between haves/have nots, but I'll save that for when the React app for the current iteration is added... once there's a "current iteration" to build a React app for :\ lol. Still hung up on the (even/especially to me) insane idea that [Fractional](https://fractional.foundation) could _maybe_ in some strange bizarro universe be a viable model for a new M0/MB... which now has me working through the question... what would "the rails" for an entirely new commons owned, socially driven/minded, and p2p M0/MB look like? Is it something like this?... taking the BitTorrent Protocol, and applying it to capital flows?

## Structs:
~~Peer~~, Offer, Bottle, Payload, Pool

## Functions:
mint(), announce(), whisper(), pool(), recant(), fill(), sendBottle(), sendPayload()

## State:
- mapping(uint=>address) termRegistry;
- mapping(address=>uint256[]) peerPermittedTerms;

- uint maxPasses = 3;
- uint _costMultiplier = 10*10**18;

-    //map peer=>market=>bottle
- mapping(address=>mapping(bytes32=>Bottle)) marketSeedBandwidth;
- mapping(address=>mapping(bytes32=>Bottle)) marketPeerAppetite;

- mapping(bytes32=>uint256) currentSpot;

- mapping(bytes32=>MoneyTree) marketTrees;
- mapping(bytes32=>mapping(uint=>address)) treeAddresses;

- mapping(bytes32=>uint) marketIdx;

-    //inputs/outputs for each markethash
- mapping(bytes32=>address) marketInputs;
- mapping(bytes32=>address) marketOutputs;

-    //available asset pairs for each asset
- mapping(address=>address[]) inputMarkets;
- mapping(address=>address[]) outputMarkets;

## Events:
Transfer, PairHashed, BottleSent, BottleUpdated, BottleCapped, PayloadSent, SpotCheck

## Interface Extensions In Progress

### DTerm

Simple term-coded on-chain transaction processors, following a CUPS model of reporting: Create, Update, Process, Submit.

#### DTermBottleProccessor
- create, update, process functions, emitting events for each

#### DTermPayloadProccessor
- create, update, process functions, emitting events for each

####  DTermAuth
- term authority manager, extending the processor system further by allowing processors to submit final/partial claims to central authorities, who can chain their own contracts for further processing
