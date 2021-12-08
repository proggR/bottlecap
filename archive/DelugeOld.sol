pragma solidity ^0.5.0;

contract Deluge {

// NOT OLD, JUST SCRAPS


function swapPayload(Index memory idx_, Bottle storage bottle_, address asset_, uint value_, uint cost_, uint fee_) internal returns (uint){
  uint remainder = value_;
  address _recipient = bottle_.owner;
  Bottle memory btl = marketPeerAppetite[_recipient][idx_.marketHash];
  require(btl.owner == bottle_.owner && btl.asset == bottle_.asset);  //need appetite for offer/sanity check
  require(btl.value >= value_); //need appetite to be suffient (change this? brain too mush...)
  if(btl.fee < fee_) return remainder; //need agreeable fee

  uint _inValue = flipQuant(value_,cost_);
  uint _inCost = getCost(_inValue/value_);
  uint _fee = fee_ < bottle_.fee ? bottle_.fee : fee_;
  Payload memory payOut = Payload({bottle:bottle_,sender:msg.sender,recipient:_recipient,asset:asset_,value:value_,fee:_fee,cost:_inCost,
    resolved:false,blockNumber:block.number, termCode:0});
  Payload memory payIn = Payload({bottle:bottle_,sender:_recipient,recipient:msg.sender,asset:bottle_.asset,value:_inValue,fee:0,cost: cost_,
    resolved:false,blockNumber:block.number, termCode:0});
  bottle_.payloads.push(payOut);
  bottle_.payloads.push(payIn);

  /* @TODO: implement current iteration as an ERC, and then add support for approving movements of other tokens */
  /* ERC20(payOut.asset).transferFrom(payOut.sender,payOut.recipient,payOut.value);
  ERC20(payIn.asset).transferFrom(payIn.sender,payIn.recipient,payIn.value); */
  emit PayloadSent(payOut.sender,payOut.recipient,payOut.asset,payOut.value);
  emit PayloadSent(payIn.sender,payIn.recipient,payIn.asset,payIn.value);


  balances[_recipient] -= fee_;
  balances[msg.sender] += fee_;
  emit Transfer(payIn.sender,payIn.recipient,payOut.fee);

  if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
    DTermPayloadProcessor(termRegistry[bottle_.termCode]).process(
      payOut.sender, payOut.asset, payOut.value,payIn.fee,
      payOut.recipient, payIn.asset, payIn.value, block.number
      );
    DTermPayloadProcessor(termRegistry[bottle_.termCode]).process(
      payIn.sender, payIn.asset, payIn.value,payOut.fee,
      payIn.recipient, payOut.asset, payOut.value, block.number
      );
  }

  remainder -= bottle_.value > value_ ? value_ : bottle_.value;
  bottle_.value -= bottle_.value > value_ ? value_ : bottle_.value;
  if(bottle_.value == 0){
    bottle_.open = false;
  }
  if(bottle_.termCode>0 && termRegistry[bottle_.termCode] != address(0)){
    DTermBottleProcessor(termRegistry[bottle_.termCode]).process(
      bottle_.owner, payOut.asset, bottle_.initialValue, bottle_.blockNumber,
      payOut.recipient, payIn.asset, payIn.value, block.number
      );
  }

  if(!bottle_.open){
    emit BottleCapped(bottle_.owner,bottle_.asset);
    delete marketPeerAppetite[bottle_.owner][idx_.marketHash];
    delete marketSeedBandwidth[bottle_.owner][idx_.peerMarketHash];
  }
  return remainder;
}



function mint(address assetIn_, uint valueIn_, address assetOut_, uint valueOut_, uint fee_) public payable returns (bool) {
  (bytes32 hashIn,bytes32 hashOut) = marketHashes(assetIn_,assetOut_);

  uint curs = marketIdxCursor;
  marketIdxCursor++;

  Index memory idxIn = Index({idx:curs,maxNatural:true, marketHash:hashIn,peerMarketHash:hashOut});
  marketIdx[hashIn] = idxIn;
  idxMarket[idxIn.idx] = hashIn;
  marketInputs[hashIn] = assetIn_;
  marketOutputs[hashIn] = assetOut_;
  assetMarkets[assetIn_].push(assetOut_);

  Index memory idxOut = Index({idx:curs,maxNatural:false, marketHash:hashOut,peerMarketHash:hashIn});
  marketIdx[hashOut] = idxOut;
  idxMarket[idxOut.idx] = hashOut;
  marketInputs[hashOut] = assetOut_;
  marketOutputs[hashOut] = assetIn_;
  assetMarkets[assetOut_].push(assetIn_);

  uint _cost = getCost(valueIn_/valueOut_);
  uint _flippedCost = getCost(valueOut_/valueIn_);

  Bottle memory _bottleIn = Bottle({owner:msg.sender,asset:assetIn_,value:valueIn_,initialValue:valueIn_,fee:fee_,cost:_cost, blockNumber: block.number,open:true,
    designatedRecipient:address(0),handshakeHash:'',messages:new address[](0),costs: new uint256[](0),payloads:new Payload[](0),termCode:0});
  Bottle memory _bottleOut = Bottle({owner:msg.sender,asset:assetOut_,value:valueOut_,initialValue:valueOut_,fee:fee_,cost:_flippedCost, blockNumber: block.number,open:true,
    designatedRecipient:address(0),handshakeHash:'',messages:new address[](0),costs:new uint256[](0),payloads:new Payload[](0),termCode:0});


  // will this work?... might need to think up a better way to reward minting than 2 bottles... that might not actually work like this :\
  marketSeedBandwidth[msg.sender][hashIn] = _bottleIn;
  marketPeerAppetite[msg.sender][hashOut] = _bottleOut;

  insertOption(hashIn,_cost);
  insertOption(hashOut,_flippedCost);

  emit PairHashed(hashIn,assetIn_, assetOut_);
  emit PairHashed(hashOut, assetOut_, assetIn_);
  emit BottleSent(_bottleIn.owner,hashIn,_bottleIn.asset,_bottleIn.value,_bottleIn.cost,_bottleIn.fee);
  emit BottleSent(_bottleOut.owner,hashOut,_bottleOut.asset,_bottleOut.value,_bottleOut.cost,_bottleOut.fee);

  if(_bottleIn.termCode>0 && termRegistry[_bottleIn.termCode] != address(0)){
    DTermBottleProcessor(termRegistry[_bottleIn.termCode]).create(
      _bottleIn.owner,hashIn,_bottleIn.asset,_bottleIn.value,_bottleIn.cost,_bottleIn.fee);
  }
  if(_bottleOut.termCode>0 && termRegistry[_bottleOut.termCode] != address(0)){
    DTermBottleProcessor(termRegistry[_bottleOut.termCode]).create(
      _bottleOut.owner,hashOut,_bottleOut.asset,_bottleOut.value,_bottleOut.cost,_bottleOut.fee);
  }
}


///




    // admin variable to store the address of the admin
    address admin;

    mapping(address=>Peer) peers;
    mapping(uint=>address) termRegistry;

    //map peer=>market=>bottle
    mapping(address=>mapping(string=>Bottle)) marketSeedBandwidth;
    mapping(address=>mapping(string=>Bottle)) marketPeerAppetite;

    //map peer=>asset=>bottle
    mapping(address=>mapping(address=>Bottle)) assetSeedBandwidth;
    mapping(address=>mapping(address=>Bottle)) assetPeerAppetite;

    //assetPriceLists
    //map asset=>fee=>bottle
    mapping(address=>mapping(uint=>Bottle)) assetOptions;

    //marketPriceLists
    //map asset=>cost=>bottle
    //cost = unitsOut/unitsIn + fee
    //if collision, increment/decrement key for bandwidth until
    //empty key found
    mapping(string=>mapping(uint=>Bottle)) marketOptions;

    //^ @TODO: fix that... definitely shit, and critical to
    //the performance of the model

    //map asset=>peer
    mapping(address=>address) activeSeeds;
    mapping(address=>address) activeConsumers;

    //mapping(address=>mapping(string=>uint)) chokingNum;
    //mapping(address=>mapping(string=>uint)) chokedByNum;

    mapping(string=>address) marketInputs;
    mapping(string=>address) marketOutputs;

    struct Bottle {
        address owner;
        address asset;
        uint value;
        uint fee;
        uint cost;
        Payload[] payloads;
        bool open; //bit confusing with the bottle vs bag ref now :\ lol
        uint termCode;
    }

    struct Payload {
        address sender;
        address recipient;
        address asset;
        uint value;
        uint fee;
        uint cost;
        bool resolved;
        uint termCode;
    }

    function registerTermContract(uint termCode, address termContract) public onlyOwner returns (bool){
      //require code not already be in use
      require(termRegistry[termCode] == address(0));
      //add a step here to ensure it conforms to interface... once exists
      termRegistry[termCode] = termContract;
    }

    function sendBottle() public returns (bool){
        Bottle btl = Bottle({sender:msg.sender,recipient:_recipient,asset:payloadType,value:_value,fee:_fee,cost:_cost});
    }

    function resolve(address payloadType, address _recipient, uint _value, uint _fee) public returns (bool){
      Bottle btl = assetPeerAppetite[payloadType][_recipient];
      require(btl);  //need appetite for offer
      require(btl.fee <= _fee); //need agreeable fee
      require(btl.value >= _value); //need appetite to be suffient

      uint _cost = stuff/stuff + fee;

      Payload payOut = Payload({sender:msg.sender,recipient:_recipient,asset:payloadType,value:_value,fee:_fee,cost:_cost});
      Payload payIn = Payload({sender:_recipient,recipient:msg.sender,asset:payloadType,value:_value,fee:_fee,cost:_cost});
      btl.payloads.push(payOut);
      btl.payloads.push(payIn);

      ERC20(payOut.asset).transferFrom(payOut.sender,payOut.recipient,payOut.value);
      ERC20(payIn.asset).transferFrom(payIn.sender,payIn.recipient,payIn.value);
      balances[_recipient] -= _fee;
      balances[msg.sender] += _fee;
      emit Transfer(msg.sender,_recipient,_fee);

      bottle.value -= bottle.value > _value ? _value : bottle.value;
      if(bottle.value == 0){
        btl.open = false;
        //remove from appetite/seed mappings
      }

      if(btl.termCode>0 && termRegistry[btl.termCode]){
      DTermProcessor(termRegistry[btl.termCode]).process(btl,payOut,payIn);
      }
    }




    //MarketInterest[] interests;
    //MarketOffers[] offers;
    //Wires[] wires;

    //Function is used by the admin to add a bank to the KYC Contract.
    function registerPeer(string memory uName) public payable returns(bool) {
        peers[msg.sender] = Peer({pstr:'v0',uname:uName});
        emit Peered(msg.sender,uName);
    }


    //Function is used by the admin to add a bank to the KYC Contract.
    function registerInterest(string memory marketName, uint sent,uint requested,uint fees) public payable returns(bool) {
        MarketInterest int = MarketInterest({pstr:'v0',interested:msg.sender,marketHash:marketName,outgoingUnits:sent,incomingUnits:requested,feeTolerance:fees});
        peers[msg.sender].interests.push(int);
        peerAppetite[msg.sender][marketName] = requested;
        peerTolerance[msg.sender][marketName] = fees;
        emit Interest(msg.sender,marketName,sent,requested,fees);
    }

    //Function is used by the admin to add a bank to the KYC Contract.
    function registerOffer(string memory marketName, uint sent,uint requested,uint fees) public payable returns(bool) {
        MarketOffer off = MarketOffer({pstr:'v0',offerer:msg.sender,marketHash:marketName,outgoingUnits:sent,incomingUnits:requested,fee:fees});
        peers[msg.sender].offers.push(off);
        peerBandwidth[msg.sender][marketName] = sent;
        emit Offer(msg.sender,marketName,sent,requested,fees);
    }

    //Function is used by the admin to add a bank to the KYC Contract.
    function openWire(string memory marketName,address recp, uint sent,uint fees) public payable returns(bool) {
        Peer toP = peers[recp];
        require(sent <= toP.interests[marketName].incomingUnits && fees <= toP.interests[marketName].feeTolerance);

        Wire wire = Wire({pstr:'v0',interested:recp,fullfiller:msg.sender,marketHash:marketName,outgoingUnitsCommitted:sent,feesCollected:fees});
        Interest interest = toP.interests[marketName];
        interest.wires.push(wire);

        uint blah = (sent*100)/((interest.incomingUnits - interest.incomingFulfilled)*100)/100;
        uint takenOut = blah*(interest.outgoingUnits - interest.outgoingSent);

        interest.incomingFulfilled += sent;
        interest.outgoingSent += takenOut;
        interest.feesSent += fees;

        peers[msg.sender][marketName].wires.push(wire);
        toP.wires[marketName].push(wire);
        toP.interests[marketName] = interest;

        emit Offer(msg.sender,marketName,sent,requested,fees);
    }



    //  Struct Peer

    struct Peer {
        string pstr;
        address uname;
        string dataHash;
        uint chokedNum;
        uint chokingNum;
        uint interestNum;
        uint interestedNum;

        mapping(address=>bool) choking;
        mapping(address=>bool) interested;

        //prolly change: hash 2 contract addresses together... prolly not address?
        //basically: map hashed market ID of 2 addies to the receiver addy
        //to the amount of the outgoing committed to on the wire
        //mapping(address=>mapping(address=>uint) wires;

        mapping(string=>MarketInterest) interests;
        mapping(string=>MarketOffers) offers;
        mapping(string=>Wire[]) wires;

        uint uploaded;
        uint downloaded;
    }

    struct MarketInterest{
      string pstr;
      string reserved;
      string marketHash;
      address interested;
      uint outgoingUnits; //what the interested party has
      uint incomingUnits; //what they want
      uint feeTolerance;
      uint feesSent;
      Wire[] wires;
      uint incomingFulfilled;
      uint outgoingSent;
    }

    struct MarketOffer{
      string pstr;
      string reserved;
      string marketHash;
      address offerer;
      uint outgoingUnits; //what the offering party has
      uint incomingUnits; //what the offering party wants/will accept
      uint fee;
      uint feesCollected;
      Wire[] wires;
      uint outgoingSent;
      uint incomingCollected;
    }

    struct Wire {
      string pstr;
      string reserved;
      string marketHash;
      address interested;
      address fullfiller;
      uint outgoingUnitsCommitted;
      uint feeCollected;
    }


}
