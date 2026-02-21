# Baseball Report Agent - Data Processing Scripts

This directory contains R scripts for processing Statcast data and generating report outputs.

## Scripts

- **`process_statcast.R`** — Main data processor. Reads raw Statcast CSV files, calculates aggregate metrics, and outputs structured data for report generation.
- **`calculate_metrics.R`** — Helper functions for computing percentile ranks, zone-by-zone breakdowns, pitch-specific stats, and trend analysis.
- **`generate_report.R`** — Takes processed data and populates report templates with formatted markdown output.

## Usage

Run the main pipeline:
```r
source("scripts/process_statcast.R")
```

This orchestrates:
1. Data loading and cleaning
2. Player/pitcher segmentation
3. Metric calculation
4. Report template population
5. Output to `/reports`

## Data Requirements

See `DATA_FORMAT.md` for input file specifications.
