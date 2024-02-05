// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import {DolaSavings} from "src/DolaSavings.sol";
import {sDola} from "src/sDola.sol";
import {sDolaHelper} from "src/sDolaHelper.sol";

contract MainnetFullDeployScript is Script {

    function run() public {

        address dbr = 0xAD038Eb671c44b853887A7E32528FaB35dC5D710;
        address dola = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
        address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
        address operator = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
        address savings = 0xE5f24791E273Cb96A1f8E5B67Bc2397F0AD9B8B4;
        uint K = 325*10**42;

        vm.startBroadcast();

        sDola sdola = new sDola(
            dola,
            address(savings),
            gov,
            address(0),
            K
        
        );

        sDolaHelper helper = new sDolaHelper(
            address(sdola)
        );
    }
}
