import { network } from "hardhat";

class NetworkSnapshotter {
  snapshotId: number;
  constructor() {
    this.snapshotId = 0;
  }

  async revert() {
    await network.provider.send("evm_revert", [this.snapshotId]);
    this.snapshot();
  }

  async snapshot() {
    this.snapshotId = await network.provider.send("evm_snapshot", []);
  }
}

export default NetworkSnapshotter;
