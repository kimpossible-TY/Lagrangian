// Native crypto handles signature algorithms; Python owns OAuth claim policy.
// Only public JWKS and the pending ID token cross this private stdin pipe.
import { createPublicKey, verify } from "node:crypto";

let input = "";
for await (const chunk of process.stdin) {
  input += chunk;
  if (input.length > 262144) process.exit(1);
}
try {
  const { token, keys } = JSON.parse(input);
  const [header, payload, signature, extra] = token.split(".");
  if (extra !== undefined) throw new Error();
  const meta = JSON.parse(Buffer.from(header, "base64url"));
  const algorithms = { RS256: "RSA-SHA256", ES256: "sha256", EdDSA: null };
  if (!Object.hasOwn(algorithms, meta.alg) || meta.crit) throw new Error();
  const matches = keys.filter(
    (key) =>
      key.kid === meta.kid &&
      (!key.alg || key.alg === meta.alg) &&
      (!key.use || key.use === "sig") &&
      (!key.key_ops || key.key_ops.includes("verify")),
  );
  if (matches.length !== 1) throw new Error();
  const jwk = matches[0];
  if (
    (meta.alg === "RS256" && jwk.kty !== "RSA") ||
    (meta.alg === "ES256" && (jwk.kty !== "EC" || jwk.crv !== "P-256")) ||
    (meta.alg === "EdDSA" && (jwk.kty !== "OKP" || jwk.crv !== "Ed25519"))
  )
    throw new Error();
  const key = createPublicKey({ key: jwk, format: "jwk" });
  if (
    !verify(
      algorithms[meta.alg],
      Buffer.from(`${header}.${payload}`),
      meta.alg === "ES256" ? { key, dsaEncoding: "ieee-p1363" } : key,
      Buffer.from(signature, "base64url"),
    )
  )
    throw new Error();
  process.stdout.write(Buffer.from(payload, "base64url"));
} catch {
  process.exitCode = 1;
}
