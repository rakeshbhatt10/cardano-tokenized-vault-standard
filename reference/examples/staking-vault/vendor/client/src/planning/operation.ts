import { decodeAuthorization, stakingAction, } from "../../protocol/shared-v1/authorization.ts";
import { stakingAuthorization } from "../staking/authorization.ts";
import { decodeVaultPosition, encodeVaultPosition, openPosition, } from "../staking/position.ts";
import { protocolRef, protocolValue } from "@ctvs/cardano";
import { createPlan, ownAsset, value, type ProtectedInput, type SyncDeployment, } from "@ctvs/planning";
import { addressData, assetId, decodeData, directRedeemer, encodeData, enterprise, hex, mintRedeemer, NAMES, quantity, refId, stateData, stateFromData, termsHash, transition, type Destination, type Operation, } from "@ctvs/protocol";
import { CML, Constr, Data, fromHex, credentialToAddress, withCMLScope, type UTxO, } from "@lucid-evolution/lucid";
import { decodePoolDatum, encodePoolDatum, type PositionState, } from "../staking/datum.ts";
import { checkpointPool, checkpointPosition } from "../staking/rewards.ts";
import type { PoolBinding, VaultSetup } from "../setup/vault.ts";
import { validateComposedPlan, type ComposedPlan } from "./model.ts";
/** Economic context shared by explicit-authority and factory-genesis controllers. */
export interface ComposedVault {
    implementation: "staking-v2";
    settings: Pick<VaultSetup, "network" | "terms" | "chainPoint">;
    binding: PoolBinding;
    policy: string;
    termsHash: string;
    buildId: string;
    genesisPlan: {
        implementation: {
            configLock: string;
        };
    };
}
export interface ComposedOperation {
    vault: ComposedVault;
    deployment: SyncDeployment;
    stateInput: ProtectedInput;
    poolInput: UTxO;
    positionInput?: UTxO;
    creationInput?: UTxO;
    operation: Operation;
    amount: bigint;
    bound: bigint;
    receiver: Destination;
    receiverTopup: bigint;
    positionReserve: bigint;
    /** Explicit ADA added to the pool continuation for its changed minimum storage. */
    poolTopup?: bigint;
    lowerBoundMs: bigint;
    /** Staking handlers permit at most 60 seconds. Existing callers retain 50 seconds. */
    validityWindowMs?: bigint;
    /** Maximum Test1-style reward contribution on entry. Required even when zero. */
    maxRewardInput: bigint;
    /** Minimum reward receipt on exit. Required even when zero. */
    minRewardOutput: bigint;
}
export function positionName(seed: {
    txId: string;
    index: bigint;
}) {
    const raw = Data.to(new Constr(0, [seed.txId, seed.index]));
    return withCMLScope((own) => {
        const data = own(CML.PlutusData.from_cbor_bytes(fromHex(raw)));
        return own(CML.hash_plutus_data(data)).to_hex();
    });
}
export function cashStateValue(vault: ComposedVault, state: ReturnType<typeof stateFromData>, rewards: bigint) {
    return value([
        ["ada", state.storageLovelace],
        [vault.settings.terms.underlying, state.accruedFees],
        [ownAsset(vault.policy, "state"), 1n],
        [vault.binding.rewardAsset, rewards],
    ]);
}
const sameValue = (a: Record<string, bigint>, b: Record<string, bigint>) => {
    const normalized = (v: Record<string, bigint>) => JSON.stringify(Object.entries(v)
        .filter(([, q]) => q !== 0n)
        .sort()
        .map(([k, q]) => [k, q.toString()]));
    return normalized(a) === normalized(b);
};
const toData = (raw: Data) => decodeData(Data.to(raw));
/** Pure arithmetic/planning; supplied snapshots are consistency-checked, not chain-authenticated. */
export function buildComposedPlan(input: ComposedOperation) {
    const { vault, deployment, stateInput, poolInput, positionInput, operation, receiver, } = input;
    const terms = vault.settings.terms, binding = vault.binding;
    if (vault.implementation !== "staking-v2")
        throw Error("Current staking controller required");
    const entry = operation === "deposit" || operation === "mint";
    const name = positionName(binding.positionSeed), poolUnit = binding.poolPolicy + "504f4f4c", marker = binding.poolPolicy + name;
    quantity(input.maxRewardInput);
    quantity(input.minRewardOutput);
    quantity(input.receiverTopup);
    quantity(input.positionReserve);
    const validityWindow = input.validityWindowMs ?? 50000n;
    if (validityWindow < 1000n ||
        validityWindow > 60000n ||
        validityWindow % 1000n !== 0n)
        throw new Error("Staking validity window must be whole seconds in 1..60 seconds");
    quantity(input.poolTopup ?? 0n);
    if (input.lowerBoundMs < 0n || input.lowerBoundMs % 1000n !== 0n)
        throw new Error("Whole-second staking validity required");
    if (deployment.policy !== vault.policy ||
        deployment.termsHash !== termsHash(terms) ||
        deployment.buildId !== vault.buildId ||
        deployment.network !== vault.settings.network ||
        deployment.configLock !== vault.genesisPlan.implementation.configLock)
        throw new Error("Stale vault deployment binding");
    const state = stateFromData(stateInput.datum);
    const rewardKey = assetId(binding.rewardAsset), oldRewards = stateInput.value[rewardKey] ?? 0n;
    if (stateInput.address.payment.type !== "script" ||
        stateInput.address.payment.hash !== vault.policy ||
        stateInput.address.stake !== null ||
        state.vaultPolicy !== vault.policy ||
        state.termsHash !== vault.termsHash ||
        !sameValue(stateInput.value, cashStateValue(vault, state, oldRewards)))
        throw new Error("Invalid invested State custody");
    if (!poolInput.datum ||
        poolInput.scriptRef ||
        poolInput.address !==
            credentialToAddress(vault.settings.network, {
                type: "Script",
                hash: binding.poolPolicy,
            }))
        throw new Error("Invalid staking pool input");
    const pool = decodePoolDatum(poolInput.datum);
    if (poolInput.assets[poolUnit] !== 1n ||
        (pool.totalStaked < state.backingAssets) ||
        pool.isLocked ||
        (entry && pool.isPaused))
        throw new Error("Pool identity/backing mismatch or unavailable operation");
    const checkpoint = {
        ...pool,
        ...checkpointPool(pool, input.lowerBoundMs / 1000n),
    };
    let before: PositionState | null = null;
    if (positionInput) {
        if (!positionInput.datum ||
            positionInput.scriptRef ||
            positionInput.assets[marker] !== 1n ||
            positionInput.address !== poolInput.address)
            throw new Error("Invalid staking position input");
        before =
            decodeVaultPosition(positionInput.datum, vault.policy);
        if (before.poolId !== binding.poolPolicy ||
            before.positionName !== name ||
            before.owner !== vault.policy ||
            before.stakedAmount !== state.backingAssets ||
            Data.to(before.payoutAddress) !==
                Data.to(Data.from(hex(encodeData(addressData(enterprise(vault.policy)))))))
            throw new Error("Position binding mismatch");
    }
    else if (!entry ||
        state.backingAssets !== 0n ||
        state.economicSupply !== 0n ||
        !input.creationInput ||
        refId(protocolRef(input.creationInput)) !== refId(binding.positionSeed))
        throw new Error("First stake requires the immutable position creation input");
    const accrued = before
        ? {
            ...before,
            ...checkpointPosition(before, checkpoint.rewardPerTokenStored),
        }
        : null;
    const earned = accrued?.pendingRewards ?? 0n;
    const result = transition(operation, input.amount, input.bound, state, terms);
    const q = result.quote, totalRewards = oldRewards + earned;
    quantity(totalRewards);
    if (state.economicSupply === 0n && totalRewards !== 0n)
        throw new Error("Unowned reward reserve");
    const rewardInput = entry && state.economicSupply > 0n
        ? (totalRewards * q.shares + state.economicSupply - 1n) /
            state.economicSupply
        : 0n;
    const rewardOutput = entry
        ? 0n
        : (totalRewards * q.shares) / state.economicSupply;
    if (rewardInput > input.maxRewardInput ||
        rewardOutput < input.minRewardOutput ||
        (entry && input.minRewardOutput !== 0n) ||
        (!entry && input.maxRewardInput !== 0n))
        throw new Error("Reward contribution/receipt bound exceeded");
    const nextRewards = entry
        ? oldRewards + rewardInput
        : totalRewards - rewardOutput;
    const amount = entry ? q.netAssets : q.grossAssets;
    const nextPool = {
        ...checkpoint,
        totalStaked: pool.totalStaked + result.successor.backingAssets - state.backingAssets,
        accruedLiabilityBound: checkpoint.accruedLiabilityBound - (entry ? 0n : earned),
    };
    if (nextPool.accruedLiabilityBound < 0n)
        throw new Error("Claim exceeds authenticated liability");
    const nextPosition: PositionState = {
        poolId: binding.poolPolicy,
        positionName: name,
        owner: vault.policy,
        payoutAddress: Data.from(hex(encodeData(addressData(enterprise(vault.policy))))),
        stakedAmount: result.successor.backingAssets,
        rewardPerTokenPaid: checkpoint.rewardPerTokenStored,
        pendingRewards: entry ? earned : 0n,
    };
    const stateRedeemer = stakingAuthorization({
        poolId: binding.poolPolicy,
        positionName: name,
        operation: entry ? "stake" : "withdraw_and_claim",
        amount,
        creationRef: before ? null : binding.positionSeed,
        stateOutput: 0n,
        base: directRedeemer(operation, {
            receiver,
            amount: input.amount,
            bound: input.bound,
            stateOutput: 0n,
            receiverOutput: 1n,
        }),
        maxRewardInput: input.maxRewardInput,
        minRewardOutput: input.minRewardOutput,
    });
    const action = Data.from<Data>(hex(encodeData(stakingAction(decodeAuthorization(stateRedeemer)))));
    const payoutAsset = entry
        ? ownAsset(vault.policy, "share")
        : terms.underlying;
    // Start from the canonical plan envelope, then explicitly add admitted staking roles.
    const base = createPlan({
        operation,
        deployment,
        inputs: [],
        referenceInputs: [deployment.configRef],
        outputs: [],
    });
    const plan: ComposedPlan = {
        ...base,
        schema: "STAKING-CTVS1-PLAN-1",
        stateAuthorization: "shared-v1",
        staking: { poolPolicy: binding.poolPolicy, positionName: name },
        inputs: [
            {
                ref: stateInput.ref,
                role: "state",
                redeemer: stateRedeemer,
            },
            {
                ref: protocolRef(poolInput),
                role: "staking_pool",
                redeemer: toData(action),
            },
            ...(positionInput
                ? [
                    {
                        ref: protocolRef(positionInput),
                        role: "staking_position" as const,
                        redeemer: toData(action),
                    },
                ]
                : [
                    {
                        ref: binding.positionSeed,
                        role: "position_seed" as const,
                        redeemer: null,
                    },
                ]),
        ],
        outputs: [
            {
                index: 0n,
                role: "state",
                address: enterprise(vault.policy),
                datum: stateData(result.successor),
                datumMode: "inline",
                referenceScript: null,
                value: cashStateValue(vault, result.successor, nextRewards),
            },
            {
                index: 1n,
                role: "receiver",
                address: receiver.address,
                datum: receiver.datum,
                datumMode: receiver.datum === null ? "none" : "inline",
                referenceScript: null,
                value: value([
                    [payoutAsset, entry ? q.shares : q.netAssets],
                    ["ada", input.receiverTopup],
                    [binding.rewardAsset, rewardOutput],
                ]),
            },
            {
                index: 2n,
                role: "staking_pool",
                address: enterprise(binding.poolPolicy),
                datum: decodeData(encodePoolDatum(nextPool)),
                datumMode: "inline",
                referenceScript: null,
                value: protocolValue({
                    ...poolInput.assets,
                    [terms.underlying === "ada"
                        ? "lovelace"
                        : terms.underlying.policy + terms.underlying.name]: (poolInput.assets[terms.underlying === "ada"
                        ? "lovelace"
                        : terms.underlying.policy + terms.underlying.name] ?? 0n) + (entry ? amount : -amount),
                    [binding.rewardAsset.policy + binding.rewardAsset.name]: (poolInput.assets[binding.rewardAsset.policy + binding.rewardAsset.name] ?? 0n) - (entry ? 0n : earned),
                    lovelace: (poolInput.assets.lovelace ?? 0n) +
                        (terms.underlying === "ada" ? (entry ? amount : -amount) : 0n) +
                        (input.poolTopup ?? 0n),
                }),
            },
            {
                index: 3n,
                role: "staking_position",
                address: enterprise(binding.poolPolicy),
                datum: decodeData(encodeVaultPosition(nextPosition)),
                datumMode: "inline",
                referenceScript: null,
                value: protocolValue(positionInput?.assets ?? {
                    lovelace: input.positionReserve,
                    [marker]: 1n,
                }),
            },
        ],
        mint: [
            {
                policy: vault.policy,
                assets: { [NAMES.share]: result.shareMint },
                redeemer: mintRedeemer({ genesis: false, stateRef: stateInput.ref }),
            },
            ...(before
                ? []
                : [
                    {
                        policy: binding.poolPolicy,
                        assets: { [name]: 1n },
                        redeemer: toData(openPosition(binding.positionSeed, vault.policy)),
                    },
                ]),
        ],
        validity: {
            lowerPosixMs: input.lowerBoundMs,
            upperPosixMs: input.lowerBoundMs + validityWindow,
            lowerInclusive: true,
            upperExclusive: true,
        },
    };
    validateComposedPlan(plan);
    return {
        ...plan,
        economicEffects: q,
        rewardEffects: {
            contribution: rewardInput,
            receipt: rewardOutput,
            claimedFromPool: entry ? 0n : earned,
            remainingReserve: nextRewards,
        },
    };
}
