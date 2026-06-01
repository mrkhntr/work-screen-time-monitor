// Public API. Native shells call the JSON-string boundary on `globalThis.WSTCore`
// (set as a side effect of evaluating the bundle). Tests import the typed
// functions directly from the modules below.

import { defaultConfig, parseConfig } from "./config";
import { reduce } from "./reducer";
import { defaultState, NowSchema, parseState } from "./state";

export * from "./types";
export * from "./config";
export * from "./state";
export * from "./schedule";
export { escalationState } from "./escalation";
export { notifiesOnSnooze } from "./accountability";
export { matchesConfirmationPhrase, normalizePhrase } from "./phrase";
export { buildWebhookRequest, renderWebhookRequest } from "./webhook";
export { reduce } from "./reducer";

/** JSON-string boundary: native host passes/receives strings to avoid marshaling structs. */
function reduceJson(stateJson: string, eventJson: string, nowJson: string, configJson: string): string {
  const state = parseState(JSON.parse(stateJson));
  const event = JSON.parse(eventJson);
  const now = NowSchema.parse(JSON.parse(nowJson));
  const config = parseConfig(JSON.parse(configJson));
  return JSON.stringify(reduce(state, event, now, config));
}

const api = {
  version: "0.1.0",
  reduce: reduceJson,
  defaultConfig: (): string => JSON.stringify(defaultConfig()),
  normalizeConfig: (json: string): string => JSON.stringify(parseConfig(JSON.parse(json))),
  defaultState: (): string => JSON.stringify(defaultState()),
};

(globalThis as Record<string, unknown>).WSTCore = api;

export default api;
