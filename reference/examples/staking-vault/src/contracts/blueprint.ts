import type { FactoryBlueprint } from "../../vendor/client/src/factory/proof/build.ts";

/** Require exactly the current handlers, with the deployed compiled bytes and
 * parameter shapes. Removing unrelated prototypes changes the whole blueprint. */
export function assertDeployedBlueprint(
  rebuilt: FactoryBlueprint,
  original: FactoryBlueprint,
  titles: string[],
  family: "factory" | "staking" = "factory",
) {
  const names = rebuilt.validators.map((validator) => validator.title).sort();

  if (
    new Set(titles).size !== titles.length ||
    JSON.stringify(names) !== JSON.stringify([...titles].sort())
  )
    throw Error(`Unexpected current ${family} validator set`);

  const programs = titles.map((title) => {
    const actual = rebuilt.validators.find((validator) => validator.title === title);
    const expected = original.validators.find((validator) => validator.title === title);

    if (
      !actual ||
      !expected ||
      actual.compiledCode !== expected.compiledCode ||
      actual.hash !== expected.hash ||
      JSON.stringify(actual.parameters) !== JSON.stringify(expected.parameters)
    )
      throw Error(`Current validator differs from deployed program: ${title}`);

    return { title, hash: actual.hash, bytes: actual.compiledCode.length / 2 };
  });

  return programs;
}
