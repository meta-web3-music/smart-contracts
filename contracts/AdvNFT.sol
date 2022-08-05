pragma solidity 0.8.13;
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

// TODO: tokenMetadataURI, tokenURI
// TODO: add token uri func and append ipfs://
contract AdvNFT is Context, ERC721Burnable, ERC721Pausable {
    using Counters for Counters.Counter;
    address public nftContractAddr;
    Counters.Counter private _tokenIdTracker;

    // MusicTokenId to AdvNftId
    mapping(uint256 => uint256) private _musicIdToAdvId;

    mapping(uint256 => AdvNft) private _advIdToAdv;

    function setNftContractAddr(address _nftContractAddr) external {
        require(
            nftContractAddr == address(0),
            "address is already initialized"
        );
        nftContractAddr = _nftContractAddr;
    }

    struct AdvNft {
        string metaDataUri;
        uint32 expirationDuration;
        uint256 expirationTime;
        address creator;
    }
    address public admin;
    address public marketplaceAddress;
    event AdvNFTCreated(
        uint256 tokenID,
        address indexed creator,
        string metaDataUri
    );

    using Strings for uint256;

    constructor(
        string memory name,
        string memory symbol,
        address _marketplaceAddress
    ) ERC721(name, symbol) {
        marketplaceAddress = _marketplaceAddress;
        admin = _msgSender();
    }

    modifier slotEmpty(uint256 musicTokenId) {
        require(
            IERC721(nftContractAddr).ownerOf(musicTokenId) == _msgSender(),
            "sender is not owner of the music"
        );
        _;
    }

    modifier onlyAdmin() {
        require(admin == _msgSender(), "sender is not admin");
        _;
    }

    modifier onlyOwner(uint256 tokenId) {
        require(
            ownerOf(tokenId) == _msgSender(),
            "sender is not owner of token"
        );
        _;
    }

    modifier onlyMusicNFTOwner(address owner, uint256 musicTokenId) {
        require(
            IERC721(nftContractAddr).ownerOf(musicTokenId) == owner,
            "sender is not owner of the music"
        );
        _;
    }

    modifier onlyNftAddrExist() {
        require(
            nftContractAddr != address(0),
            "please initialize nft contract address"
        );
        _;
    }

    // Only music NFT address can be sender
    modifier onlyMusicNFT() {
        require(
            _msgSender() == nftContractAddr,
            "sender is not Music NFT contract"
        );
        _;
    }

    modifier onlyExpired(uint256 musicTokenId) {
        uint256 advNftId = _musicIdToAdvId[musicTokenId];
        AdvNft memory advNft = _advIdToAdv[advNftId];
        require(
            // expiration duration is 0 only when the mapping is null since we don't allow duration 0
            advNft.expirationDuration == 0 ||
                (advNft.expirationTime != 0 &&
                    block.timestamp > advNft.expirationTime),
            "Adspace is not expired yet"
        );
        _;
    }

    function createAdSpace(
        uint256 musicNFTId,
        string memory metadataHash,
        uint32 expirationDuration
    ) public returns (uint256) {
        return
            _createAdSpace(
                _msgSender(),
                musicNFTId,
                metadataHash,
                expirationDuration
            );
    }

    function _musicNFTCreateAdSpace(
        address owner,
        uint256 musicNFTId,
        string memory metadataHash,
        uint32 expirationDuration
    ) public onlyMusicNFT returns (uint256) {
        return
            _createAdSpace(owner, musicNFTId, metadataHash, expirationDuration);
    }

    function _createAdSpace(
        address owner,
        uint256 musicNFTId,
        string memory metadataHash,
        uint32 _expirationDuration
    )
        internal
        onlyMusicNFTOwner(owner, musicNFTId)
        onlyExpired(musicNFTId)
        onlyNftAddrExist
        returns (uint256)
    {
        require(
            _expirationDuration <= 2592000,
            "adspace for more than 30 days is not allowed"
        );

        require(
            _expirationDuration >= 259200,
            "adspace for less than 3 days is not allowed"
        );

        _tokenIdTracker.increment();
        uint256 currentTokenID = _tokenIdTracker.current();
        _safeMint(owner, currentTokenID);

        _musicIdToAdvId[musicNFTId] = currentTokenID;

        _advIdToAdv[currentTokenID].metaDataUri = metadataHash;
        _advIdToAdv[currentTokenID].creator = owner;
        _advIdToAdv[currentTokenID].expirationDuration = _expirationDuration;

        _setApprovalForAll(owner, marketplaceAddress, true);

        emit AdvNFTCreated(currentTokenID, owner, tokenURI(currentTokenID));
        return currentTokenID;
    }

    function getCurrentAdvMetaDataUri(uint256 musicNFTId)
        external
        view
        returns (string memory)
    {
        uint256 advNFTid = _musicIdToAdvId[musicNFTId];
        AdvNft memory advNFT = _advIdToAdv[advNFTid];
        require(block.timestamp <= advNFT.expirationTime, "AdvNFT has expired");
        return advNFT.metaDataUri;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Non-Existent NFT");
        string memory _tokenURI = _advIdToAdv[tokenId].metaDataUri;

        return _tokenURI;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function updateMetaDatUri(uint256 tokenId, string memory _metaDataUri)
        external
    {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "sender is not approved nor owner of token"
        );
        _advIdToAdv[tokenId].metaDataUri = _metaDataUri;
    }

    //Some checks to avoid token being transfer to other marketplace where it is not possible to detect sale and therefore not possible to initilize expirationTime
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Pausable) {
        // If minted then go through normal flow and return
        if (from == address(0)) {
            super._beforeTokenTransfer(from, to, tokenId);
            return;
        }
        AdvNft memory advNft = _advIdToAdv[tokenId];
        // Expire the token if it is being burn
        if (to == address(0)) {
            if (advNft.expirationTime > block.timestamp) {
                _advIdToAdv[tokenId].expirationTime = 0;
            }
            super._beforeTokenTransfer(from, to, tokenId);
            return;
        }

        // If token has expirationTime already initlized then it is used and cannot transfer to any other address, instead can be approved to other address if needed
        require(advNft.expirationTime == 0, "cannot transfer used Adspace");

        // Check if the token is being placed at marketplace or it is being sold to another account
        require(
            to == marketplaceAddress || from == marketplaceAddress,
            "token can be transferred only from or to marketplace"
        );

        // Set expiration time when there is market sale
        if (from == marketplaceAddress && to != advNft.creator) {
            _advIdToAdv[tokenId].expirationTime =
                block.timestamp +
                advNft.expirationDuration;
        }

        super._beforeTokenTransfer(from, to, tokenId);
    }
}
