/** Factory-admitted staking extension example; does not alter either CTVS family. */

export { resolveFactoryAdmission } from "../vendor/client/src/factory/admission.ts";
export type { FactoryCreationLedger } from "../vendor/client/src/factory/creation.ts";
export {
  constructFactoryVaultGenesis,
  constructFactoryVaultPublication,
} from "../vendor/client/src/factory/creation.ts";
export {
  factoryOperationContext,
  prepareFactoryDeployment,
} from "../vendor/client/src/factory/deployment.ts";
export type { FactoryExistingDepositLedger } from "../vendor/client/src/factory/existing-deposit.ts";
export { constructFactoryExistingDeposit } from "../vendor/client/src/factory/existing-deposit.ts";
export type { FirstDepositLedger } from "../vendor/client/src/factory/first-deposit.ts";
export { constructFactoryFirstDeposit } from "../vendor/client/src/factory/first-deposit.ts";
export type { FactoryGenesisReferences } from "../vendor/client/src/factory/genesis-builder.ts";
export type { FactoryPositionLedger } from "../vendor/client/src/factory/position-operation.ts";
export {
  constructFactoryPublication,
  prepareFactoryPublication,
} from "../vendor/client/src/factory/publication.ts";
export type { FactoryRedeemLedger } from "../vendor/client/src/factory/redeem.ts";
export { constructFactoryRedeem } from "../vendor/client/src/factory/redeem.ts";
export type { FactoryWithdrawLedger } from "../vendor/client/src/factory/withdraw.ts";
export { constructFactoryWithdraw } from "../vendor/client/src/factory/withdraw.ts";
export { readFactorySettings } from "../vendor/client/src/setup/composed-settings.ts";
export type { FactoryPoolSettings } from "../vendor/client/src/setup/factory-pool.ts";
export { importExistingFactoryPool } from "../vendor/client/src/setup/import-factory-pool.ts";
export { constructFactoryMint, type FactoryMintLedger } from "./mint.ts";
