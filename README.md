# Preply — Breakage Estimation (Analytics Engineer Case Study)

A dbt project that estimates breakage revenue per subscription payment,
refreshed daily while a payment's cycle is still open, replaced by the
known actual once it closes — built for Preply's Analytics Engineer
take-home case study.

**Start here → [`dbt/README.md`](dbt/README.md)**
for how to run the project and a description of the data model.

The dashboard mockup is [`breakage_dashboard.html`](breakage_dashboard.html)
— a standalone file, open it in any browser. The written summary and AI
usage note are a short slide deck, submitted alongside this repo.

## Repo layout

```
dbt/                       the dbt project — staging, intermediate, marts, tests
breakage_dashboard.html    the PayOps dashboard mockup, built on the mart
```
