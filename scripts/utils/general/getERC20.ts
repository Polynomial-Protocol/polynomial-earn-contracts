import { BigNumber, Contract, Signer } from "ethers";
import hre from "hardhat";
import { ERC20__factory } from "../../../typechain";

const { ethers, network } = hre;

export async function getERC20(address: string, signer: Signer) : Promise<Contract> {
    const erc20 = new ethers.Contract(address, ERC20__factory.abi, signer);

    return erc20;
}