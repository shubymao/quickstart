#!/bin/bash

INVENTORY_FILE="inventory.yml"
KEYS_DIR="./keys"

mkdir -p "$KEYS_DIR"

if [ ! -f "$INVENTORY_FILE" ]; then
  echo "Error: $INVENTORY_FILE not found!"
  exit 1
fi

echo "Encrypting $INVENTORY_FILE and moving to $KEYS_DIR..."

# We use --output to save the encrypted version into the keys folder
ansible-vault encrypt "$INVENTORY_FILE" --output "$KEYS_DIR/inventory.vault.yml"

if [ $? -eq 0 ]; then
  echo "Success! Encrypted inventory is at $KEYS_DIR/inventory.vault.yml"
  read -p "Delete the original unencrypted file for security? (y/n): " CONFIRM
  if [ "$CONFIRM" = "y" ]; then
    rm "$INVENTORY_FILE"
    echo "Original file removed."
  fi
else
  echo "Encryption failed."
fi
