import { outRef } from "./ledger.ts";
import type { setupLocalExample } from "./setup.ts";

export async function firstDepositInput(f: Awaited<ReturnType<typeof setupLocalExample>>) {
  const funding = (await f.ledger.provider.getUtxos(f.ledger.address)).filter(
    (u) =>
      !u.datum &&
      !u.scriptRef &&
      u.txHash !== f.collateral.txHash &&
      u.txHash !== f.prepared.vault.input.poolBinding.positionSeed.txId,
  );

  return {
    prepared: f.prepared,
    provider: f.ledger.provider,
    fundingAddress: f.ledger.address,
    funding,
    collateral: [f.collateral],
    protectedInputs: [],
    configRef: outRef(f.config),
    certificateRef: outRef(f.certificate),
    controllerReference: outRef(f.controller),
    stakingReference: outRef(f.staking),
    amount: 10_000_000n,
    lowerBoundMs: f.time + 60000n,
    reserveBuffer: 1_000_000n,
    maxNetworkFee: 3_000_000n,
    maxCollateralExposure: 5_000_000n,
  };
}
