pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
/* import {BokkyPooBahsRedBlackTreeLibrary } from "./BokkyPooBahsRedBlackTreeLibrary.sol"; */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/* import {DTermBottleProcessor, DTermPayloadProcessor, DTermAuth } from "./DTerm.sol"; */

contract Bottlecap is ERC20 {
using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;

    // EVENTS

    event Transfer(address indexed sender, address indexed recipient, uint256 indexed fee);
    event PairHashed(bytes32 indexed marketHash, address indexed assetIn , address indexed assetOut);
    event BottleSent(address owner, bytes32 indexed marketHash, uint indexed value, uint indexed cost, address asset, uint fee);
    event BottleUpdated(address owner, bytes32 indexed marketHash, uint indexed value, uint indexed cost, uint fee);
    event BottleCapped(address indexed owner, address indexed asset);
    event PayloadSent(address sender, address indexed recipient, address indexed asset, uint indexed value);
    event SpotCheck(bytes32 indexed marketHash,uint256 indexed cost);

    // ADMIN/UTILITY STATE + CONSTRUCTER

    address owner;
    bool halted;
    mapping(bytes32=>bool) marketHalts;
    mapping(address=>bool) peerHalts;

    /* , address initialOfferingAddress, address marketRewardAddress, address airdropAddress, address personalAddress */
    constructor(uint256 initialSupply) public ERC20("Bottlecap", "BTTL") {
        owner = msg.sender;
        marketIdxCursor = 0;
        halted = true;
        _mint(msg.sender, initialSupply*10**8);
    }

    // SEED/CONSUMER BOTTLE MAPPINGS

    //map peer=>market idx=>bottle
    mapping(address=>mapping(uint256=>Bottle)) peerMarketBottles;

    // MARKET ASSET MAPPING STATE

    //inputs/outputs for each markethash
    mapping(bytes32=>address) marketInputs;
    mapping(bytes32=>address) marketOutputs;

    // INDEX STATE
    uint marketIdxCursor;
    mapping(bytes32=>Index) marketIdx;

    // MARKET COSTS STATE

    mapping(uint256=>uint256) currentSpot;

    mapping(uint256=>BokkyPooBahsRedBlackTreeLibrary.Tree) marketTrees;
    mapping(uint256=>mapping(uint=>address)) treeAddresses;

    // STRUCTS

    struct Index {
        uint256 idx;
        bool maxNatural;
        bytes32 marketHash;
        bytes32 peerMarketHash;
    }

    struct Offer {
      address asset;
      uint valueIn;
      uint valueOut;
      uint cost;
      uint peerCost;
      uint correctedCost;
      uint fee;
    }

    struct Bottle {
        address owner;
        address asset;
        uint initialValue;
        uint value;
        uint fee;
        uint cost;
        uint correctedCost;
        mapping(uint=>Payload) payloads;
        bool open; //bit confusing with the bottle vs bag ref now :\ lol
        uint blockNumber;
        uint payloadsLength;
    }

    struct Payload {
        Bottle bottle;
        address sender;
        address recipient;
        address asset;
        uint value;
        uint fee;
        uint cost;
    }

    // CORE PUBLIC FUNCTIONS
    function announce(bytes32  marketHash_, address asset_, uint value_, uint valueOut_, uint fee_) public returns (bool){
      require(!halted && !marketHalts[marketHash_] && !peerHalts[msg.sender], "Activity Halted");
      Index memory _idx = marketIdx[marketHash_];
      require(_idx.idx > 0, "Market not minted. Mint it!");
      address inputContract = marketInputs[marketHash_];
      require(asset_ == inputContract, "Wrong asset/wire.");

      uint _cost = getCost(value_,valueOut_);
      uint _peerCost = getCost(valueOut_,value_);
      uint _correctedCost = _idx.maxNatural ? _cost : _peerCost ;
      Offer memory _offer = Offer({ asset:asset_,valueIn:value_,valueOut: valueOut_, cost:_cost, peerCost:_peerCost, correctedCost: _correctedCost, fee: fee_});

      _offer.valueIn = fill(_idx, _offer, _correctedCost, 0);
      if(_offer.valueIn == 0) return false;

      sendBottle(_idx, _offer);
      return true;
    }

    function recant(bytes32  marketHash_) public returns (bool){
      require(!peerHalts[msg.sender], "Sorry buddy"); // undecided on this... to let kicked users pull or not... should just flush them on kick
      Index memory _idx = marketIdx[marketHash_];
      Bottle memory _bottle = peerMarketBottles[msg.sender][_idx.idx];
      if(_bottle.owner != msg.sender){
          return false; //doesn't appear to be anything here mate;
      }

      removeOption(_idx, _bottle.correctedCost);

      delete peerMarketBottles[msg.sender][_idx.idx];
      return true;
    }

    function mint(address assetIn_, uint valueIn_, address assetOut_, uint valueOut_, uint fee_) public payable returns (bool) {
      require(!halted && !peerHalts[msg.sender], "Activity Halted");
      (bytes32 _hashIn,bytes32 _hashOut) = marketHashes(assetIn_,assetOut_);

      marketTrees[marketIdxCursor] = BokkyPooBahsRedBlackTreeLibrary.Tree({root:0,treeSize:0});

      uint _cost = getCost(valueIn_,valueOut_);
      /* uint _flippedCost = getCost(valueOut_,valueIn_); */

      Index memory _idx = mintHash(marketIdxCursor, assetIn_, assetOut_, true, _hashIn, _hashOut);
      mintHash(marketIdxCursor, assetOut_, assetIn_, false, _hashOut, _hashIn);

      Bottle memory _bottle = Bottle({owner:msg.sender,asset:assetIn_,value:valueIn_,initialValue:valueIn_,fee:fee_,cost:_cost, correctedCost:_cost, blockNumber: block.number,open:true, payloadsLength:0});//,
        /* designatedRecipient:address(0),handshakeHash:'',messages:new address[](0),costs: new uint256[](0),termCode:0}); */

      peerMarketBottles[msg.sender][_idx.idx] = _bottle;
      insertOption(_idx,_cost);
      emit BottleSent(_bottle.owner,_hashIn,_bottle.value,_bottle.cost,_bottle.asset,_bottle.fee);

      marketIdxCursor++;
    }

    // CORE INTERNAL FUNCTIONS

    function mintHash(uint curs_, address assetIn_, address assetOut_, bool maxNatural_, bytes32 marketHash_, bytes32 peerMarketHash_) internal returns (Index memory){
      Index memory _idx = Index({idx:curs_,maxNatural:maxNatural_, marketHash:marketHash_,peerMarketHash:peerMarketHash_});
      marketIdx[marketHash_] = _idx;
      /* idxMarket[_idx.idx] = marketHash_; */
      marketInputs[marketHash_] = assetIn_;
      marketOutputs[marketHash_] = assetOut_;

      emit PairHashed(marketHash_,assetIn_, assetOut_);
      return _idx;
    }

    //cost = output/input
    //for natural, that's correct, otherwise flip
    function fill(Index memory idx_, Offer memory offer_, uint key_, uint passes_) internal returns (uint256){
      (uint _key, address _highestBidder) = nextMaxOption(idx_, key_);

      Bottle storage _bottle = peerMarketBottles[_highestBidder][idx_.idx];
      // update to use idx direction... I think... tricky to wrap my head around without an excplicit buy/sell declarative with this goofy method :\
      if(_bottle.cost <= offer_.peerCost){
          while(_bottle.cost <= offer_.peerCost && _bottle.asset == offer_.asset){
            (_key,_highestBidder) = nextMaxOption(idx_,_key);
            _bottle = peerMarketBottles[_highestBidder][idx_.idx];
          }

          if(_bottle.cost <= offer_.peerCost && _bottle.asset != offer_.asset){
            offer_.valueIn = swapPayloads(idx_,_key, _bottle, offer_);
             // "maxPasses" = 8. 16 might work too/be optimal? cuz 256 seemed to be the ideal "max" search depth for this lib, so root 256 = 16 cuz binary tree? idunno
            if(offer_.valueIn > 0 && passes_ < 8){
              offer_.valueIn = fill(idx_, offer_, _key, (passes_+1));
            }else{offer_.valueIn = 0;}
          }
      }
      if(passes_ == 0){
        /* @TODO: fix... this isn't correct... like, at all :\ */
        currentSpot[idx_.idx] = _bottle.cost;
        emit SpotCheck(idx_.marketHash,_bottle.cost);
        emit SpotCheck(idx_.peerMarketHash,_bottle.cost);
      }

      return offer_.valueIn;
    }

    function sendBottle(Index memory idx_,Offer memory offer_) internal returns (bool){
      Bottle memory _bottle = peerMarketBottles[msg.sender][idx_.idx];
      if(_bottle.value > 0){ //lazy existance check
          removeOption(idx_,_bottle.correctedCost);
          _bottle.value += offer_.valueIn;
          _bottle.fee = offer_.fee;
          _bottle.cost = offer_.cost;
          _bottle.correctedCost = offer_.correctedCost;
          emit BottleUpdated(_bottle.owner, idx_.marketHash,_bottle.value, _bottle.cost, _bottle.fee);
      }else{
          _bottle = Bottle({owner:msg.sender,asset:offer_.asset,value:offer_.valueIn,initialValue:offer_.valueIn,fee:offer_.fee,cost:offer_.cost, correctedCost:offer_.correctedCost, blockNumber: block.number,open:true, payloadsLength: 0});
          emit BottleSent(msg.sender,idx_.marketHash,offer_.valueIn,offer_.cost,offer_.asset,offer_.fee);
      }

      peerMarketBottles[msg.sender][idx_.idx] = _bottle;
      insertOption(idx_,offer_.correctedCost);
    }

    function swapPayloads(Index memory idx_, uint key_, Bottle storage bottle_, Offer memory offer_) internal returns (uint){
      if(bottle_.fee <= offer_.fee) return offer_.valueIn; //need agreeable fee

      uint _value = offer_.valueIn <= bottle_.value ? offer_.valueIn : bottle_.value;
      uint _peerValue = flipQuant(_value,offer_.cost);
      uint _fee = offer_.fee < bottle_.fee ? bottle_.fee : offer_.fee;

      sendPayload(bottle_, msg.sender, bottle_.owner, offer_.asset, _value, offer_.cost, _fee);
      sendPayload(bottle_, bottle_.owner, msg.sender, bottle_.asset, _peerValue, offer_.peerCost, 0);
      offer_.valueIn -= _value;
      bottle_.value -= _peerValue;
      transferFrom(bottle_.owner, msg.sender,_fee);

      if(bottle_.value == 0){
        emit BottleCapped(bottle_.owner,bottle_.asset);
        removeOption(idx_,key_);
        delete peerMarketBottles[bottle_.owner][idx_.idx];
      }
      return offer_.valueIn;
    }

    function sendPayload(Bottle storage bottle_, address from_, address to_, address assetIn_, uint valueIn_, uint cost_, uint fee_) internal returns (bool){
      Payload memory _pay = Payload({bottle:bottle_,sender:from_,recipient:to_,asset:assetIn_,value:valueIn_,fee:fee_,cost:cost_});

      bottle_.payloads[bottle_.payloadsLength] = _pay;
      bottle_.payloadsLength++;

      emit PayloadSent(_pay.sender,_pay.recipient,_pay.asset,_pay.value);
      return true;
    }

    // COST FUNCTIONS

    // supports 18 decimal places
    function flipQuant(uint value_, uint cost_) internal pure returns (uint256){
      uint _costMultiplier = 10*10**18;
      return ((value_*_costMultiplier)*(cost_*_costMultiplier))/_costMultiplier;
    }

    // supports 18 decimal places
    function getCost(uint costIn_, uint costOut_) internal pure returns (uint256){
      uint _costMultiplier = 10*10**18;
      return ((costOut_*_costMultiplier)/(costIn_*_costMultiplier))/_costMultiplier;
    }

    function insertOption(Index memory idx_, uint _key) internal {
        marketTrees[idx_.idx].insert(_key);
        treeAddresses[idx_.idx][_key] = msg.sender;
    }

    function removeOption(Index memory idx_,uint _key) internal {
      marketTrees[idx_.idx].remove(_key);
      delete treeAddresses[idx_.idx][_key];
    }

    function maxOption(Index memory idx_, uint cost_) internal view returns (uint, address){
      /* Index idx = marketIdx[marketHash_]; */
      uint _key;
      if(idx_.maxNatural){
        _key = marketTrees[idx_.idx].treeMaximum(cost_);
      }else{
        _key  = marketTrees[idx_.idx].treeMinimum(cost_);
      }
      return (_key,treeAddresses[idx_.idx][_key]);
    }

    function nextMaxOption(Index memory idx_, uint cost_) internal view returns (uint, address){
      /* Index idx = marketIdx[marketHash_]; */
      uint _key;
      if(idx_.maxNatural){
        _key = marketTrees[idx_.idx].prev(cost_);
      }else{
        _key  = marketTrees[idx_.idx].next(cost_);
      }
      return (_key,treeAddresses[idx_.idx][_key]);
    }

    function marketHash(address in_, address out_) public pure returns (bytes32){
      return keccak256(abi.encodePacked(in_,out_));
    }

    function marketHashes(address in_, address out_) public pure returns (bytes32,bytes32){
      return (keccak256(abi.encodePacked(in_,out_)),keccak256(abi.encodePacked(out_,in_)));
    }

    // ADMIN FUNCTIONS

    function togglePeer(address peer_) public returns (bool){
      require(owner == msg.sender);
      return peerHalts[peer_] = !peerHalts[peer_];
    }

    function toggleMachine() public returns (bool){
      require(owner == msg.sender);
      return halted = !halted;
    }

    function toggleMarket(bytes32 marketHash_) public returns (bool){
      require(owner == msg.sender);
      return marketHalts[marketHash_] = !marketHalts[marketHash_];
    }
}


// ----------------------------------------------------------------------------
// BokkyPooBah's Red-Black Tree Library v1.0-pre-release-a
//
// A Solidity Red-Black Tree binary search library to store and access a sorted
// list of unsigned integer data. The Red-Black algorithm rebalances the binary
// search tree, resulting in O(log n) insert, remove and search time (and ~gas)
//
// https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary
//
//
// Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2020. The MIT Licence.
// ----------------------------------------------------------------------------
library BokkyPooBahsRedBlackTreeLibrary {

    struct Node {
        uint parent;
        uint left;
        uint right;
        bool red;
    }

    struct Tree {
        uint root;
        mapping(uint => Node) nodes;
        uint treeSize;
    }

    uint private constant EMPTY = 0;

    function first(Tree storage self) internal view returns (uint _key) {
        _key = self.root;
        if (_key != EMPTY) {
            while (self.nodes[_key].left != EMPTY) {
                _key = self.nodes[_key].left;
            }
        }
    }
    function last(Tree storage self) internal view returns (uint _key) {
        _key = self.root;
        if (_key != EMPTY) {
            while (self.nodes[_key].right != EMPTY) {
                _key = self.nodes[_key].right;
            }
        }
    }
    function next(Tree storage self, uint target) internal view returns (uint cursor) {
        require(target != EMPTY);
        if (self.nodes[target].right != EMPTY) {
            cursor = treeMinimum(self, self.nodes[target].right);
        } else {
            cursor = self.nodes[target].parent;
            while (cursor != EMPTY && target == self.nodes[cursor].right) {
                target = cursor;
                cursor = self.nodes[cursor].parent;
            }
        }
    }
    function prev(Tree storage self, uint target) internal view returns (uint cursor) {
        require(target != EMPTY);
        if (self.nodes[target].left != EMPTY) {
            cursor = treeMaximum(self, self.nodes[target].left);
        } else {
            cursor = self.nodes[target].parent;
            while (cursor != EMPTY && target == self.nodes[cursor].left) {
                target = cursor;
                cursor = self.nodes[cursor].parent;
            }
        }
    }
    function exists(Tree storage self, uint key) internal view returns (bool) {
        return (key != EMPTY) && ((key == self.root) || (self.nodes[key].parent != EMPTY));
    }
    function isEmpty(uint key) internal pure returns (bool) {
        return key == EMPTY;
    }
    function getEmpty() internal pure returns (uint) {
        return EMPTY;
    }
    function getNode(Tree storage self, uint key) internal view returns (uint _returnKey, uint _parent, uint _left, uint _right, bool _red) {
        require(exists(self, key));
        return(key, self.nodes[key].parent, self.nodes[key].left, self.nodes[key].right, self.nodes[key].red);
    }

    function insert(Tree storage self, uint key) internal {
        require(key != EMPTY);
        require(!exists(self, key));
        uint cursor = EMPTY;
        uint probe = self.root;
        while (probe != EMPTY) {
            cursor = probe;
            if (key < probe) {
                probe = self.nodes[probe].left;
            } else {
                probe = self.nodes[probe].right;
            }
        }
        self.nodes[key] = Node({parent: cursor, left: EMPTY, right: EMPTY, red: true});
        if (cursor == EMPTY) {
            self.root = key;
        } else if (key < cursor) {
            self.nodes[cursor].left = key;
        } else {
            self.nodes[cursor].right = key;
        }
        insertFixup(self, key);
        self.treeSize++;
    }
    function remove(Tree storage self, uint key) internal {
        require(key != EMPTY);
        require(exists(self, key));
        uint probe;
        uint cursor;
        if (self.nodes[key].left == EMPTY || self.nodes[key].right == EMPTY) {
            cursor = key;
        } else {
            cursor = self.nodes[key].right;
            while (self.nodes[cursor].left != EMPTY) {
                cursor = self.nodes[cursor].left;
            }
        }
        if (self.nodes[cursor].left != EMPTY) {
            probe = self.nodes[cursor].left;
        } else {
            probe = self.nodes[cursor].right;
        }
        uint yParent = self.nodes[cursor].parent;
        self.nodes[probe].parent = yParent;
        if (yParent != EMPTY) {
            if (cursor == self.nodes[yParent].left) {
                self.nodes[yParent].left = probe;
            } else {
                self.nodes[yParent].right = probe;
            }
        } else {
            self.root = probe;
        }
        bool doFixup = !self.nodes[cursor].red;
        if (cursor != key) {
            replaceParent(self, cursor, key);
            self.nodes[cursor].left = self.nodes[key].left;
            self.nodes[self.nodes[cursor].left].parent = cursor;
            self.nodes[cursor].right = self.nodes[key].right;
            self.nodes[self.nodes[cursor].right].parent = cursor;
            self.nodes[cursor].red = self.nodes[key].red;
            (cursor, key) = (key, cursor);
        }
        if (doFixup) {
            removeFixup(self, probe);
        }
        delete self.nodes[cursor];
        self.treeSize--;
    }

    function treeMinimum(Tree storage self, uint key) public view returns (uint) {
        while (self.nodes[key].left != EMPTY) {
            key = self.nodes[key].left;
        }
        return key;
    }
    function treeMaximum(Tree storage self, uint key) public view returns (uint) {
        while (self.nodes[key].right != EMPTY) {
            key = self.nodes[key].right;
        }
        return key;
    }

    function rotateLeft(Tree storage self, uint key) private {
        uint cursor = self.nodes[key].right;
        uint keyParent = self.nodes[key].parent;
        uint cursorLeft = self.nodes[cursor].left;
        self.nodes[key].right = cursorLeft;
        if (cursorLeft != EMPTY) {
            self.nodes[cursorLeft].parent = key;
        }
        self.nodes[cursor].parent = keyParent;
        if (keyParent == EMPTY) {
            self.root = cursor;
        } else if (key == self.nodes[keyParent].left) {
            self.nodes[keyParent].left = cursor;
        } else {
            self.nodes[keyParent].right = cursor;
        }
        self.nodes[cursor].left = key;
        self.nodes[key].parent = cursor;
    }
    function rotateRight(Tree storage self, uint key) private {
        uint cursor = self.nodes[key].left;
        uint keyParent = self.nodes[key].parent;
        uint cursorRight = self.nodes[cursor].right;
        self.nodes[key].left = cursorRight;
        if (cursorRight != EMPTY) {
            self.nodes[cursorRight].parent = key;
        }
        self.nodes[cursor].parent = keyParent;
        if (keyParent == EMPTY) {
            self.root = cursor;
        } else if (key == self.nodes[keyParent].right) {
            self.nodes[keyParent].right = cursor;
        } else {
            self.nodes[keyParent].left = cursor;
        }
        self.nodes[cursor].right = key;
        self.nodes[key].parent = cursor;
    }

    function insertFixup(Tree storage self, uint key) private {
        uint cursor;
        while (key != self.root && self.nodes[self.nodes[key].parent].red) {
            uint keyParent = self.nodes[key].parent;
            if (keyParent == self.nodes[self.nodes[keyParent].parent].left) {
                cursor = self.nodes[self.nodes[keyParent].parent].right;
                if (self.nodes[cursor].red) {
                    self.nodes[keyParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    key = self.nodes[keyParent].parent;
                } else {
                    if (key == self.nodes[keyParent].right) {
                      key = keyParent;
                      rotateLeft(self, key);
                    }
                    keyParent = self.nodes[key].parent;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    rotateRight(self, self.nodes[keyParent].parent);
                }
            } else {
                cursor = self.nodes[self.nodes[keyParent].parent].left;
                if (self.nodes[cursor].red) {
                    self.nodes[keyParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    key = self.nodes[keyParent].parent;
                } else {
                    if (key == self.nodes[keyParent].left) {
                      key = keyParent;
                      rotateRight(self, key);
                    }
                    keyParent = self.nodes[key].parent;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    rotateLeft(self, self.nodes[keyParent].parent);
                }
            }
        }
        self.nodes[self.root].red = false;
    }

    function replaceParent(Tree storage self, uint a, uint b) private {
        uint bParent = self.nodes[b].parent;
        self.nodes[a].parent = bParent;
        if (bParent == EMPTY) {
            self.root = a;
        } else {
            if (b == self.nodes[bParent].left) {
                self.nodes[bParent].left = a;
            } else {
                self.nodes[bParent].right = a;
            }
        }
    }
    function removeFixup(Tree storage self, uint key) private {
        uint cursor;
        while (key != self.root && !self.nodes[key].red) {
            uint keyParent = self.nodes[key].parent;
            if (key == self.nodes[keyParent].left) {
                cursor = self.nodes[keyParent].right;
                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[keyParent].red = true;
                    rotateLeft(self, keyParent);
                    cursor = self.nodes[keyParent].right;
                }
                if (!self.nodes[self.nodes[cursor].left].red && !self.nodes[self.nodes[cursor].right].red) {
                    self.nodes[cursor].red = true;
                    key = keyParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].right].red) {
                        self.nodes[self.nodes[cursor].left].red = false;
                        self.nodes[cursor].red = true;
                        rotateRight(self, cursor);
                        cursor = self.nodes[keyParent].right;
                    }
                    self.nodes[cursor].red = self.nodes[keyParent].red;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[cursor].right].red = false;
                    rotateLeft(self, keyParent);
                    key = self.root;
                }
            } else {
                cursor = self.nodes[keyParent].left;
                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[keyParent].red = true;
                    rotateRight(self, keyParent);
                    cursor = self.nodes[keyParent].left;
                }
                if (!self.nodes[self.nodes[cursor].right].red && !self.nodes[self.nodes[cursor].left].red) {
                    self.nodes[cursor].red = true;
                    key = keyParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].left].red) {
                        self.nodes[self.nodes[cursor].right].red = false;
                        self.nodes[cursor].red = true;
                        rotateLeft(self, cursor);
                        cursor = self.nodes[keyParent].left;
                    }
                    self.nodes[cursor].red = self.nodes[keyParent].red;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[cursor].left].red = false;
                    rotateRight(self, keyParent);
                    key = self.root;
                }
            }
        }
        self.nodes[key].red = false;
    }
}
// ----------------------------------------------------------------------------
// End - BokkyPooBah's Red-Black Tree Library
// ----------------------------------------------------------------------------
