import { ethers } from "hardhat";
import { escrowNativeSetup, escrowTokenSetup } from "../../test/helpers/setup";
import fs from "fs";

async function main() {
    const [devAccount, defaultDeployer] = await ethers.getSigners();

    const network = await ethers.provider.getNetwork();

    console.log("Network: ", network.name);
    console.log("Deployer address: ", await defaultDeployer.getAddress());

    const addressesData = fs.readFileSync(
        "./deployments/avax/" + network.name + "/addresses.json",
        "utf8"
    );

    const parsedAddressesData = JSON.parse(addressesData);

    const escrowNativeImplementation = await escrowNativeSetup(
        defaultDeployer,
        false
    );
    const escrowTokenImplementation = await escrowTokenSetup(
        defaultDeployer,
        false
    );

    parsedAddressesData.escrows = {
        escrowNative: escrowNativeImplementation.target,
        escrowToken: escrowTokenImplementation.target,
    };

    fs.writeFileSync(
        "./deployments/avax/" + network.name + "/addresses.json",
        JSON.stringify(parsedAddressesData)
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
