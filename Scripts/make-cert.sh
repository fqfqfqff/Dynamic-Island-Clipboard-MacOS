#!/bin/bash
# Создаёт самоподписанный сертификат для подписи Aura.
#
# Зачем: TCC привязывает разрешение Accessibility к подписи приложения.
# Ad-hoc подпись даёт новый хеш при каждой сборке, поэтому выданное разрешение
# слетает после каждой пересборки. Со стабильным сертификатом — не слетает.
#
# Запускать один раз. Может спросить пароль от связки ключей.
set -euo pipefail

NAME="Aura Dev Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Сертификат «$NAME» уже есть, ничего не делаю."
    exit 0
fi

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/aura.key" -out "$WORK/aura.crt" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

# Ключ и сертификат импортируются по отдельности, без PKCS12: современный
# OpenSSL пакует контейнер алгоритмами, которых Security.framework не знает,
# и падает на «Unknown format in import».
#
# -A разрешает codesign пользоваться ключом без запроса на каждую сборку.
security import "$WORK/aura.key" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -A
security import "$WORK/aura.crt" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -A

# Доверие для подписи кода. Шаг необязательный — codesign работает и без него,
# а запрос пароля здесь всплывает не на всех системах. Если не удалось, идём
# дальше: для TCC важна стабильность подписи, а не её доверенность.
security add-trusted-cert -r trustRoot -p codeSign \
    -k ~/Library/Keychains/login.keychain-db "$WORK/aura.crt" 2>/dev/null \
    || echo "доверие не добавлено — на подпись это не влияет"

echo
echo "Готово. Проверка:"
security find-identity -v -p codesigning | grep "$NAME" || echo "  сертификат не найден — см. вывод выше"
