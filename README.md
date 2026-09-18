# Preply — Breakage Estimation (Analytics Engineer Case Study)

A dbt project that estimates breakage revenue per subscription payment,
refreshed daily while a payment's cycle is still open, replaced by the
known actual once it closes — built for Preply's Analytics Engineer
take-home case study.

**Start here → [`dbt/README.md`](dbt/README.md)**
for how to run the project and a description of the data model.

The other two deliverables are standalone HTML files — open either in any
browser, no server or build step:
[`breakage_dashboard.html`](breakage_dashboard.html) (the PayOps dashboard
mockup) and [`case_summary_slides.html`](case_summary_slides.html) (the
written summary and AI usage note).

## Repo layout

```
dbt/                       the dbt project — staging, intermediate, marts, tests
breakage_dashboard.html    the PayOps dashboard mockup, built on the mart
case_summary_slides.html   written summary + AI usage note, as slides
```
