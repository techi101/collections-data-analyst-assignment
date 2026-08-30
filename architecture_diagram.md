# Production Analytics Architecture

This diagram outlines how the analytical system will operate in production on a daily basis.

```mermaid
flowchart TD
    %% Data Sources
    subgraph Raw [Raw Data Sources]
        A1(Dialer / Telephony)
        A2(WhatsApp / SMS APIs)
        A3(Field App DB)
        A4(Core Banking / Payments)
    end

    %% Staging & Ingestion
    subgraph Staging [Staging Layer - S3 / Data Lake]
        B1[(Raw Events)]
        B2[(Raw Accounts)]
        B3[(Raw Agents)]
    end

    %% Data Pipeline & Transformation
    subgraph Clean [Processing Engine - dbt / Spark]
        C1[Deduplication & Entity Resolution]
        C2[Timezone Normalization to UTC]
        C3[Late-Arriving Data Handler]
    end

    %% Golden Dataset Layer
    subgraph Golden [Golden Dataset - Data Warehouse]
        D1[(dim_accounts)]
        D2[(dim_agents)]
        D3[(fact_payments)]
        D4[(fact_communications)]
    end
    
    %% Serving Layer
    subgraph Serving [Metrics & Features]
        E1[Aggregated Monthly Metrics]
        E2[Agent Performance Features]
        E3[Anomaly Detection Module]
    end

    %% Consumption
    subgraph Dashboard [Consumption]
        F1((CEO Executive Dashboard))
        F2((Operations Dashboard))
    end

    Raw -->|Batch / Streaming| Staging
    Staging --> Clean
    Clean --> Golden
    Golden --> Serving
    Serving --> Dashboard

    %% Error Handling
    Clean -.->|Rejected Records| G1[Data Quality Logs]
```

## Production Design Notes
- **Data Contracts**: Upstream APIs must enforce schema validation. Any schema changes (like `schema_version` in telephony) trigger alerts rather than silently breaking downstream.
- **Primary Keys & Deduplication**: Incremental processing models will upsert on primary keys (`payment_reference`, `borrower_id`) to naturally handle retries and duplicates.
- **Timezones**: All events are normalized to UTC at the staging layer. Dashboards apply local timezone formatting on the client side.
- **Monitoring**: Anomaly detection runs on the `Aggregated Monthly Metrics` layer to catch sudden drops in the denominator (active accounts) or spikes in duplicate payment hashes.
