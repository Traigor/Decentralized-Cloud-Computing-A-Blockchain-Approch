import { AuctionsManager } from "../AuctionsManager";
import {
  address as AUCTIONS_MANAGER_ADDRESS,
  abi as AUCTIONS_MANAGER_ABI,
} from "../../../deployments/localhost/AuctionsManager.json";
import { address as TASKS_MANAGER_ADDRESS } from "../../../deployments/localhost/TasksManager.json";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("cancel auction on AuctionsManager on localhost hardhat network", () => {
  let auctionsManager: AuctionsManager;
  let auctionDeadline: number;
  let taskDeadline: number;
  let clientVerification: string;
  let code: string;
  let clientAddress: string;
  let providerAddress: string;
  let auctionID: string;

  //hardhat network
  const provider = new ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  const signerAsClient = provider.getSigner(0);
  const signerAsProvider = provider.getSigner(1);

  beforeEach(async () => {
    auctionDeadline = 100;
    taskDeadline = 200;
    clientVerification =
      "0xf2350a27c0f701987ca97fd3f4d930ee0ab2c93fcf107f356f26f9f83fc6f4da";
    code = "code";
    clientAddress = await signerAsClient.getAddress();
    auctionsManager = new AuctionsManager(
      AUCTIONS_MANAGER_ADDRESS,
      AUCTIONS_MANAGER_ABI,
      signerAsClient
    );
    await auctionsManager.setTasksManager(TASKS_MANAGER_ADDRESS);
    auctionsManager.connect(signerAsClient);
  });

  it("should cancel auction successfully", async () => {
    const createdAuction = await auctionsManager.createAuction({
      auctionDeadline,
      taskDeadline,
      clientVerification,
      code,
    });
    auctionID = createdAuction.event.auctionID;

    auctionsManager.connect(signerAsProvider);
    const activeAuctionsInitial = await auctionsManager.getActiveAuctions();

    auctionsManager.connect(signerAsClient);
    const cancelledAuction = await auctionsManager.cancelAuction(auctionID);
    const event = cancelledAuction.event;

    auctionsManager.connect(signerAsProvider);
    const activeAuctionsFinal = await auctionsManager.getActiveAuctions();

    expect(event.name).to.equal("AuctionCancelled");
    expect(event.client).to.equal(clientAddress);
    expect(activeAuctionsFinal.length).to.equal(
      activeAuctionsInitial.length - 1
    );
  });

  it.only("should fail to cancel auction if auction does not exist", async () => {
    const auctionID = ethers.utils.formatBytes32String("0x1234");
    auctionsManager.connect(signerAsProvider);
    await expect(
      await auctionsManager.cancelAuction(auctionID)
    ).to.be.revertedWith("AuctionDoesNotExist");
    //create domain error and test with to.throw
  });
});
