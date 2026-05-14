#!/bin/bash
BODY=$(gh release view v1.0.18 --json body --jq '.body' || echo "No notes yet")
gh api -X POST /markdown -f text="$BODY" --header "Accept: application/vnd.github.v3+json"
