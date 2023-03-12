+++
title = "GPG-sign in CI/CD builds"
date = 2023-03-12
+++

### TL;DR;
1. Generate GPG key: `gpg --gen-key`. Don't forget to specify password. Keep it in `SIGNING_PASSWORD` CI/CD environment variable.
2. Find a key: `gpg --list-secret-keys --keyid-format short`. Take keyId after `/` . For example: `rsa2048/9B695056` -> `9B695056`. Put it into `SIGNING_KEYID` CI/CD env.
3. Publish a key on public server: `gpg --keyserver https://keys.openpgp.org/ --send-keys 9B695056`
4. Encrypt key `gpg --symmetric --cipher-algo AES256 9B695056.gpg` into file `9B695056.gpg.gpg` . Encryption password save into `SECRET_PASSPHRASE` CI/CD env.
5. Encode key into base64-string: `base64 9B695056.gpg.gpg > 9B695056.base64` . Put `9B695056.base64` content into `GPG_KEY_CONTENTS` CI/CD env.
6. Import key in CI/CD pipeline with script like this (if you're using GitHub actions, append a `secrets.` to environment variables substitution):
    ```bash
    echo '${{secrets.GPG_KEY_CONTENTS}}' | base64 -d > publish_key.gpg
    gpg --quiet --batch --yes --decrypt --passphrase="${{secrets.SECRET_PASSPHRASE}}" \
    --output secret.gpg publish_key.gpg
    ```

<!-- more -->
