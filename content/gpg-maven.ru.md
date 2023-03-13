+++
title = "Настройка GPG подписи в CI/CD"
date = 2023-03-12
[taxonomies]
tags = ["til"]
+++

### TL;DR;

1. Сгенерировать ключ: `gpg --gen-key` При генерации нужно указать пароль. Запишем в переменную окружения `SIGNING_PASSWORD` 
2. Взять ключ: `gpg --list-secret-keys --keyid-format short`. Id будет указан после слеша, например: `rsa2048/9B695056`. Запишем в переменную `SIGNING_KEYID`
3. Опубликовать ключ: `gpg --keyserver https://keys.openpgp.org/ --send-keys 9B695056`
4. Зашифровать ключ: `gpg --symmetric --cipher-algo AES256 9B695056.gpg` . Получим файл `9B695056.gpg.gpg` . Пароль, введенный при шифровке будет `SECRET_PASSPHRASE`
5. Переведем ключ в base64: `base64 9B695056.gpg.gpg > 9B695056.base64` . Запишем в переменную `GPG_KEY_CONTENTS`
6. В CI/DI пайплайне импортируем ключ:
    ```bash
    echo '${{secrets.GPG_KEY_CONTENTS}}' | base64 -d > publish_key.gpg
    gpg --quiet --batch --yes --decrypt --passphrase="${{secrets.SECRET_PASSPHRASE}}" \
    --output secret.gpg publish_key.gpg
    ```

<!-- more -->