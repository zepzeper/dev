# secrets

Encrypted with [age](https://age-encryption.org). Managed by `dev-secrets`.

```
identity.age     the age private key, encrypted with your passphrase
recipient.txt    the matching public key - not secret, used to add secrets
MANIFEST         name -> destination -> mode
store/*.age      the secrets themselves
```

Everything is encrypted to one identity, and that identity is encrypted with a
passphrase. So a new machine needs exactly one thing that is not in this repo:
**the passphrase**. Keep it in Bitwarden.

Adding a secret only needs `recipient.txt`, so `dev-secrets add` never prompts.
Only reading prompts.

## Usage

```sh
dev-secrets init                                  # once, ever
dev-secrets add <name> <file> [dest] [mode]       # encrypt a file in
dev-secrets unlock                                # write secrets to their destinations
dev-secrets cat <name>                            # print one to stdout
dev-secrets edit <name>                           # decrypt, edit, re-encrypt
dev-secrets verify [name...]                      # check the store against disk
dev-secrets list
```

`unlock` also derives the `.pub` beside any secret that turns out to be an ssh
private key, so there is no reason to store public keys here.

`verify` decrypts each secret and compares it to the file it unlocks to,
exiting non-zero on any mismatch. It uses `cmp -s` rather than `diff`, so a
mismatch never prints key material.

A destination of `-` means the secret has no file on disk — recovery codes, for
example. Read those with `cat`.

## What is safe here

- Plaintext is only ever written to a tmpfs (`$XDG_RUNTIME_DIR`, falling back to
  `/dev/shm`) and removed when the command exits. It never touches the disk.
- `.gitignore` denies everything under `secrets/` and allows back only `*.age`,
  `recipient.txt` and `MANIFEST`. A stray plaintext file cannot be committed by
  accident.
- Decrypted files are written with the mode in `MANIFEST` (`600` for keys), and
  `~/.ssh` is forced to `700`, which ssh refuses to work without.

## What is not

**Ciphertext committed here is permanent.** Git history keeps every version, so
`dev-secrets rm` removes a secret from the working tree but not from history.
If a secret leaks, rotating it at the source — new SSH key on GitHub, new
recovery codes — is the only real fix.

**Losing the passphrase loses everything.** There is no recovery path, by
design.

**One key everywhere.** The SSH key here is shared across machines, so losing
any machine means rotating it on all of them. Per-machine keys avoid that; this
repo trades it for zero manual setup.
