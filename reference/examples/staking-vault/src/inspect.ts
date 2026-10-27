import { historicalProfile, publicJson } from "./profile.ts";

const profile = historicalProfile();

console.log(
  publicJson({
    historicalOnly: true,
    factoryPolicy: profile.factory.factoryPolicy,
    buildId: profile.factory.buildId,
    factoryReferences: profile.factory.stages,
    vault: profile.vault.controller,
    vaultAddress: profile.vault.vaultAddress,
    pool: profile.pool.poolPolicyId,
    poolAddress: profile.pool.poolAddress,
    principal: profile.prepared.pool.settings.stakingAsset,
    reward: profile.prepared.pool.settings.rewardAsset,
    liveIdentityVerified: false,
    networkVerified: false,
    deploymentReady: false,
  }),
);
