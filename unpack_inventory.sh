#!/bin/bash

VAULT_FILE="./keys/inventory.vault.yml"
OUTPUT_FILE="inventory.yml"

if [ ! -f "$VAULT_FILE" ]; then
    echo "Error: Vault file $VAULT_FILE not found in ./keys/"
    exit 1
fi

echo "Decrypting $VAULT_FILE to $OUTPUT_FILE..."

# This will prompt you for the vaultpass once and then decrypt
ansible-vault decrypt "$VAULT_FILE" --output "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
    echo "Success: $OUTPUT_FILE is now available for use."
else
    echo "Decryption failed. Please check your vaultpass."
    exit 1
fi
