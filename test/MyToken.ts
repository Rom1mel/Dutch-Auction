import { describe, it } from "node:test";
import { network } from "hardhat";
//import assert from "node:assert";
import assert from "node:assert/strict";
import { ContractFunctionExecutionError, getContract, isAddress, isAddressEqual } from "viem";
import { ConcatErrorType } from "viem";

const { viem } = await network.connect();

describe("Token Functionality", async function() {
    const [owner, user, spender] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();
    const zeroAddress = "0x0000000000000000000000000000000000000000"
    it("transfer", async function() {
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })
        const startBalance = await token.read.balanceOf([owner.account.address])
        let supply = await token.read.totalSupply()
        assert.equal(supply, 10000n)
        assert.equal(startBalance, 10000n)
        assert.equal(await token.read.balanceOf([spender.account.address]), 0n)

        await token.write.transfer([user.account.address, 100n])
        const newUserBalance = await token.read.balanceOf([user.account.address])
        const newOwnerBalance = await token.read.balanceOf([owner.account.address])
        supply = await token.read.totalSupply()
        const [transferEvent] = await publicClient.getContractEvents({
            abi: token.abi,
            address: token.address,
            fromBlock: await publicClient.getBlockNumber(),
            toBlock: await publicClient.getBlockNumber()
        })
        assert.equal(transferEvent.eventName, "Transfer")
        assert.ok(isAddressEqual(transferEvent.args.from!, owner.account.address))
        assert.ok(isAddressEqual(transferEvent.args.to!, user.account.address))
        assert.equal(transferEvent.args.value,100n)
        assert.equal(newUserBalance, 100n)
        assert.equal(supply, 10000n)
        assert.equal(newOwnerBalance, 10000n-100n)
    })
    it("illegal transfer", async function(){
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })
        
        try{
            await token.write.transfer([user.account.address,1000000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("luckOfFunds(10000, 1000000)"))
            }
            else{
                assert.ok(false)
            }
        }
        
        try{
            await token.write.transfer([zeroAddress,1000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("addressCantBeZero()"))
            }
            else{
                assert.ok(false)
            }
        }
    })
    it("approve and transferFrom", async function(){
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })

        await token.write.approve([spender.account.address, 5000n])
        assert.equal(await token.read.allowance([owner.account.address, spender.account.address]), 5000n)
        await spender.writeContract({
            address: token.address,
            abi: token.abi,
            functionName:'transferFrom',
            args:[owner.account.address, user.account.address, 1000n]
        })
        assert.equal(await token.read.allowance([owner.account.address, spender.account.address]), 4000n)
        assert.equal(await token.read.balanceOf([owner.account.address]), 9000n)
        assert.equal(await token.read.balanceOf([user.account.address]), 1000n)
        assert.equal(await token.read.totalSupply(), 10000n)

        await token.write.approve([spender.account.address, 1000n])
        assert.equal(await token.read.allowance([owner.account.address, spender.account.address]), 1000n)

        await token.write.approve([spender.account.address, (2n ** 256n) - 1n])
        await spender.writeContract({
            address: token.address,
            abi: token.abi,
            functionName:'transferFrom',
            args:[owner.account.address, spender.account.address, 2000n]
        })
        assert.equal(await token.read.allowance([owner.account.address, spender.account.address]), (2n ** 256n) - 1n)
        assert.equal(await token.read.balanceOf([owner.account.address]), 7000n)
        assert.equal(await token.read.balanceOf([spender.account.address]), 2000n)
        assert.equal(await token.read.totalSupply(), 10000n)
    })
    it("illegal transfer from and approve", async function(){
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })
        const tokenSpend = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: spender}
        })
        try{
            await tokenSpend.write.transferFrom([owner.account.address, user.account.address, 1000n])
        } catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("ownerDontApproveThisAmount(1000, 0)"))
            }
            else{
                assert.ok(false)
            }
        }

        await token.write.approve([spender.account.address, 1000n])
        try{
            await tokenSpend.write.transferFrom([owner.account.address, user.account.address, 1200n])
        } catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("ownerDontApproveThisAmount(1200, 1000)"))
            }
            else{
                assert.ok(false)
            }

        }try{
            await token.write.approve([zeroAddress, 1000n])
        } catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("addressCantBeZero()"))
            }
            else{
                assert.ok(false)
            }
        }
    })
    it("burn and mint", async function(){
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })

        await token.write.mint([user.account.address, 1000n])
        assert.equal(await token.read.totalSupply(), 11000n)
        assert.equal(await token.read.balanceOf([user.account.address]), 1000n)
        
        await token.write.burn([5000n])
        assert.equal(await token.read.totalSupply(), 6000n)
        assert.equal(await token.read.balanceOf([owner.account.address]), 5000n)
    })
    it("illegal burn and mint", async function(){
        const tokenDeploy = await viem.deployContract("EducationToken", ["education", "EDU"]);
        const token = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: owner}
        })
        const tokenForUsersAction = await getContract({
            address: tokenDeploy.address,
            abi: tokenDeploy.abi,
            client: {public: publicClient, wallet: user}
        })
        try{
            await tokenForUsersAction.write.mint([user.account.address, 1000000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("onlyForOwner"))
            }
            else{
                assert.equal(err,0)
            }
        }
        try{
            await tokenForUsersAction.write.burn([1000000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("onlyForOwner"))
            }
            else{
                assert.equal(err,0)
            }
        }
        try{
            await token.write.burn([10000000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("luckOfFunds(10000, 10000000)"))
            }
            else{
                assert.equal(err,0)
            }
        }
        try{
            await token.write.mint([zeroAddress, 10000000n])
        }
        catch(err){
            if(err instanceof ContractFunctionExecutionError){
                assert.ok(err.cause.details.includes("addressCantBeZero()"))
            }
            else{
                assert.equal(err,0)
            }
        }
    })
})