pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
import {BokkyPooBahsRedBlackTreeLibrary } from "./BokkyPooBahsRedBlackTreeLibrary.sol";
/* import {DTermBottleProcessor, DTermPayloadProcessor, DTermAuth } from "./DTerm.sol"; */

contract FractionalDeluge {
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
    mapping(address=>uint256) balances;
    bool halted;
    mapping(bytes32=>bool) marketHalts;
    mapping(address=>bool) peerHalts;

    constructor() public {
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
    /* mapping(uint256=>bytes32) idxMarket; */

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
        /* uint termCode;
        address designatedRecipient;
        bytes32 handshakeHash; //<- probably actually shouldn't store this?... think it through before adding support. maybe just store a signature instead
        address[] messages; //need to make cost an array as well if I do this... see simple version work first... so close :\
        uint[] costs;//maybe just maybe bottle cost weighted average for this basket?... dunno */
    }

    struct Payload {
        Bottle bottle;
        address sender;
        address recipient;
        address asset;
        uint value;
        uint fee;
        uint cost;
        /* uint blockNumber;
        uint termCode;
        bool resolved; */
    }

    // CORE PUBLIC FUNCTIONS

    function announce(bytes32  marketHash_, address asset_, uint value_, uint valueOut_, uint fee_) public returns (bool){
      require(!halted);
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

    /* @TODO: implement p2pMarkets version of announcement, and adapt/reimplement fill/sendBottle if/as needed */
    /* function whisper(bytes32  marketHash_, address asset_, uint value_, uint cost_, uint fee_) public returns (bool){
      return false;
    } */

    /* @TODO: implement p2p group Markets version of announcement/whisper, and adapt/reimplement fill/sendBottle if/as needed */
    /* function pool(bytes32  marketHash_, address asset_, uint value_, uint cost_, uint fee_) public returns (bool){
      return false;
    } */

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

      /* if(_bottle.termCode>0 && termRegistry[_bottle.termCode] != address(0)){
        DTermBottleProcessor(termRegistry[_bottle.termCode]).create(
          _bottle.owner,marketHash_,_bottle.asset,_bottle.value,_bottle.cost,_bottle.fee);
      } */
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

      if(_bottle.cost >= _peerCost){
          while(_bottle.cost >= _peerCost && _bottle.asset == asset_){
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
          /* if(_bottle.termCode>0 && termRegistry[_bottle.termCode] != address(0)){
            DTermBottleProcessor(termRegistry[_bottle.termCode]).update(
              _bottle.owner, _bottle.asset,_bottle.value, _bottle.cost, _bottle.fee);
          } */
      }else{
          _bottle = Bottle({owner:msg.sender,asset:asset_,value:value_,initialValue:value_,fee:fee_,cost:cost_, correctedCost:_unitCorrectedCost, blockNumber: block.number,open:true, payloadsLength: 0});//,
            /* designatedRecipient:address(0),handshakeHash:'',messages:new address[](0),costs:new uint256[](0),termCode:0}); */
          emit BottleSent(msg.sender,idx_.marketHash,value_,_unitCorrectedCost,asset_,fee_);
          /* if(_bottle.termCode>0 && termRegistry[_bottle.termCode] != address(0)){
            DTermBottleProcessor(termRegistry[_bottle.termCode]).create(
              _bottle.owner,idx_.marketHash,_bottle.asset,_bottle.value,_bottle.cost,_bottle.fee);
          } */
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
      uint _inValue = flipQuant(value_,cost_);
      _fee = _fee < bottle_.fee ? bottle_.fee : _fee;

      value_ -= _value;
      bottle_.value -= _inValue;

      sendPayload(bottle_, msg.sender, bottle_.owner, asset_, _value, cost_, _fee);
      sendPayload(bottle_, bottle_.owner, msg.sender, bottle_.asset, _inValue, _peerCost, 0);

      balances[bottle_.owner] -= _fee;
      balances[msg.sender] += _fee;
      emit Transfer(bottle_.owner,msg.sender,_fee);

      /* if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
        dPayloadProcessor(bottle_, msg.sender, bottle_.owner, asset_, value_, bottle_.asset, _inValue, _fee, 0);
      } */

      if(bottle_.value == 0){
        /* bottle_.open = false; */
      /* } */
      /* if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
        dBottleProcessor(bottle_);
      } */

      /* if(!bottle_.open){ */
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

    // DTERM FUNCTIONS

    /* function dPayloadProcessor(Bottle storage bottle_, address sender_, address recipient_, address assetIn_, uint valueIn_, address assetOut_, uint valueOut_, uint feeIn_, uint feeOut_) internal{
      if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
        DTermPayloadProcessor(termRegistry[bottle_.termCode]).process(
          sender_, assetIn_, valueIn_,feeIn_,
          recipient_,assetOut_, valueOut_, block.number
          );
        DTermPayloadProcessor(termRegistry[bottle_.termCode]).process(
          recipient_,assetOut_, valueOut_,feeOut_,
          sender_, assetIn_, valueIn_, block.number
          );
      }
    } */

    /* function dBottleProcessor(Bottle storage bottle_) internal{ //Bottle storage bottle_, address owner_, address recipient_, address assetIn_, uint valueIn_, address assetOut_, uint valueOut_, uint feeIn_, uint feeOut_){
      if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
        DTermBottleProcessor(termRegistry[bottle_.termCode]).process(
          owner_, _payOut.asset, bottle_.initialValue, bottle_.blockNumber,
          _payOut.recipient, _payIn.asset, _payIn.value, block.number
          );
      }
    } */

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

/* function flipCost(uint value_, uint cost_) internal pure returns (uint256){
  uint _costMultiplier = 10*10**18;
  return ((value_*_costMultiplier)/flipQuant(value_,cost_)*_costMultiplier)/_costMultiplier;
} */
// supports 18 decimal places
/* function getQuant(uint value_, uint cost_) internal pure returns (uint256){
  uint _costMultiplier = 10*10**18;
  return ((value_*_costMultiplier)*(cost_*_costMultiplier))/_costMultiplier;
} */

    /* function privateMarketHash(address inAsset_, address inPeer_, address outAsset_, address outPeer_, bytes32 handshakeHash_) public view returns (bytes32){
      return bytes32(bytes(sha256(inPeer_,inAsset_,outPeer_,outAsset_,handshakeHash_)));
    } */

    /* function privateMarketHashes(address inAsset_, address inPeer_, address outAsset_, address outPeer_, bytes32 handshakeHash_) public view returns (bytes32,bytes32){
      return (bytes32(bytes(sha256(inPeer_,inAsset_,outPeer_,outAsset_,handshakeHash_))),
              bytes32(bytes(sha256(outPeer_,outAsset_,inPeer_,inAsset_,handshakeHash_))));
    } */


// DTERM REGISTRY/ADMIN STATE
//mostly to be implemented later, and tightly controlled to start (if finished/launched ever)
//idea: term = industry specific processing appended onto each event
//passes in the transactional data required to trace each swap, ensuring its
//deletion within this contract doesn't prevent it from existing elsewhere,
//and not depending solely on internally raised events to do the job
/* mapping(uint=>address) termRegistry;
mapping(address=>uint256[]) peerPermittedTerms; */
//available asset pairs for each asset (as the asset's address, rather than the hash to keep UI options more flexible)
/* mapping(address=>address[]) assetMarkets; */


/*

mapping(address=>bool) assetHalts;
mapping(address=>bool) peerKicks;


    function toggleAsset(address asset_) public onlyOwner returns (bool){
      bool state = assetHalts[asset_];
      assetHalts[asset_] = !state;
      if(!state){
        //toggle off all active markets for asset (ie: force halts on any active pairs)
      }
      return !state;
    } */


    /* function kickPeer(address peer_) public onlyOwner returns (bool){
      peerKicks[peer_] = true;
      peerHalts[peer_] = true;
    }

    //doubtful a kicked address would be unkicked, but in case mods/whoever fucks up
    function unkickPeer(address peer_) public onlyOwner returns (bool){
      peerKicks[peer_] = false;
      peerHalts[peer_] = false;
    } */

/*
    function registerTermContract(uint termCode, address termContract) public onlyOwner returns (bool){
      //require code not already be in use
      require(termRegistry[termCode] == address(0));
      //add a step here to ensure it conforms to interface... once exists
      termRegistry[termCode] = termContract;
    } */


    //dunno why this is payable, revisit... prolly just copypaste, but should it be maybe?
    /* function registerPeer(bytes32  uName) public payable returns(bool) {
        peers[msg.sender] = Peer({pstr:'v0',uname:uName});
        emit Peered(msg.sender,uName);
    } */

// PEER STATE

/* mapping(address=>Peer) peers; */
/* mapping(address=>Peer) openMarketPeers; */
/* mapping(address=>Peer) openAssetPeers; */
//mapping(address=>mapping(bytes32=>uint)) chokingNum;
//mapping(address=>mapping(bytes32=>uint)) chokedByNum;
// map marketHash=>Bottle
/* mapping(bytes32=>Bottle) p2pMarkets; */
// map marketHash=>Bottle
/* mapping(bytes32=>Bottle) p2pGroupMarkets; */


    /* struct Peer {
        bytes32 pstr;
        address uname;
        bytes32 dataHash;
        uint chokedNum;
        uint chokingNum;
        uint interestNum;
        uint interestedNum;

        mapping(address=>bool) choking;
        mapping(address=>bool) interested;

        uint uploaded;
        uint downloaded;
    } */

    /* function getInputMarkets(address asset_) public view returns (address[] memory){
      return assetMarkets[asset_];
    }

    function getOutputMarkets(address asset_) public view returns (address[] memory){
      return assetMarkets[asset_];
    } */


/* function minOption(Index memory idx_, uint cost_) internal view returns (uint, address){
  uint _key;
  if(idx_.maxNatural){
    _key = marketTrees[idx_.idx].treeMinimum(cost_);
  }else{
    _key  = marketTrees[idx_.idx].treeMaximum(cost_);
  }
  return (_key,treeAddresses[idx_.idx][_key]);
}

function nextMinOption(Index memory idx_, uint cost_) internal view returns (uint, address){
  uint _key;
  if(idx_.maxNatural){
    _key = marketTrees[idx_.idx].next(cost_);
  }else{
    _key  = marketTrees[idx_.idx].prev(cost_);
  }
  return (_key,treeAddresses[idx_.idx][_key]);
} */

/* function calcSeedCost(uint cost_, uint fee_){
return (1000000000000000000*10**18)/(cost_+fee_);
}

function calcConsumerCost(uint cost_, uint fee_){
return cost_+fee_;
} */

/*
@TODO: add asset level announcements/matchmaking
*/


    //map asset=>peer
    /* mapping(address=>mapping(address=>bool)) activeSeeds;
    mapping(address=>mapping(address=>bool)) activeConsumers; */

    //assetPriceLists
    //map asset=>fee=>bottle
    /* mapping(address=>mapping(uint=>Bottle)) assetOptions; */


    //map peer=>asset=>bottle
    /* mapping(address=>mapping(address=>Bottle)) assetSeedBandwidth;
    mapping(address=>mapping(address=>Bottle)) assetPeerAppetite;

    function getInt(uint256 _value, uint256 _position, uint256 _size) public pure returns(uint256){
        uint256 a = ((_value % (10 ** _position)) - (_value % (10 ** (_position - _size)))) / (10 ** (_position - _size));
        return a;
    }

    function addy2Num(address a) internal pure returns (uint256) {
      return uint256(uint160(a));
    }

^ keep those 2 functions, they're gud
    */
