# CrowdSec Grafana Dashboard Datasource UID Fix Report
**Date:** 2025-10-18
**Status:** ✅ SUCCESSFULLY COMPLETED

## Problem Identified
- **Issue:** CrowdSec dashboards referenced non-existent datasource UIDs
- **Impact:** All 33 panels showing "No data" / 404 errors
- **Root Cause:** Dashboard datasource UIDs didn't match the actual Prometheus datasource UID

## Wrong UIDs Found
1. `PBFA97CFB590B2093` - Found in all three dashboards (92 occurrences total)
   - crowdsec-overview.json: 37 occurrences
   - crowdsec-details.json: 34 occurrences
   - crowdsec-lapi.json: 21 occurrences

2. `IH0jqv6nz` - Found in crowdsec-details.json only (8 occurrences)

## Correct UID
- **Prometheus Datasource UID:** `prometheus-uid`

## Changes Made

### Files Modified
1. `/workspaces/jacker/config/grafana/provisioning/dashboards/crowdsec-overview.json`
   - Replaced 37 instances of `PBFA97CFB590B2093` with `prometheus-uid`

2. `/workspaces/jacker/config/grafana/provisioning/dashboards/crowdsec-details.json`
   - Replaced 34 instances of `PBFA97CFB590B2093` with `prometheus-uid`
   - Replaced 8 instances of `IH0jqv6nz` with `prometheus-uid`
   - Total: 42 datasource references now corrected

3. `/workspaces/jacker/config/grafana/provisioning/dashboards/crowdsec-lapi.json`
   - Replaced 21 instances of `PBFA97CFB590B2093` with `prometheus-uid`

### Deployment Steps
1. Created backups of all dashboard files (.bak extension)
2. Used sed for reliable bulk UID replacement
3. Verified replacements locally (0 occurrences of wrong UIDs)
4. Deployed corrected files to VPS1 (193.70.40.21)
5. Restarted Grafana container to trigger re-provisioning
6. Validated fix through Grafana API and logs

## Verification Results

### ✅ Quality Gates Passed
- [x] Zero occurrences of "PBFA97CFB590B2093" in all dashboard files
- [x] Zero occurrences of "IH0jqv6nz" in all dashboard files
- [x] All dashboards reference "prometheus-uid" (100 total references)
- [x] No 404 datasource errors in Grafana logs
- [x] Grafana can query Prometheus datasource successfully (HTTP 200)
- [x] All three CrowdSec dashboards accessible in Grafana UI
- [x] Test query executed successfully with data returned

### Dashboard Status
- **Crowdsec Overview** (UID: hjmZdB4nk) - ✅ Accessible (ID: 5)
- **Crowdsec Details per instance** (UID: 6L2GdB47z) - ✅ Accessible (ID: 3)
- **LAPI Metrics** (UID: ofdKJG37k) - ✅ Accessible (ID: 4)

### Datasource Status
- **Prometheus** (UID: prometheus-uid) - ✅ Active at http://prometheus:9090

### Test Query Results
```json
{
  "status": 200,
  "frames": 1,
  "error": null
}
```
Query: `crowdsec_lapi_decisions_info`
Result: Successfully retrieved data from Prometheus

## Final State
- **Total UIDs Corrected:** 100 datasource references
- **Dashboards Functional:** 3/3 (100%)
- **Panels Affected:** All 33 panels now have access to correct datasource
- **Grafana Logs:** Clean, no datasource-related errors
- **Production Status:** Deployed and operational on VPS1

## Backup Files Created
- crowdsec-overview.json.bak
- crowdsec-details.json.bak
- crowdsec-lapi.json.bak

## Recommendations
1. ✅ Dashboards are now fully functional
2. Monitor dashboard panels over next 24 hours to ensure data display
3. Consider adding datasource UID validation to deployment pipeline
4. Keep backup files for rollback capability if needed

---
**Report Generated:** 2025-10-18 04:15:00 UTC
**Executed By:** Configuration Management Expert
**Environment:** VPS1 (193.70.40.21)
