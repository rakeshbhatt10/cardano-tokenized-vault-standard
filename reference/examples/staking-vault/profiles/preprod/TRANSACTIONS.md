# single-staking-protocol × CTVS-1 — Preprod deployment and transaction record

**Record date: 27 October 2026. Network: Cardano Preprod; network magic: 1.** All times below are IST (UTC+05:30).

This standalone record identifies the shared authenticated factory, staking pool and the second vault instance used for the completed deposit → redeem/claim → re-entry → fixed-amount withdraw/claim sequence. Every confirmed hash links to the public Preprod explorer. The earlier empty vault is identified separately at the end.

## 1. Addresses and policy IDs

| Component | Address or identifier | Role |
| --- | --- | --- |
| Tested vault — script address | [addr_test1wz9pcsykk6dqja6qu9j8jdy0ktt5sc5jt46q6nwngdggv4ca4jhtu](https://preprod.cardanoscan.io/address/addr_test1wz9pcsykk6dqja6qu9j8jdy0ktt5sc5jt46q6nwngdggv4ca4jhtu) | Holds the authenticated State NFT and vault State |
| Vault controller / SHARE policy | `8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657` | One program validates State spending and share mint/burn |
| Staking pool and positions — script address | [addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj](https://preprod.cardanoscan.io/address/addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj) | Pool State and the vault-owned staking position use this same address |
| Staking pool / position policy | `02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36` | Authenticates the POOL and position NFTs |
| Permanent Config/certificate lock — script address | [addr_test1wq3vnggra5ljl2tunqkhd4hz4agvt422cvrfswcedj8um2cwsu3l3](https://preprod.cardanoscan.io/address/addr_test1wq3vnggra5ljl2tunqkhd4hz4agvt422cvrfswcedj8um2cwsu3l3) | Holds immutable vault Config ID and registration certificate |
| Config/certificate lock script hash | `22c9a103ed3f2fa97c982d76d6e2af50c5d54ac306983b196c8fcdab` | Permanent lock |
| Authenticated factory — minting policy | `9ca7570e34603c08370ac69d204ebdf9651d4b6bdd193918adc43370` | Mints a certificate at vault creation; no factory spending-State address |
| Funding, share receiver and payout wallet | [addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5](https://preprod.cardanoscan.io/address/addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5) | Key-controlled wallet; also hosts the published reference outputs |

State validation is compiled into the vault controller; it has no separate script address. The factory is a minting policy. Publishing its program as a reference output and later minting a vault registration certificate are separate transactions.

## 2. Shared infrastructure — confirmed transactions

| Action | Confirmed transaction hash | IST | Fee (test ADA) |
| --- | --- | --- | --- |
| Factory policy reference publication | [e1892706c527ad510a32a1764221db61c875166ef85350bda400294ad830a14b](https://preprod.cardanoscan.io/transaction/e1892706c527ad510a32a1764221db61c875166ef85350bda400294ad830a14b) | 13:14:48 | 0.315497 |
| Controller template data, part 1 | [a6af01e221cdfaba76c22cea61ee49f9211613c38ba9601ba5b5cd1c90202a39](https://preprod.cardanoscan.io/transaction/a6af01e221cdfaba76c22cea61ee49f9211613c38ba9601ba5b5cd1c90202a39) | 13:17:02 | 0.532417 |
| Controller template data, part 2 | [29019876572d25dafdeb465d0ea438661a3ef9b471d1813300b3b7f4cbd6c319](https://preprod.cardanoscan.io/transaction/29019876572d25dafdeb465d0ea438661a3ef9b471d1813300b3b7f4cbd6c319) | 13:19:40 | 0.532417 |
| Mint MixedPrincipal and MixedReward | [0fe821595f19e4d2abe239074c2de642df5c862afa7de20c0e35daf6e4bc4b4b](https://preprod.cardanoscan.io/transaction/0fe821595f19e4d2abe239074c2de642df5c862afa7de20c0e35daf6e4bc4b4b) | 14:07:20 | 0.242282 |
| Publish staking reference script | [06dfa039f5d3a4ab027ca3e31ea848d95bdd3b6e5b859245ea50c7abd92ae7e9](https://preprod.cardanoscan.io/transaction/06dfa039f5d3a4ab027ca3e31ea848d95bdd3b6e5b859245ea50c7abd92ae7e9) | 14:10:35 | 0.871173 |
| Initialize permanently unlocked mixed-owner pool | [6ac68a507ceadd3f58694d4250fc4d7192faeb67935610135971dbf548453cab](https://preprod.cardanoscan.io/transaction/6ac68a507ceadd3f58694d4250fc4d7192faeb67935610135971dbf548453cab) | 14:17:34 | 0.448396 |
| Fund/notify pool reward schedule | [dcb322cd283f577883251e7ab994513dc4fda1e33bb9c1d0c657a785376e2e1f](https://preprod.cardanoscan.io/transaction/dcb322cd283f577883251e7ab994513dc4fda1e33bb9c1d0c657a785376e2e1f) | 14:18:01 | 0.731180 |

The pool supports wallet-owned and vault-owned version-2 positions, permanently disables withdrawal locks for this vault integration and trusts the factory policy above. Its initial reward budget was **70 MixedReward** for **604,800 seconds (7 days)**. Both test tokens have **6 decimals**; 1 token = 1,000,000 base units.

## 3. Tested vault — deployment and lifecycle transactions

| Action | Confirmed transaction hash | IST | Fee (test ADA) | Result |
| --- | --- | --- | --- | --- |
| Provision genesis seed, position seed and collateral | [9e7a19b166e2b7849d052ffeabaf85782ddac82ff7da4687023420ddb340fa82](https://preprod.cardanoscan.io/transaction/9e7a19b166e2b7849d052ffeabaf85782ddac82ff7da4687023420ddb340fa82) | 15:58:10 | 0.174213 | Three separate 5-test-ADA wallet outputs |
| Publish vault controller reference | [c86b3f1980e64f888360bc7ae244b937578fa8cc6f247942e93f2f2bef555f78](https://preprod.cardanoscan.io/transaction/c86b3f1980e64f888360bc7ae244b937578fa8cc6f247942e93f2f2bef555f78) | 16:03:19 | 0.872537 | Controller program published |
| Atomic vault genesis + factory registration | [66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c](https://preprod.cardanoscan.io/transaction/66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c) | 16:08:32 | 0.684711 | Mint Config ID, State NFT and registration certificate; zero initial supply |
| First deposit and position creation | [0a5c84c158ea6c837e44bf94191e6e20afbc52d7cde8bf4a18777557ad9ccc47](https://preprod.cardanoscan.io/transaction/0a5c84c158ea6c837e44bf94191e6e20afbc52d7cde8bf4a18777557ad9ccc47) | 16:55:13 | 1.332700 | Stake 10 MixedPrincipal; mint 10,000,000,000,000 share base units; create one position NFT |
| Full Redeem + claim | [431dba6b1d17290a3150c3b22cbaa38c1c2f037586c237d1fbf1ba8b07b6ec05](https://preprod.cardanoscan.io/transaction/431dba6b1d17290a3150c3b22cbaa38c1c2f037586c237d1fbf1ba8b07b6ec05) | 18:49:12 | 1.400513 | Burn all shares; return 10 MixedPrincipal + 0.786140 MixedReward |
| Re-entry deposit; position reused | [1788dddfb6bbde80f21aec94745a882356b23f86f89bb24c6277fa0369f4c889](https://preprod.cardanoscan.io/transaction/1788dddfb6bbde80f21aec94745a882356b23f86f89bb24c6277fa0369f4c889) | 19:22:27 | 1.360732 | Stake 10 MixedPrincipal; mint 10,000,000,000,000 share base units; reuse position NFT |
| Fixed-amount Withdraw + claim | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 19:26:32 | 1.400442 | Request 10 MixedPrincipal; burn required shares; return 10 MixedPrincipal + 0.030015 MixedReward |

Seed provisioning transaction `9e7a19b166e2b7849d052ffeabaf85782ddac82ff7da4687023420ddb340fa82` created the genesis seed at `#0`, position seed at `#1` and dedicated collateral at `#2`. Genesis consumed the first seed; the first deposit consumed the position seed. Vault genesis transaction `66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c` created Config at `#0`, the initial State at `#1` and the certificate at `#2`. The State subsequently moved through the lifecycle transactions.

**Redeem** selects the share amount to burn and derives principal received. **Withdraw** selects the net principal to receive and caps the required share burn. The final transaction used the actual CTVS **Withdraw** action with **10,000,000 principal base units** and a maximum burn of **10,000,000,000,000 share base units**. Both exit paths invoke staking **WithdrawAndClaim** in the same transaction. No separate claim transaction was needed.

At zero entry/exit fees, each tested 10-token deposit minted 10,000,000,000,000 share base units under the configured 1,000,000 virtual-share scale. Share amounts here are **base units**, not a declared human-readable token denomination.

## 4. Token and NFT identities

| Asset | Policy ID | Asset name (hex) | Purpose |
| --- | --- | --- | --- |
| MixedPrincipal | `fdab00e21b190b1be225cee5c7aefd0a505975ece08d1972ce31769e` | `4d697865645072696e636970616c` | Vault deposit and staking principal; 6 decimals |
| MixedReward | `d0f8a2f1830941b14d32facbfbfe58782706be7409be3aed1cee7d40` | `4d69786564526577617264` | Claimed staking rewards; 6 decimals |
| Config ID | `8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657` | `4944` | One immutable Config identity |
| State NFT | `8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657` | `5354415445` | One continuing vault State identity |
| SHARE | `8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657` | `5348415245` | Minted on entry; burned on exit |
| Registration certificate | `9ca7570e34603c08370ac69d204ebdf9651d4b6bdd193918adc43370` | `8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657` | Binds factory-approved controller and Config |
| POOL NFT | `02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36` | `504f4f4c` | One continuing shared pool identity |
| Vault position NFT | `02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36` | `665e1f7a82e3cf93c189bf481fde7b1cb60489de4aeb4042433d79f0d2f2174c` | One continuing position owned by this vault |

A Cardano asset unit is the policy ID concatenated with the asset-name hex, without a separator. The position NFT is:

```text
02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36665e1f7a82e3cf93c189bf481fde7b1cb60489de4aeb4042433d79f0d2f2174c
```

The position owner is **VaultOwner(controller=8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657, State policy=8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657, State name=5354415445)**. It is controlled through the authenticated vault State transition. Re-entry and withdrawal reuse this position identity.

## 5. Reference outputs and permanent vault records

| Record | Transaction hash | Output index | Location/status |
| --- | --- | --- | --- |
| Factory policy program | [e1892706c527ad510a32a1764221db61c875166ef85350bda400294ad830a14b](https://preprod.cardanoscan.io/transaction/e1892706c527ad510a32a1764221db61c875166ef85350bda400294ad830a14b) | 0 | At the funding wallet |
| Controller template, part 1 | [a6af01e221cdfaba76c22cea61ee49f9211613c38ba9601ba5b5cd1c90202a39](https://preprod.cardanoscan.io/transaction/a6af01e221cdfaba76c22cea61ee49f9211613c38ba9601ba5b5cd1c90202a39) | 0 | At the funding wallet |
| Controller template, part 2 | [29019876572d25dafdeb465d0ea438661a3ef9b471d1813300b3b7f4cbd6c319](https://preprod.cardanoscan.io/transaction/29019876572d25dafdeb465d0ea438661a3ef9b471d1813300b3b7f4cbd6c319) | 0 | At the funding wallet |
| Staking program | [06dfa039f5d3a4ab027ca3e31ea848d95bdd3b6e5b859245ea50c7abd92ae7e9](https://preprod.cardanoscan.io/transaction/06dfa039f5d3a4ab027ca3e31ea848d95bdd3b6e5b859245ea50c7abd92ae7e9) | 0 | At the funding wallet |
| Tested vault controller program | [c86b3f1980e64f888360bc7ae244b937578fa8cc6f247942e93f2f2bef555f78](https://preprod.cardanoscan.io/transaction/c86b3f1980e64f888360bc7ae244b937578fa8cc6f247942e93f2f2bef555f78) | 0 | At the funding wallet |
| Immutable Config ID | [66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c](https://preprod.cardanoscan.io/transaction/66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c) | 0 | At the permanent Config/certificate lock |
| Registration certificate | [66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c](https://preprod.cardanoscan.io/transaction/66c3ef20deb231ddbec675fc6eb932d639d4e91c02ade1e79cc8fe8772c19f1c) | 2 | At the permanent Config/certificate lock |
| Dedicated collateral | [9e7a19b166e2b7849d052ffeabaf85782ddac82ff7da4687023420ddb340fa82](https://preprod.cardanoscan.io/transaction/9e7a19b166e2b7849d052ffeabaf85782ddac82ff7da4687023420ddb340fa82) | 2 | 5 test ADA, key-owned and unspent at final readback |

An output reference is written as `transactionHash#outputIndex`. Published program/template outputs are wallet-owned references; Config and the certificate use the permanent lock. Spending an old State/pool/position output replaces its reference, so use the final references below for the recorded final state.

## 6. Final verified state

Snapshot: **27 October 2026, 19:27:35 IST**, after the confirmed fixed-amount withdrawal. This is a historical readback, not a live balance feed.

| Output | Transaction hash | Index | Address | Final contents |
| --- | --- | --- | --- | --- |
| Vault State | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 0 | [addr_test1wz9pcsykk6dqja6qu9j8jdy0ktt5sc5jt46q6nwngdggv4ca4jhtu](https://preprod.cardanoscan.io/address/addr_test1wz9pcsykk6dqja6qu9j8jdy0ktt5sc5jt46q6nwngdggv4ca4jhtu) | STATE NFT; backing 0; share supply 0; 2.422300 test ADA |
| Withdrawal payout | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 1 | [addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5](https://preprod.cardanoscan.io/address/addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5) | 10 MixedPrincipal + 0.030015 MixedReward + 2.396440 test ADA |
| Pool State | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 2 | [addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj](https://preprod.cardanoscan.io/address/addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj) | POOL NFT; total principal 0; 69.183845 MixedReward + 2.680900 test ADA |
| Vault-owned position | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 3 | [addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj](https://preprod.cardanoscan.io/address/addr_test1wqp0zvmf4jluw9lcz9qndyw4fhm640zrec7cx4fxtv5ccdspqvmwj) | Same position NFT; principal/pending rewards 0; 3.004150 test ADA |
| Wallet change | [1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce](https://preprod.cardanoscan.io/transaction/1b0331464b6d01a515626f72455847c1e36ad5e92f2a7af0eca3f501095b7fce) | 4 | [addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5](https://preprod.cardanoscan.io/address/addr_test1qzx2wkt926dmrrver2878sp4jjzz055umccckdkhgwunhjxz3veecmqv0k658p9tnnn57rlc2yhjzadc4a8jamqhl09sr4krd5) | Unused funding and prior wallet token inventory returned |

The vault and position remain open and reusable. Their NFTs and ADA storage were retained; they were not closed. All exact outputs and **16 protected outputs** matched readback for each successful user operation, including the earlier empty vault, Config/certificates, published references and collateral.

Wallet inventory verified at **19:30:08 IST**: **1,000 MixedPrincipal**, **930.816155 MixedReward**, and **zero shares of this vault**. Across the two completed exit transactions, newly claimed rewards total **0.816155 MixedReward**.

## 7. Fees and configuration

| Scope | Confirmed network fees (test ADA) |
| --- | --- |
| Shared factory publications | 1.380331 |
| Test-token mint + staking reference + pool initialization + reward funding | 2.293031 |
| Tested vault seed provisioning + controller publication + genesis | 1.731461 |
| Tested vault deposit + redeem/claim + re-entry + fixed Withdraw/claim | 5.494387 |
| Tested vault setup and all four user operations | 7.225848 |
| All main-record transactions, including shared infrastructure | 10.899210 |
| Re-entry → fixed Withdraw cycle only (already included above) | 2.761174 |

These are network fees, not principal deposits or ADA held in outputs. Entry fee: **0%**; exit fee: **0%**. The vault uses **1,000,000 virtual share units**, has **no backing cap**, and records the configured wallet as fee recipient and pause administrator. The shared factory, published programs and retained State/position/storage balances are not counted as fees.

## 8. Expired or rejected attempts — not confirmed transactions

| Attempt | Body hash | Outcome |
| --- | --- | --- |
| Pool initialization | `3ba31415bd57aa072c1c255fa63d955179f2a94adf9be3885032ab1c0967fc45` | Node rejected stale/spent collateral selection before acceptance |
| Full redemption | `069d5b6a1b577007030dcd3e2ce7b9907c097dd7c9163d5679ceeb01cb73425f` | Submitted; expired without inclusion |
| Full redemption replacement | `722b9b027d8e0664084766c49b6a8fbd70f9bb9adde7e17310166ff986d8ad45` | Node rejected a start slot ahead of its current slot; later reconciled beyond expiry |
| Re-entry deposit | `dcfa3acf790454f729ed386dd9b270bd96a16b534123bc9cf37e19d7b801dc88` | Submitted; expired without inclusion |

These hashes are retained for audit history and are not successful deployment or withdrawal hashes. The vault-operation attempts were reconciled after expiry with every normal input and collateral unspent and unchanged before replacement. The pool-initialization rejection also consumed no collateral. **No network fee, collateral or principal was consumed by the listed unsuccessful attempts.** Unsigned preflight hashes are not part of the confirmed transaction sequence.

## 9. Earlier empty vault — separate instance

This earlier vault shares the same factory and pool but was not the vault used for the lifecycle in section 3. It remained empty and protected during the tested vault’s operations.

| Identity | Value |
| --- | --- |
| Script address | [addr_test1wrw8fvr4m0xg3p3c2lkascqgr7h5t3pjxrfmef6vmrvyy3shhgmdg](https://preprod.cardanoscan.io/address/addr_test1wrw8fvr4m0xg3p3c2lkascqgr7h5t3pjxrfmef6vmrvyy3shhgmdg) |
| Controller / share policy | `dc74b075dbcc88863857edd860081faf45c43230d3bca74cd8d84246` |
| Controller reference transaction | [33ff6bb49064cf54124c2c67665e0fd2e1bc0ea05333d21bff4d27c9607ed7ee](https://preprod.cardanoscan.io/transaction/33ff6bb49064cf54124c2c67665e0fd2e1bc0ea05333d21bff4d27c9607ed7ee) — output 0 |
| Genesis / factory registration | [a1cfca458f6d1ba973d7c0b96531780a3f5f330da7900bc54b3a4af7938abe9b](https://preprod.cardanoscan.io/transaction/a1cfca458f6d1ba973d7c0b96531780a3f5f330da7900bc54b3a4af7938abe9b) |
| Immutable Config reference | `a1cfca458f6d1ba973d7c0b96531780a3f5f330da7900bc54b3a4af7938abe9b#0` |
| Unchanged empty State reference | `a1cfca458f6d1ba973d7c0b96531780a3f5f330da7900bc54b3a4af7938abe9b#1` |
| Certificate reference | `a1cfca458f6d1ba973d7c0b96531780a3f5f330da7900bc54b3a4af7938abe9b#2` |
| Controller publication + genesis fees | 1.557143 test ADA |

Its two confirmed transactions add **1.557143 test ADA** to the main-record fees. Including that earlier instance, all confirmed transactions listed in this document total **12.456353 test ADA** in network fees.

## 10. Verification status

The confirmed transactions above have archived chain receipts and output readbacks. The final signed withdrawal’s State redeemer was decoded to verify the **Withdraw** action, its exact principal amount and maximum share burn, coupled to **WithdrawAndClaim**. The tested sequence demonstrates first entry, full Redeem/claim, re-entry without reminting the position NFT and full fixed-asset Withdraw/claim. **122 package tests and TypeScript checks passed** at this checkpoint.

Independent review, live partial operations/nonempty top-ups and broader multiple-vault histories remain pending. This Preprod record does not establish production readiness.
