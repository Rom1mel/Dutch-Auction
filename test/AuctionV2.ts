import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { ContractFunctionExecutionError, encodeFunctionData, getContract, isAddressEqual, parseEther, RpcError, zeroAddress} from "viem";
import { BaseError} from 'viem';
import hre from "hardhat";

const { networkHelpers } = await hre.network.connect()
const { viem } = await network.connect();

async function simpleDeployment(){  //deployment and creation of contract instances.
    const publicClient = await viem.getPublicClient()
    const [owner, user] = await viem.getWalletClients()
    const admin = await viem.getTestClient()
    const deployNFT = await viem.deployContract("NFTsLot", [owner.account?.address as `0x${string}`]) 
    const deployToken = await viem.deployContract("EducationToken",["Education", "EDU"])
    const nftForOwner = await getContract({
    address: deployNFT.address,
    abi: deployNFT.abi,
    client: { public: publicClient, wallet: owner }
    });
    const nftForUser = await getContract({
    address: deployNFT.address,
    abi: deployNFT.abi,
    client: { public: publicClient, wallet: user }
    });
    const tokenForOwner = await getContract({
    address: deployNFT.address,
    abi: deployNFT.abi,
    client: { public: publicClient, wallet: owner }
    });
    const tokenForUser = await getContract({
    address: deployNFT.address,
    abi: deployNFT.abi,
    client: { public: publicClient, wallet: user }
    });
    const deployAuction = await viem.deployContract("Auction",
    [1000n, 100n, deployToken.address, deployNFT.address] as [bigint, bigint, `0x${string}`, `0x${string}`])
    const auctionForOwner = await getContract({
        address: deployAuction.address,
        abi: deployAuction.abi,
        client: { public: publicClient, wallet: owner} 
    })
    const auctionForUser = await getContract({
        address: deployAuction.address,
        abi: deployAuction.abi,
        client: { public: publicClient, wallet: owner}
    })
    return { publicClient, owner, user, admin ,auctionForOwner, auctionForUser, tokenForOwner, tokenForUser, nftForOwner, nftForUser} //created instances of contracts and accounts.
}

describe("befor adding lot", async function(){  //Сhecking the initial state of the contract.
    it("Correct Feeses", async function () { // Сhecking the fees set by the constructor
        const {auctionForOwner } = await networkHelpers.loadFixture(simpleDeployment)
        assert.equal(await auctionForOwner.read.getFee(), 1000n)
        assert.equal(await auctionForOwner.read.getAddingFee(), 100n)
      })
      it("Correct owner", async function(){ // Сhecking the owner set by the constructor
        const {auctionForOwner, owner } = await networkHelpers.loadFixture(simpleDeployment)
        assert.ok(isAddressEqual(await auctionForOwner.read.getOwner(), owner.account.address));
      })
      it('Set Fee', async function(){  //Checking that the owner can change the fees.
        const {auctionForOwner} = await networkHelpers.loadFixture(simpleDeployment)
        await auctionForOwner.write.setFee([5000n])
        await auctionForOwner.write.setAddingFee([6000n])
        assert.equal(await auctionForOwner.read.getFee(), 5000n,);
        assert.equal(await auctionForOwner.read.getAddingFee(), 6000n,);
      })
      it('Not Owner Cant Set Fee And AddingFee', async function(){ //Checking that the user can't change the fees.
        const {auctionForUser} = await networkHelpers.loadFixture(simpleDeployment)
        let errorCause;
        try {
          await auctionForUser.write.setFee([50n])
          }
        catch (err){
          if (err instanceof BaseError){
            const revertEror = err.walk(err => err instanceof ContractFunctionExecutionError);
            if (revertEror instanceof ContractFunctionExecutionError) {
              errorCause = revertEror.details;
            }
          }
        }
        assert.ok(errorCause?.includes('YouAreNotOwner()'));
        errorCause = '';
        try{
          await auctionForUser.write.setAddingFee([40n])
        } catch (err) {
          if (err instanceof BaseError){
            errorCause = err.details;
          }
        }
        assert.ok(errorCause?.includes('YouAreNotOwner()'));
      })
})
describe("adding and after adding lot", async function(){
    const publicClient = await viem.getPublicClient()
    const [owner, user, buyer] = await viem.getWalletClients()
    const admin = await viem.getTestClient()
    const deployAuction = await viem.deployContract("Auction", [100n, 1000n])
    const auctionForOwner = await getContract({
        abi: deployAuction.abi,
        address: deployAuction.address,
        client: {public: publicClient, wallet: owner}
    })
    const auctionForUser = await getContract({
        abi: deployAuction.abi,
        address: deployAuction.address,
        client: {public: publicClient, wallet: user}
    })
    const deployToken = await viem.deployContract("EducationToken",["Education", "EDU"])
    const tokenForOwner = await getContract({
        abi: deployToken.abi,
        address: deployToken.address,
        client: {public: publicClient, wallet: owner}
    })
    const tokenForUser = await getContract({
        abi: deployToken.abi,
        address: deployToken.address,
        client: {public: publicClient, wallet: user}
    })
    const nftDeploy = await viem.deployContract("NFTsLot", [owner.account.address])
    const nftForOwner = await getContract({
        abi: nftDeploy.abi,
        address: nftDeploy.address,
        client: {public: publicClient, wallet: owner}
    })
    const nftForUser = await getContract({
        abi: nftDeploy.abi,
        address: nftDeploy.address,
        client: {public: publicClient, wallet: user}
    })
    await auctionForOwner.write.setTokensAddress([tokenForOwner.address, nftForOwner.address])
    await tokenForOwner.write.mint([user.account.address, 10000n])
    await tokenForOwner.write.mint([buyer.account.address, 10000n])
    await nftForUser.write.safeMint([21n])


    // СОЗДАЕМ СНЕПШОТ - создаётся, но не запускается
    const snapshotDeploy = await networkHelpers.takeSnapshot()
    it("adding lot", async function(){
        await tokenForUser.write.approve([auctionForOwner.address, 5000n])
        await nftForUser.write.approve([auctionForOwner.address, 21n])
        await auctionForUser.write.addLot([21n, 9000n, 2n, 1n, 3600n])
        const lot = await auctionForOwner.read.getLot([0n])
        assert.equal(await tokenForOwner.read.balanceOf([auctionForOwner.address]), 1000n)
        assert.equal(await tokenForOwner.read.balanceOf([user.account.address]), 9000n)
        assert.ok(isAddressEqual(await nftForOwner.read.ownerOf([21n]), auctionForOwner.address))

        await admin.mine({blocks: 7, interval: 1})
        const oldPrise = await auctionForOwner.read.getCurrentPrice([0n])
        await admin.mine({blocks: 1, interval: 1})
        assert.equal(oldPrise - await auctionForOwner.read.getCurrentPrice([0n]), 2n)
    })
    //const snapshotWithLot = await networkHelpers.takeSnapshot()
    it("purches of the lot", async function(){
        await buyer.writeContract({
            abi: tokenForOwner.abi,
            address: tokenForOwner.address,
            functionName: "approve",
            args: [auctionForOwner.address, 9990n]
        })
        await buyer.writeContract({
            abi: auctionForOwner.abi,
            address: auctionForOwner.address,
            functionName: "buyLot",
            args: [0n]
        })
        const lot = await auctionForOwner.read.getLot([0n])
        assert.ok(isAddressEqual(lot.buyer, buyer.account.address))
        assert.equal(await tokenForOwner.read.balanceOf([auctionForOwner.address]), 1100n)
        assert.equal(await tokenForOwner.read.balanceOf([user.account.address]), 9000n + lot.finalPrice)
        assert.equal(await tokenForOwner.read.balanceOf([buyer.account.address]), 9900n - lot.finalPrice)
        assert.ok(isAddressEqual(await nftForOwner.read.ownerOf([21n]), buyer.account.address))
    })
    it("wisdrow", async function(){
        await auctionForOwner.write.wisdrow([150n])
        assert.equal(await tokenForOwner.read.balanceOf([auctionForOwner.address]), 950n)
        assert.equal(await tokenForOwner.read.balanceOf([owner.account.address]), 10150n)
        
        await auctionForOwner.write.wisdrowAll()
        assert.equal(await tokenForOwner.read.balanceOf([auctionForOwner.address]), 0n)
        assert.equal(await tokenForOwner.read.balanceOf([owner.account.address]), 11100n)
    })
    it("illegal lot", async function(){   
        // Восстанавливаем - не работает
        await snapshotDeploy.restore()

        try{
            await auctionForUser.write.addLot([22n, 9000n, 2n, 1n, 3600n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                console.log(err.details)
                assert.ok(err.details.includes("ERC721NonexistentToken(22)"))
            }
            else{ assert.equal(err, 1)}
        }

        await nftForOwner.write.safeMint([22n])
        try{
            await auctionForUser.write.addLot([22n, 9000n, 2n, 1n, 3600n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                console.log(err.details)
                assert.ok(err.details.includes("YouDontHaveThisNFT(22)"))
            }
            else{ assert.equal(err, 1)}
        }

        await nftForUser.write.safeMint([23n])
        await nftForUser.write.approve([auctionForOwner.address, 23n])
        try{
            await auctionForUser.write.addLot([23n, 9000n, 1000n, 1n, 3600n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                console.log(err.details)
                assert.ok(err.details.includes("RezultDiscountMoreThenBefinPrice()"))
            }
            else{ assert.equal(err, 1)}
        }

        await tokenForUser.write.approve([auctionForUser.address, 0n])
        try{
            await auctionForUser.write.addLot([23n, 9000n, 2n, 1n, 3600n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                console.log(err.details)
                assert.ok(err.details.includes("NotApproved()"))
            }
            else{ assert.equal(err, 1)}
        }

        await tokenForUser.write.approve([auctionForUser.address, 10000n])
        await nftForUser.write.approve([zeroAddress, 23n])

        try{
            await auctionForUser.write.addLot([23n, 9000n, 2n, 1n, 3600n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                console.log(err.details)
                assert.ok(err.details.includes("NotApproved()"))
            }
            else{ assert.equal(err, 1)}
        }

    })
    
})