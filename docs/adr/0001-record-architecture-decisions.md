# 1. Record architecture decisions

Date: 2026-07-28

## Status

Accepted

## Context

This project is a long-lived, incrementally evolving reference implementation (see [docs/vision.md](../vision.md)). Decisions about architecture, tooling, and process will be made throughout its life, often before the surrounding code exists to justify them by example. Without a record, the reasoning behind a decision is easily lost or misremembered, and later contributors (including a future version of the original author) end up re-litigating settled questions or, worse, silently reversing them without understanding why they were made.

## Decision

We will record architecturally significant decisions as Architecture Decision Records (ADRs), one Markdown file per decision, numbered sequentially in `docs/adr/`. Each ADR follows Michael Nygard's format: Title, Date, Status, Context, Decision, Consequences.

An ADR is superseded, not edited, when a decision changes — the old ADR stays in place with its status updated to `Superseded by ADR-00XX`, preserving the history of *why* the project changed direction.

## Consequences

- Every non-trivial architecture or process decision gets a short, dated, discoverable record.
- The `docs/adr/` directory becomes a readable history of the project's engineering judgment over time — useful both for future contributors and as a portfolio artifact in its own right.
- Adds a small amount of overhead per decision, which is intentional: it forces the decision to be articulated, not just made.
