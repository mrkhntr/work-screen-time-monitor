// Mirrors WorkScreenTimeCore/ConfirmationPhraseMatcher.swift: lowercase, keep
// only a–z, compare.

export function normalizePhrase(value: string): string {
  let out = "";
  for (const ch of value.toLowerCase()) {
    const c = ch.charCodeAt(0);
    if (c >= 97 && c <= 122) out += ch;
  }
  return out;
}

export function matchesConfirmationPhrase(input: string, phrase: string): boolean {
  return normalizePhrase(input) === normalizePhrase(phrase);
}
