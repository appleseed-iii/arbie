// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    FlashLoanReceiverBase
} from "@aave/contracts/flashloan/base/FlashLoanReceiverBase.sol";
import {
    ILendingPoolAddressesProvider
} from "@aave/contracts/interfaces/ILendingPoolAddressesProvider.sol";

interface IERC20 {
    function approve(address _spender, uint256 _amount) external;

    function allowance(address _owner, address _spender)
        external
        returns (uint256);

    function balanceOf(address _account) external returns (uint256);

    function transfer(address _to, uint256 _amount) external;

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external;
}

interface TriCryptoSwap {
    function exchange(
        uint256 _i,
        uint256 _j,
        uint256 _dx,
        uint256 _min_dy
    ) external;
}

contract ArbieV3 is FlashLoanReceiverBase, Ownable {
    bytes4 constant CURVE_FN_SELECTOR = 0xe22c63c0;
    bytes4 constant PARASWAP_FN_SELECTOR = 0xe83ec731;
    address constant TOKEN_TRANSFER_PROxY_ADDR =
        0xb70Bc06D2c9Bf03b3373799606dc7d39346c06B3;
    address constant PARASWAP_ADDR = 0x1bD435F3C054b6e901B7b108a0ab7617C808677b;

    TriCryptoSwap constant CRYPTO_SWAP =
        TriCryptoSwap(0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5);

    ILendingPoolAddressesProvider constant LENDING_POOL_ADDRESS_PROVIDER =
        ILendingPoolAddressesProvider(
            0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5
        );

    address private inputAsset;
    uint256 private amountToReturn;

    constructor() public FlashLoanReceiverBase(LENDING_POOL_ADDRESS_PROVIDER) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(initiator == Ownable.owner());

        // Set approvals
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = amounts[i];
            uint256 premium = premiums[i];

            if (i == 0) {
                inputAsset = asset;
                amountToReturn = amount.add(premium);
            }

            uint256 allowance =
                IERC20(asset).allowance(address(this), address(CRYPTO_SWAP));

            if (allowance == 0) {
                IERC20(asset).approve(address(CRYPTO_SWAP), uint256(-1));
                IERC20(asset).approve(TOKEN_TRANSFER_PROxY_ADDR, uint256(-1));
                IERC20(asset).approve(address(LENDING_POOL), uint256(-1));
            }
        }

        (
            bytes4 fnSig,
            uint256 _i,
            uint256 _j,
            uint256 _dx,
            uint256 _min_dy,
            uint256 _deadline,
            bytes memory _paraswap_calldata
        ) =
            abi.decode(
                params,
                (bytes4, uint256, uint256, uint256, uint256, uint256, bytes)
            );

        if (fnSig == CURVE_FN_SELECTOR) {
            ArbieV3.arbitrageCurve(
                _i,
                _j,
                _dx,
                _min_dy,
                _deadline,
                _paraswap_calldata
            );
        } else if (fnSig == PARASWAP_FN_SELECTOR) {
            ArbieV3.arbitrageParaswap(
                _i,
                _j,
                _dx,
                _min_dy,
                _deadline,
                _paraswap_calldata
            );
        }

        return true;
    }

    function arbitrageCurve(
        uint256 _i,
        uint256 _j,
        uint256 _dx,
        uint256 _min_dy,
        uint256 _deadline,
        bytes memory _paraswap_calldata
    ) public {
        require(block.timestamp < _deadline);

        PARASWAP_ADDR.call(_paraswap_calldata);
        CRYPTO_SWAP.exchange(_i, _j, _dx, _min_dy);

        uint256 balance = IERC20(inputAsset).balanceOf(address(this));
        uint256 profit = balance.sub(amountToReturn);

        require(profit > 0);
        // trnasfer profit out and set storage variables to 0
        IERC20(inputAsset).transfer(Ownable.owner(), profit);
        inputAsset = address(0);
        amountToReturn = 0;
    }

    function arbitrageParaswap(
        uint256 _i,
        uint256 _j,
        uint256 _dx,
        uint256 _min_dy,
        uint256 _deadline,
        bytes memory _paraswap_calldata
    ) public {
        require(block.timestamp < _deadline);

        CRYPTO_SWAP.exchange(_i, _j, _dx, _min_dy);
        PARASWAP_ADDR.call(_paraswap_calldata);

        uint256 balance = IERC20(inputAsset).balanceOf(address(this));
        uint256 profit = balance.sub(amountToReturn);

        require(profit > 0);
        // trnasfer profit out and set storage variables to 0
        IERC20(inputAsset).transfer(Ownable.owner(), profit);
        inputAsset = address(0);
        amountToReturn = 0;
    }
}