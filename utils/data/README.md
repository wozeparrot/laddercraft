# Registry Data

## `items.json`

As of `18w50a` `items.json` isn't generated anymore but instead has been replaced with `registries.json`.

Use `jq '."minecraft:item".entries' registries.json > items.json` to extract the items from `registries.json` into `items.json`.
