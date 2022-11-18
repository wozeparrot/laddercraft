# Registry Data

## `blocks.json`

Since some version ???, the file isn't sorted by protocol_id anymore.

Use `jq -s '.[0]."minecraft:block".entries * .[1] | to_entries | sort_by(.value.protocol_id) | from_entries' registries.json blocks.json > blocks_protocol.json` to get the sorted version.

## `items.json`

As of `18w50a` `items.json` isn't generated anymore but instead has been replaced with `registries.json`.

Use `jq '."minecraft:item".entries | to_entries | sort_by(.value.protocol_id) | from_entries' registries.json > items.json` to extract the items from `registries.json` into `items.json`.
