# dataform

BigQuery transformations, using [Dataform](https://cloud.google.com/dataform) (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

Currently a skeleton: `workflow_settings.yaml` only (Dataform 3.x resolves `@dataform/core`
from `dataformCoreVersion` there — no `package.json`/`node_modules` needed), with an empty
`definitions/` directory, so `dataform compile` succeeds without a live BigQuery connection.

Models land here once raw weather data is actually flowing into GCS/BigQuery from the
ingestion service.
