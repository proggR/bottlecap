pragma solidity ^0.6.0;
contract DTermBottleProcessor {
    mapping(uint=>address) authRegistry;
    uint[] auths;
    /* mapping(address=>uint256[]) peerPermittedAuths; */

    //don't worry about the Deluge, we brought CUPS!
    event DTermBottleBottleCreated(address sender, bytes32 marketHash, address asset, uint value ,uint cost, uint fee);
    event DTermBottleBottleUpdated(address owner, address asset, uint value, uint cost, uint fee);
    event DTermBottleProcessed(address initiater, address asset, uint value, uint blockNum, address recipient, address swap, uint swapValue, uint swapBlockNum);


    function create(address sender_, bytes32 marketHash_, address asset_, uint value_, uint cost_, uint fee_) public returns (bool){
      emit DTermBottleBottleCreated(sender_, marketHash_, asset_, value_, cost_, fee_);
    }

    function update(address owner_, address asset_, uint value_, uint cost_, uint fee_) public returns (bool){
      emit DTermBottleBottleUpdated(owner_, asset_, value_, cost_, fee_);
    }

    function process(address initiater_, address asset_, uint value_, uint blockNum_, address recipient_, address swap_, uint swapValue_, uint swapBlockNum) public returns (bool) {
      emit DTermBottleProcessed(initiater_, asset_, value_, blockNum_, recipient_, swap_, swapValue_, swapBlockNum);
    }

    function submit()  public returns (bool){
      if(auths.length > 0){
        uint i;
        for(i=0;i<auths.length;i++){
          DTermAuth(authRegistry[i]).submit();
        }
      }
    }
}

contract DTermPayloadProcessor {

    event DTermPayloadProcessed(address initiater_, address asset_, uint value_, uint fee_, address recipient_, address swap_, uint swapValue_, uint blockNum_);

    function process(address initiater_, address asset_, uint value_, uint fee_, address recipient_, address swap_, uint swapValue_, uint blockNum_)  public returns (bool) {
      emit DTermPayloadProcessed(initiater_, asset_, value_, fee_, recipient_, swap_, swapValue_, blockNum_);
    }
}


contract DTermAuth {
  mapping(address=>bool) processors;

  modifier onlyProcessor {
        //make array of processors
        require(processors[msg.sender]);
        _;
    }

  function submit() public onlyProcessor{
    //do stuff here
  }
}
