// Pantheon: revoke Sign in with Apple when a player deletes his account
// (2026-09-23; Docs/BACKEND.md §7, Docs/SETTINGS.md §3).
//
// Apple requires an app that offers Sign in with Apple to revoke the user's
// tokens through its REST API when the account is deleted. That needs a
// client secret signed with the team's Sign in with Apple key, which can
// only live on a server — so the phone does the one thing it can: at the
// moment of deletion it asks Apple for a fresh authorization and sends its
// one-time code here. This function
//
//   1. signs a client secret (an ES256 JWT: kid = the key's id, iss = the
//      team, sub = the app's bundle id, aud = https://appleid.apple.com,
//      five minutes long) with the key in the APPLE_PRIVATE_KEY secret;
//   2. exchanges the code at https://appleid.apple.com/auth/token
//      (grant_type=authorization_code; no redirect_uri, since a native
//      app's authorization request has none) for a refresh token;
//   3. revokes that token at https://appleid.apple.com/auth/revoke.
//
// Secrets (Dashboard → Edge Functions → Secrets, or `supabase secrets set`):
//   APPLE_TEAM_ID      the ten-character Team ID
//   APPLE_KEY_ID       the ten-character id of the Sign in with Apple key
//   APPLE_PRIVATE_KEY  the whole AuthKey_<id>.p8 file, header lines included
//   APPLE_CLIENT_ID    com.pantheon.game, the app's bundle id
//
// Called only by a signed-in player: Supabase checks the caller's JWT before
// this code runs (verify_jwt, the default — leave it on). Nothing here reads
// or writes the database; the app deletes the user itself right after, with
// delete_my_account(). A code or a token is never logged.
//
// Answers: 200 {"revoked":true}; 400 when no code was sent; 500 when a
// secret is missing or the key cannot be read; 502 with Apple's own error
// when Apple refuses. The app treats anything but 200 as "not revoked",
// deletes everything else anyway, and tells the player how to stop using the
// Apple ID by hand.

const APPLE = "https://appleid.apple.com";
const FORM = { "Content-Type": "application/x-www-form-urlencoded" };

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return reply({ error: "POST only" }, 405);
  }

  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY") ?? "";
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "";
  const missing = [
    ["APPLE_TEAM_ID", teamId],
    ["APPLE_KEY_ID", keyId],
    ["APPLE_PRIVATE_KEY", privateKey],
    ["APPLE_CLIENT_ID", clientId],
  ].filter(([, value]) => value.trim() === "").map(([name]) => name);
  if (missing.length > 0) {
    console.error(`apple-revoke: missing secrets ${missing.join(", ")}`);
    return reply({ error: "not configured", missing }, 500);
  }

  let code = "";
  try {
    const body = await req.json();
    if (typeof body?.authorization_code === "string") code = body.authorization_code.trim();
  } catch {
    // An unreadable body is the same as no code.
  }
  if (code === "") {
    return reply({ error: "authorization_code is required" }, 400);
  }

  let clientSecret: string;
  try {
    clientSecret = await makeClientSecret(teamId.trim(), keyId.trim(), clientId.trim(), privateKey);
  } catch (error) {
    console.error(`apple-revoke: the private key could not be used: ${error}`);
    return reply({ error: "the private key could not be read" }, 500);
  }

  // 1. The one-time code for Apple's tokens.
  const exchanged = await fetch(`${APPLE}/auth/token`, {
    method: "POST",
    headers: FORM,
    body: new URLSearchParams({
      client_id: clientId.trim(),
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  });
  const tokens = await exchanged.json().catch(() => ({}));
  if (!exchanged.ok) {
    console.error(`apple-revoke: /auth/token answered ${exchanged.status} ${tokens?.error ?? ""}`);
    return reply({ error: "Apple refused the authorization code", apple: tokens?.error ?? exchanged.status }, 502);
  }
  const token: string | undefined = tokens.refresh_token ?? tokens.access_token;
  const hint = tokens.refresh_token ? "refresh_token" : "access_token";
  if (!token) {
    console.error("apple-revoke: /auth/token answered without a token");
    return reply({ error: "Apple returned no token" }, 502);
  }

  // 2. The token revoked: Pantheon leaves the Apple ID's Sign in with Apple
  // list, and the next sign-in asks for the name and the email again.
  const revoked = await fetch(`${APPLE}/auth/revoke`, {
    method: "POST",
    headers: FORM,
    body: new URLSearchParams({
      client_id: clientId.trim(),
      client_secret: clientSecret,
      token,
      token_type_hint: hint,
    }),
  });
  if (!revoked.ok) {
    const detail = await revoked.json().catch(() => ({}));
    console.error(`apple-revoke: /auth/revoke answered ${revoked.status} ${detail?.error ?? ""}`);
    return reply({ error: "Apple refused the revocation", apple: detail?.error ?? revoked.status }, 502);
  }
  console.log("apple-revoke: revoked");
  return reply({ revoked: true }, 200);
});

function reply(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// The client secret: an ES256 JWT signed with the Sign in with Apple key
// (Apple, "Creating a client secret"). Apple allows up to six months; five
// minutes is all one revocation needs.
// ---------------------------------------------------------------------------

async function makeClientSecret(teamId: string, keyId: string, clientId: string, pem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId };
  const payload = { iss: teamId, iat: now, exp: now + 300, aud: APPLE, sub: clientId };
  const encoder = new TextEncoder();
  const signingInput = `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(payload)))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto signs ECDSA as r||s (64 bytes), which is exactly JWS's ES256.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

// The .p8 file's PEM as DER bytes. A secret pasted through a shell often
// arrives with its line breaks as the two characters "\n"; both forms work.
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
