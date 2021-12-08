pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
/* import {BokkyPooBahsRedBlackTreeLibrary } from "./BokkyPooBahsRedBlackTreeLibrary.sol"; */
/* import "./BottleBase.sol"; */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/* import {DTermBottleProcessor, DTermPayloadProcessor, DTermAuth } from "./DTerm.sol"; */

contract BottlecapPreOpts is ERC20 {
using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;

    // EVENTS

    event Transfer(address indexed sender, address indexed recipient, uint256 indexed fee);
    event PairHashed(bytes32 indexed marketHash, address indexed assetIn , address indexed assetOut);
    event BottleSent(address owner, bytes32 indexed marketHash, uint indexed value, uint indexed cost, address asset, uint fee);
    event BottleUpdated(address owner, bytes32 indexed marketHash, uint indexed value, uint indexed cost, uint fee);
    event BottleCapped(address indexed owner, address indexed asset);
    event PayloadSent(address sender, address indexed recipient, address indexed asset, uint indexed value);
    event SpotCheck(bytes32 indexed marketHash,uint256 indexed cost);
    event Peered(address indexed peer,bytes32 indexed handle);

    // ADMIN/UTILITY STATE + CONSTRUCTER

    address admin;
    address owner;
    bool halted;
    mapping(bytes32=>bool) marketHalts;
    mapping(address=>bool) peerHalts;

    constructor(uint256 initialSupply) public ERC20("Bottlecap", "BTLD") {
        uint totalSupply = initialSupply*10**8;
        _mint(msg.sender, totalSupply);
        admin = msg.sender;
        owner = msg.sender;
        marketIdxCursor = 0;
        halted = true;
    }

    modifier onlyOwner {
            require(owner == msg.sender);
          _;
      }

    modifier onlyAdmin {
            require(owner == msg.sender || admin == msg.sender);
          _;
      }

    // SEED/CONSUMER BOTTLE MAPPINGS

    //map peer=>market=>bottle
    mapping(address=>mapping(bytes32=>Bottle)) marketSeedBandwidth;
    mapping(address=>mapping(bytes32=>Bottle)) marketPeerAppetite;

    // MARKET COSTS STATE

    mapping(uint256=>uint256) currentSpot;

    mapping(uint256=>BokkyPooBahsRedBlackTreeLibrary.Tree) marketTrees;
    mapping(uint256=>mapping(uint=>address)) treeAddresses;


    // INDEX STATE
    uint marketIdxCursor;
    mapping(bytes32=>Index) marketIdx;


    // MARKET ASSET MAPPING STATE

    //inputs/outputs for each markethash
    mapping(bytes32=>address) marketInputs;
    mapping(bytes32=>address) marketOutputs;

    // STRUCTS

    struct Index {
        uint256 idx;
        bool maxNatural;
        bytes32 marketHash;
        bytes32 peerMarketHash;
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
      require(!halted && !marketHalts[marketHash_]);
      require(!peerHalts[msg.sender]);
      Index memory _idx = marketIdx[marketHash_];
      require(_idx.idx > 0);
      address inputContract = marketInputs[marketHash_];
      require(asset_ == inputContract);

      uint _cost = getCost(value_,valueOut_);

      uint _unfilled = fill(_idx, asset_, value_, valueOut_, fee_, 0);
      if(_unfilled == 0) return false;

      sendBottle(_idx, asset_, _unfilled, _cost, fee_);
      return true;
    }

    function recant(bytes32  marketHash_) public returns (bool){
      Bottle memory _bottle = marketSeedBandwidth[msg.sender][marketHash_];
      if(_bottle.owner != msg.sender){
        _bottle = marketPeerAppetite[msg.sender][marketHash_];
        if(_bottle.owner != msg.sender){
          return false; //doesn't appear to be anything here mate;
        }
      }
      Index memory _idx = marketIdx[marketHash_];
      removeOption(_idx,_bottle.correctedCost);


      delete marketSeedBandwidth[msg.sender][marketHash_];
      delete marketPeerAppetite[msg.sender][marketHash_];
      return true;
    }

    function mint(address assetIn_, uint valueIn_, address assetOut_, uint valueOut_, uint fee_) public payable returns (bool) {
      (bytes32 _hashIn,bytes32 _hashOut) = marketHashes(assetIn_,assetOut_);

      uint _curs = marketIdxCursor;
      marketIdxCursor++;

      marketTrees[_curs] = BokkyPooBahsRedBlackTreeLibrary.Tree({root:0,treeSize:0});

      uint _cost = getCost(valueIn_,valueOut_);
      uint _flippedCost = getCost(valueOut_,valueIn_);

      mintHash(_curs, assetIn_, valueIn_, assetOut_, true, _hashIn, _hashOut, _cost, fee_);
      mintHash(_curs, assetOut_, valueOut_, assetIn_, false, _hashOut, _hashIn, _flippedCost, fee_);
    }

    // CORE INTERNAL FUNCTIONS

    function mintHash(uint curs_, address assetIn_, uint valueIn_, address assetOut_, bool maxNatural_, bytes32 marketHash_, bytes32 peerMarketHash_, uint cost_, uint fee_) internal returns (bool){
      Index memory _idx = Index({idx:curs_,maxNatural:maxNatural_, marketHash:marketHash_,peerMarketHash:peerMarketHash_});
      uint _unitCorrectedCost = maxNatural_ ? cost_ : flipCost(valueIn_,cost_);

      marketIdx[marketHash_] = _idx;
      /* idxMarket[_idx.idx] = marketHash_; */
      marketInputs[marketHash_] = assetIn_;
      marketOutputs[marketHash_] = assetOut_;

      Bottle memory _bottle = Bottle({owner:msg.sender,asset:assetIn_,value:valueIn_,initialValue:valueIn_,fee:fee_,cost:cost_, correctedCost:_unitCorrectedCost, blockNumber: block.number,open:true, payloadsLength:0});//,
        /* designatedRecipient:address(0),handshakeHash:'',messages:new address[](0),costs: new uint256[](0),termCode:0}); */

      if(maxNatural_){
        marketSeedBandwidth[msg.sender][marketHash_] = _bottle;
        insertOption(_idx,cost_);
      }else{
        marketPeerAppetite[msg.sender][marketHash_] = _bottle;
      }

      emit PairHashed(marketHash_,assetIn_, assetOut_);
      emit BottleSent(_bottle.owner,marketHash_,_bottle.value,_bottle.cost,_bottle.asset,_bottle.fee);
    }

    //cost = output/input
    //for natural, that's correct, otherwise flip
    function fill(Index memory idx_, address asset_, uint value_, uint valueOut_, uint fee_, uint passes_) internal returns (uint){
      uint _peerCost = getCost(valueOut_,value_);
      uint _key; address _highestBid;

      if(passes_ == 0){
      ( _key, _highestBid) = maxOption(idx_,( idx_.maxNatural
                                                            ? getCost(value_,valueOut_) :
                                                            flipCost(value_,getCost(value_,valueOut_))
                                                        ));
      }else{
        ( _key, _highestBid) = nextMaxOption(idx_,( idx_.maxNatural
                                                              ? getCost(value_,valueOut_) :
                                                              flipCost(value_,getCost(value_,valueOut_))
                                                          ));
      }

      Bottle storage _bottle = marketPeerAppetite[_highestBid][idx_.marketHash];

      if(_bottle.cost <= _peerCost){
          while(_bottle.cost <= _peerCost && _bottle.asset == asset_){
            (_key,_highestBid) = nextMaxOption(idx_,_key);
            _bottle = marketPeerAppetite[_highestBid][idx_.marketHash];
          }

          if(_bottle.cost >= _peerCost && _bottle.asset != asset_){
            value_ = swapPayloads(idx_,_key, _bottle, asset_, value_, getCost(value_,valueOut_), fee_);
             // "maxPasses" = 8. 16 might work too/be optimal? cuz 256 seemed to be the ideal "max" search depth for this lib, so root 256 = 16 cuz binary tree? idunno
            if(value_ > 0 && passes_ < 8){
              value_ = fill(idx_, asset_, value_, getQuant(value_,getCost(value_,valueOut_)), fee_, (passes_+1));
            }else{value_ = 0;}
          }
      }
      if(passes_ == 0){
        currentSpot[idx_.idx] = _bottle.cost;
        emit SpotCheck(idx_.marketHash,_bottle.cost);
        emit SpotCheck(idx_.peerMarketHash,_bottle.cost);
      }

      return value_;
    }

    function sendBottle(Index memory idx_,address asset_, uint value_, uint cost_, uint fee_) internal returns (bool){
      uint _unitCorrectedCost = idx_.maxNatural ? cost_ : flipCost(value_,cost_);

      Bottle memory _bottle = marketSeedBandwidth[msg.sender][idx_.marketHash];
      if(_bottle.value > 0){ //lazy existance check
          removeOption(idx_,_bottle.correctedCost);
          _bottle.value += value_;
          _bottle.fee = fee_;
          _bottle.cost = _unitCorrectedCost;
          emit BottleUpdated(_bottle.owner, idx_.marketHash,_bottle.value, _bottle.cost, _bottle.fee);

      }else{
          _bottle = Bottle({owner:msg.sender,asset:asset_,value:value_,initialValue:value_,fee:fee_,cost:cost_, correctedCost:_unitCorrectedCost, blockNumber: block.number,open:true, payloadsLength: 0});
          emit BottleSent(msg.sender,idx_.marketHash,value_,_unitCorrectedCost,asset_,fee_);
      }

      marketSeedBandwidth[msg.sender][idx_.marketHash] = _bottle;
      marketPeerAppetite[msg.sender][idx_.peerMarketHash] = _bottle;

      insertOption(idx_,_unitCorrectedCost);
    }

    function swapPayloads(Index memory idx_, uint key_, Bottle storage bottle_, address asset_, uint value_, uint cost_, uint _fee) internal returns (uint){
      require(bottle_.value >= value_); //need appetite to be suffient (change this? brain too mush...)
      if(bottle_.fee < _fee) return value_; //need agreeable fee


      uint _value = value_ <= bottle_.value ? value_ : bottle_.value;
      uint _peerCost = flipCost(value_,cost_);
      uint _peerValue = flipQuant(value_,cost_);
      _fee = _fee < bottle_.fee ? bottle_.fee : _fee;

      value_ -= _value;
      bottle_.value -= _peerValue;

      sendPayload(bottle_, msg.sender, bottle_.owner, asset_, _value, cost_, _fee);
      sendPayload(bottle_, bottle_.owner, msg.sender, bottle_.asset, _peerValue, _peerCost, 0);

       transferFrom(bottle_.owner, msg.sender,_fee);

      if(bottle_.value == 0){

        emit BottleCapped(bottle_.owner,bottle_.asset);
        removeOption(idx_,key_);
        delete marketPeerAppetite[bottle_.owner][idx_.marketHash];
        delete marketSeedBandwidth[bottle_.owner][idx_.peerMarketHash];
      }
      return value_;
    }

    function sendPayload(Bottle storage bottle_, address from_, address to_, address assetIn_, uint valueIn_, uint cost_, uint fee_) internal returns (bool){
      uint _fee = fee_;

      Payload memory _pay = Payload({bottle:bottle_,sender:from_,recipient:to_,asset:assetIn_,value:valueIn_,fee:_fee,cost:cost_});//,
        /* resolved:false,blockNumber:block.number, termCode:0}); */

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

    function flipCost(uint value_, uint cost_) internal pure returns (uint256){
      uint _costMultiplier = 10*10**18;
      return ((value_*_costMultiplier)/flipQuant(value_,cost_)*_costMultiplier)/_costMultiplier;
      /* return getCost(flipQuant(value_,cost_),value_); */
    }

    // supports 18 decimal places
    function getCost(uint costIn_, uint costOut_) internal pure returns (uint256){
      uint _costMultiplier = 10*10**18;
      return ((costOut_*_costMultiplier)/(costIn_*_costMultiplier))/_costMultiplier;
    }

    // supports 18 decimal places
    function getQuant(uint value_, uint cost_) internal pure returns (uint256){
      uint _costMultiplier = 10*10**18;
      return ((value_*_costMultiplier)*(cost_*_costMultiplier))/_costMultiplier;
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

    function togglePeer(address peer_) public onlyAdmin returns (bool){
      bool state = peerHalts[peer_];
      peerHalts[peer_] = !state;
      return !state;
    }

    function toggleMachine() public onlyOwner returns (bool){
      halted = !halted;
      return halted;
    }

    function toggleMarket(bytes32 marketHash_) public onlyOwner returns (bool){
      bool state = marketHalts[marketHash_];
      marketHalts[marketHash_] = !state;
      return !state;
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
