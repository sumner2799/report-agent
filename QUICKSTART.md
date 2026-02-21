# Quick Start Guide - Report Generation Workflow

## What You Have
✅ **Report Templates** (Markdown) — ready for population  
✅ **Data Processing Scripts** (R) — automated metric calculation  
✅ **Tracking System** — to monitor players and calibrate thresholds  
✅ **Folder Structure** — organized data flow  

---

## Workflow for Weekly Reports

### Step 1: Prepare Data
1. Export Statcast data (from Baseball Savant or your data source)
2. Save as CSV in `/data/raw/` with naming convention: `statcast_[START_DATE]_[END_DATE].csv`
3. Reference: [Data Format Spec](.system/DATA_FORMAT.md)

### Step 2: Run the Pipeline
Execute the processing script:
```bash
Rscript scripts/process_statcast.R
```

Or use the VS Code task (setup instructions in next section).

### Step 3: Review Generated Reports
- Reports appear in `/reports/`
- File names: `YYYY-MM-DD_newprofile_[player-name].md` or `YYYY-MM-DD_trend_[player-name].md`
- Open in VS Code and review

### Step 4: Provide Feedback
- **Edit reports directly** if you want to add/modify sections
- **Note changes** in [.system/REPORT_INDEX.md](.system/REPORT_INDEX.md) feedback log
- **Iterate** — I'll refine templates and scripts based on your preferences

### Step 5: Update Tracking
- Add completed reports to [Report Index](.system/REPORT_INDEX.md)
- Document any threshold adjustments learned

---

## Setting Up a VS Code Task (Optional)

To run reports directly from VS Code:

1. **Create/edit** `.vscode/tasks.json` in the repo root:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Generate Weekly Reports",
      "type": "shell",
      "command": "Rscript",
      "args": ["scripts/process_statcast.R"],
      "group": {
        "kind": "build",
        "isDefault": true
      },
      "presentation": {
        "echo": true,
        "reveal": "always"
      }
    }
  ]
}
```

2. **Run task** from VS Code: `Ctrl+Shift+B` (or `Cmd+Shift+B` on Mac) → Select "Generate Weekly Reports"

---

## Calibration Phase (First Few Reports)

For the first 2-3 reports, do this manually:

1. **Generate** reports using the script (they'll be ~80% complete with metrics populated)
2. **Edit** the reports: add your analysis, observations, and context
3. **Note differences** between template and what you actually wrote
4. **Tell me:** What did I miss? What should be automated? What thresholds feel right?
5. **I'll refine** the script based on your feedback

---

## File Structure Reference

```
report-agent/
├── data/
│   ├── raw/                    ← Place Statcast CSV files here
│   └── processed/              ← Script outputs (intermediate)
├── reports/                    ← Generated reports go here
├── scripts/
│   ├── process_statcast.R      ← Main pipeline (run this)
│   ├── calculate_metrics.R     ← Helper functions
│   └── README.md
├── templates/
│   ├── new_player_profile_pitcher.md
│   ├── new_player_profile_hitter.md
│   └── trend_analysis.md
├── .system/
│   ├── REPORT_INDEX.md         ← Track all reports + thresholds
│   └── DATA_FORMAT.md          ← Data spec
└── OPERATING-FRAMEWORK.md      ← Your analytical philosophy
```

---

## Next Steps

1. **Test with sample data** — Get some Statcast CSV data and run the pipeline
2. **Generate first report** — See what the script produces
3. **Provide feedback** — Tell me what to refine
4. **Iterate** — We'll improve it each week

---

## Questions?

Refer to:
- [Data Format](./system/DATA_FORMAT.md) — For data requirements
- [Report Index](.system/REPORT_INDEX.md) — For tracking & thresholds
- [Scripts README](scripts/README.md) — For technical details
