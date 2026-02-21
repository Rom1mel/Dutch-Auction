import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { ContractFunctionExecutionError, encodeFunctionData, getContract, isAddressEqual, parseEther, RpcError, zeroAddress} from "viem";
import { BaseError} from 'viem';
import hre from "hardhat";

const { networkHelpers } = await hre.network.connect()
const { viem } = await network.connect();
const MAX_UINT256 = 2n ** 256n - 1n;

async function simpleDeployment(){  //deployment and creation of contract instances.
    const publicClient = await viem.getPublicClient()
    const [owner, user, buyer] = await viem.getWalletClients()
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
    address: deployToken.address,
    abi: deployToken.abi,
    client: { public: publicClient, wallet: owner }
    });
    const tokenForUser = await getContract({
    address: deployToken.address,
    abi: deployToken.abi,
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
        client: { public: publicClient, wallet: user}
    })
    return { publicClient, owner, user, buyer, admin ,auctionForOwner,
    auctionForUser, tokenForOwner, tokenForUser, nftForOwner, nftForUser } //created instances of contracts and accounts.
}

async function deploymentWithBalances(){ // Deploys contracts and adds the user balances.
    const { publicClient, owner, user, buyer, admin ,auctionForOwner,
    auctionForUser, tokenForOwner, tokenForUser, nftForOwner, nftForUser } = await simpleDeployment()
    const auctionForBuyer = await getContract({
        address: auctionForOwner.address,
        abi: auctionForOwner.abi,
        client: {public: publicClient, wallet: buyer}
    })
    const tokenForBuyer = await getContract({
        address: tokenForOwner.address,
        abi: tokenForOwner.abi,
        client: {public: publicClient, wallet: buyer}
    })
    const nftForBuyer = await getContract({
        address: nftForOwner.address,
        abi: nftForOwner.abi,
        client: {public: publicClient, wallet: buyer}
    })
    await tokenForOwner.write.mint([user.account.address, 10000n])
    await tokenForOwner.write.mint([buyer.account.address, 10000n])
    await nftForOwner.write.safeMint([11n])
    await nftForOwner.write.safeTransferFrom([owner.account.address, user.account.address, 11n])
    return { publicClient, owner, user, buyer, admin ,auctionForOwner,
    auctionForUser, auctionForBuyer, tokenForOwner, tokenForUser,
    tokenForBuyer, nftForOwner, nftForUser, nftForBuyer }
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
        const {auctionForOwner} = await simpleDeployment()
        await auctionForOwner.write.setFee([5000n])
        await auctionForOwner.write.setAddingFee([6000n])
        assert.equal(await auctionForOwner.read.getFee(), 5000n,);
        assert.equal(await auctionForOwner.read.getAddingFee(), 6000n,);
      })
      it('Not Owner Cant Set Fee And AddingFee', async function(){ //Checking that the user can't change the fees.
        const {auctionForUser, tokenForOwner} = await networkHelpers.loadFixture(simpleDeployment)
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
        assert.ok(errorCause.includes('YouAreNotOwner()'));
      })
})
describe("adding and after adding lot", async function(){
    it("correct adding lot", async function(){ //You can add a lot with acceptable parameters.
        const { publicClient, user, auctionForOwner, auctionForUser, tokenForUser, tokenForOwner,
        nftForOwner, nftForUser} = await networkHelpers.loadFixture(deploymentWithBalances)
        await tokenForUser.write.approve([auctionForOwner.address, 5000n])
        await nftForUser.write.approve([auctionForOwner.address, 11n])
        const lotId = await auctionForUser.write.addLot([11n, 9000n, 2n, 1n, 3600n])
        //Checking the change in token balance.
        assert.equal(await tokenForOwner.read.balanceOf([auctionForOwner.address]), 100n)
        assert.equal(await tokenForOwner.read.balanceOf([user.account.address]), 9900n)
        assert.ok(isAddressEqual(await nftForOwner.read.ownerOf([11n]), auctionForOwner.address))
		const lot = await auctionForUser.read.getLot([0n])
		const block = await publicClient.getBlock()
		//Сhecking lot parameters
		assert.equal(lot.beginPrice, 9000n)
		assert.equal(lot.discount, 2n)
		assert.equal(lot.periodOfDiscount, 1n)
		assert.equal(lot.timeToEnd, 3600n)
		assert.equal(lot.beginPrice, 9000n)
		assert.equal(lot.finalPrice, 0n)
		assert.equal(lot.timeStemp, block.timestamp)
		assert.ok(isAddressEqual(lot.lotOwner, user.account.address))
		assert.ok(isAddressEqual(lot.buyer, zeroAddress))
		// Checking lot status
		assert.equal( await auctionForOwner.read.getLotStatus([0n]), 'The lot is put up for sale.')
		//Event emission check
		const [event] = await publicClient.getContractEvents({
  		address: auctionForOwner.address,
  		abi: auctionForOwner.abi,
  		eventName: 'LotAdded',
  		fromBlock: 'latest', 
  		toBlock: 'latest'
		});
		assert.equal(event.args.lotId, 0n)
		assert.equal(event.args.beginPrice, 9000n)
		assert.equal(event.args.timeStemp, block.timestamp)
		assert.ok(isAddressEqual(event.args.lotOwner as `0x${string}`, user.account.address))
	})
	it("correct price", async function(){  // Checking that the price decreases over time.
		const {admin, auctionForOwner } = await networkHelpers.loadFixture(deploymentWithBalances)
		await admin.mine({blocks: 7, interval: 1})
        const oldPrise = await auctionForOwner.read.getPrice([0n])
        await admin.mine({blocks: 1, interval: 1})
        assert.equal(oldPrise - await auctionForOwner.read.getPrice([0n]), 2n)
	})
	it("illegal lots", async function(){ //Checking scenarios where a user cannot add a lot.
		const {auctionForUser, auctionForBuyer, nftForUser, tokenForUser} = await deploymentWithBalances()
		let errorCause = ''
		try{
			await auctionForBuyer.write.addLot([11n, 9000n, 2n, 1n, 3600n])
		} catch(err){  //You cannot list an NFT that is not yours for sale.
			if(err instanceof BaseError){
				errorCause = err.details
				assert.ok(errorCause.includes("YouDontHaveThisNFT(11)"))
				if(!errorCause.includes("YouDontHaveThisNFT(11)")){
					console.log(errorCause)
				}
			}
		}

		errorCause = ''
		try{
			await auctionForUser.write.addLot([11n, 9000n, 2n, 1n, 3600n])
		}
		 catch(err){ //The user has not approved any of the tokens, since the NFT approval check is performed first, a corresponding error will occur.
			if(err instanceof BaseError){
				errorCause = err.details
				if(!errorCause.includes("NotApproved(11)")){
					console.log(errorCause)
				}
				assert.ok(errorCause.includes('NotApproved(11)'));
			}
		}

		errorCause = ''
		try{
			await nftForUser.write.approve([auctionForUser.address, 11n])
			await auctionForUser.write.addLot([11n, 9000n, 2000n, 1n, 3600n])
		}
		 catch(err){ //The tokens required to pay the commission fee have not been approved.
			if(err instanceof BaseError){
				errorCause = err.details
				if(!errorCause.includes("NotApproved(100)")){
					console.log(errorCause)
				}
				assert.ok(errorCause.includes('NotApproved(100)'));
			}
		}

		errorCause = ''
		try{
			await nftForUser.write.approve([auctionForUser.address, 11n])
			await tokenForUser.write.approve([auctionForUser.address, 1000n])
			await auctionForUser.write.addLot([11n, 9000n, 2000n, 1n, 3600n])
		}
		 catch(err){ //The price should not go into the negative by the end of the lot due to too large of a decrease.
			if(err instanceof BaseError){
				errorCause = err.details
				if(!errorCause.includes("RezultDiscountMoreThenBefinPrice()")){
					console.log(errorCause)
				}
				assert.ok(errorCause.includes('RezultDiscountMoreThenBefinPrice()'));
			}
		}

		errorCause = ''
		try{
			await nftForUser.write.approve([auctionForUser.address, 11n])
			await tokenForUser.write.approve([auctionForUser.address, 1000n])
			await auctionForUser.write.addLot([11n, 0n, 2n, 1n, 3600n])
		}
		 catch(err){ //You cannot sell an NFT for free.
			if(err instanceof BaseError){
				errorCause = err.details
				if(!errorCause.includes("PriceCantBeZero()")){
					console.log(errorCause)
				}
				assert.ok(errorCause.includes('PriceCantBeZero()'));
			}
		}

		errorCause = ''
		try{
			await nftForUser.write.approve([auctionForUser.address, 11n])
			await tokenForUser.write.approve([auctionForUser.address, 1000n])
			await auctionForUser.write.addLot([11n, MAX_UINT256, 2000n, 1n, 3600n])
		}
		 catch(err){ //The price must not be equal to the maximum uint256 value, as this value is used for technical purposes.
			if(err instanceof BaseError){
				errorCause = err.details
				if(!errorCause.includes("PriceCantBeUint256Max()")){
					console.log(errorCause)
				}
				assert.ok(errorCause.includes('PriceCantBeUint256Max()'));
			}
		}
	})
	it("The user can buy a lot", async function(){
		const {auctionForBuyer, buyer, tokenForBuyer, user, publicClient} = await networkHelpers.loadFixture(deploymentWithBalances)
		const oldUserBalance = await tokenForBuyer.read.balanceOf([user.account.address])
		const oldBuyerBalance = await tokenForBuyer.read.balanceOf([buyer.account.address])
		await tokenForBuyer.write.approve([auctionForBuyer.address, 10000n])
		await auctionForBuyer.write.buyLot([0n])
		const price = await auctionForBuyer.read.getPrice([0n])
		// The lot is valid
		const lot = await auctionForBuyer.read.getLot([0n])
		assert.ok(isAddressEqual(lot.buyer, buyer.account.address))
		assert.equal(lot.finalPrice, price)
		// The balances is valid
		assert.equal(await tokenForBuyer.read.balanceOf([auctionForBuyer.address]), 1100n)
		assert.equal(await tokenForBuyer.read.balanceOf([user.account.address]) - oldUserBalance, price)
		assert.equal(oldBuyerBalance - await tokenForBuyer.read.balanceOf([buyer.account.address]), price + 1000n)
		// The buy event is valid
		const [event] = await publicClient.getContractEvents({
			address: auctionForBuyer.address,
			abi: auctionForBuyer.abi,
			eventName: 'LotBought',
			toBlock: 'latest',
			fromBlock: 'latest'
		})
		const blockTimeStemp = (await publicClient.getBlock()).timestamp
		assert.equal(event.args.lotId, 0n)
		assert.equal(event.args.finalPrice, price)
		assert.equal(event.args.timeStemp, blockTimeStemp)
		assert.ok(isAddressEqual(event.args.buyer as `0x${string}`, buyer.account.address))
	})
})